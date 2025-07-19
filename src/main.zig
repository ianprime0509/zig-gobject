const std = @import("std");
const builtin = @import("builtin");
const gir = @import("gir.zig");
const translate = @import("translate.zig");
const log = std.log;
const mem = std.mem;
const Allocator = mem.Allocator;

const usage =
    \\Usage: translate-gir [options] [root...]
    \\
    \\Generates bindings for the given root namespaces and their dependencies.
    \\
    \\Options:
    \\  -h, --help                          Show this help
    \\      --bindings-dir DIR              Add a directory to the bindings search path (for manual bindings)
    \\      --extensions-dir DIR            Add a directory to the extensions search path
    \\      --gir-dir DIR                   Add a directory to the GIR search path
    \\      --gir-fixes-dir DIR             Add a directory to the GIR fixes search path
    \\      --output-dir DIR                Set the output directory
    \\      --abi-test-output-dir DIR       Set the output directory for ABI tests
    \\      --dependency-file PATH          Generate a dependency file
    \\
;

var log_tty_config: std.io.tty.Config = undefined; // Will be initialized immediately in main

pub const std_options: std.Options = .{
    .log_level = if (builtin.mode == .Debug) log.Level.debug else log.Level.info,
    .logFn = logImpl,
};

pub fn logImpl(
    comptime level: log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = if (scope == .default)
        comptime level.asText() ++ ": "
    else
        comptime level.asText() ++ "(" ++ @tagName(scope) ++ "): ";
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    const stderr = std.io.getStdErr().writer();
    log_tty_config.setColor(stderr, switch (level) {
        .err => .bright_red,
        .warn => .bright_yellow,
        .info => .bright_blue,
        .debug => .bright_magenta,
    }) catch return;
    stderr.writeAll(prefix) catch return;
    log_tty_config.setColor(stderr, .reset) catch return;
    stderr.print(format ++ "\n", args) catch return;
}

pub fn main() Allocator.Error!void {
    log_tty_config = std.io.tty.detectConfig(std.io.getStdErr());

    const allocator = std.heap.smp_allocator;

    var cli_arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer cli_arena_state.deinit();
    const cli_arena = cli_arena_state.allocator();

    var gir_dir_paths = std.ArrayList([]u8).init(cli_arena);
    var gir_fixes_dir_paths = std.ArrayList([]u8).init(cli_arena);
    var bindings_dir_paths = std.ArrayList([]u8).init(cli_arena);
    var extensions_dir_paths = std.ArrayList([]u8).init(cli_arena);
    var maybe_output_dir_path: ?[]u8 = null;
    var maybe_abi_test_output_dir_path: ?[]u8 = null;
    var maybe_dependency_file_path: ?[]u8 = null;
    var roots = std.ArrayList(gir.Include).init(cli_arena);

    var args: ArgIterator = .{ .args = try std.process.argsWithAllocator(cli_arena) };
    _ = args.next();
    while (args.next()) |arg| {
        switch (arg) {
            .option => |option| if (option.is('h', "help")) {
                std.io.getStdOut().writeAll(usage) catch {};
                std.process.exit(0);
            } else if (option.is(null, "bindings-dir")) {
                const path = args.optionValue() orelse fatal("expected value for --bindings-dir", .{});
                try bindings_dir_paths.append(try cli_arena.dupe(u8, path));
            } else if (option.is(null, "extensions-dir")) {
                const path = args.optionValue() orelse fatal("expected value for --extensions-dir", .{});
                try extensions_dir_paths.append(try cli_arena.dupe(u8, path));
            } else if (option.is(null, "gir-dir")) {
                const path = args.optionValue() orelse fatal("expected value for --gir-dir", .{});
                try gir_dir_paths.append(try cli_arena.dupe(u8, path));
            } else if (option.is(null, "gir-fixes-dir")) {
                const path = args.optionValue() orelse fatal("expected value for --gir-fixes-dir", .{});
                try gir_fixes_dir_paths.append(try cli_arena.dupe(u8, path));
            } else if (option.is(null, "output-dir")) {
                const path = args.optionValue() orelse fatal("expected value for --output-dir", .{});
                maybe_output_dir_path = try cli_arena.dupe(u8, path);
            } else if (option.is(null, "abi-test-output-dir")) {
                const path = args.optionValue() orelse fatal("expected value for --abi-test-output-dir", .{});
                maybe_abi_test_output_dir_path = try cli_arena.dupe(u8, path);
            } else if (option.is(null, "dependency-file")) {
                const path = args.optionValue() orelse fatal("expected value for --dependency-file", .{});
                maybe_dependency_file_path = try cli_arena.dupe(u8, path);
            } else {
                fatal("unrecognized option: {}", .{option});
            },
            .param => |param| {
                const sep_pos = mem.indexOfScalar(u8, param, '-') orelse fatal("invalid GIR repository name: {s}", .{param});
                try roots.append(.{
                    .name = try cli_arena.dupe(u8, param[0..sep_pos]),
                    .version = try cli_arena.dupe(u8, param[sep_pos + 1 ..]),
                });
            },
            .unexpected_value => |unexpected_value| fatal("unexpected value to --{s}: {s}", .{
                unexpected_value.option,
                unexpected_value.value,
            }),
        }
    }

    const output_dir_path = maybe_output_dir_path orelse fatal("no output directory provided", .{});
    if (roots.items.len == 0) fatal("no modules specified to codegen", .{});

    const repositories = repositories: {
        var diag: Diagnostics = .{ .allocator = allocator };
        defer diag.deinit();
        const repositories = try gir.findRepositories(
            allocator,
            gir_dir_paths.items,
            gir_fixes_dir_paths.items,
            roots.items,
            &diag,
        );
        diag.report("failed to find and parse GIR repositories", .{});
        break :repositories repositories;
    };
    defer allocator.free(repositories);
    defer for (repositories) |*repository| repository.deinit();

    var deps = Dependencies.init(allocator);
    defer deps.deinit();

    {
        var diag: Diagnostics = .{ .allocator = allocator };
        defer diag.deinit();
        try translate.createBuildFiles(
            allocator,
            repositories,
            output_dir_path,
            &deps,
            &diag,
        );
        diag.report("failed to create build file", .{});
    }

    {
        const src_output_dir_path = try std.fs.path.join(cli_arena, &.{ output_dir_path, "src" });
        var diag: Diagnostics = .{ .allocator = allocator };
        defer diag.deinit();
        try translate.createBindings(
            allocator,
            repositories,
            bindings_dir_paths.items,
            extensions_dir_paths.items,
            src_output_dir_path,
            &deps,
            &diag,
        );
        diag.report("failed to translate source files", .{});
    }

    if (maybe_abi_test_output_dir_path) |abi_test_output_dir_path| {
        var diag: Diagnostics = .{ .allocator = allocator };
        defer diag.deinit();
        try translate.createAbiTests(
            allocator,
            repositories,
            abi_test_output_dir_path,
            &deps,
            &diag,
        );
        diag.report("failed to create ABI tests", .{});
    }

    if (maybe_dependency_file_path) |dependency_file_path| {
        var diag: Diagnostics = .{ .allocator = allocator };
        defer diag.deinit();
        try writeDependencies(dependency_file_path, deps, &diag);
        diag.report("failed to create dependency file", .{});
    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    log.err(format, args);
    std.process.exit(1);
}

fn writeDependencies(path: []const u8, deps: Dependencies, diag: *Diagnostics) !void {
    var file = std.fs.cwd().createFile(path, .{}) catch |err|
        return diag.add("failed to create dependency file {s}: {}", .{ path, err });
    defer file.close();

    var buffered_writer = std.io.bufferedWriter(file.writer());
    deps.write(buffered_writer.writer()) catch |err|
        return diag.add("failed to write dependency file {s}: {}", .{ path, err });
    buffered_writer.flush() catch |err|
        return diag.add("failed to write dependency file {s}: {}", .{ path, err });
}

pub const Dependencies = struct {
    paths: std.StringArrayHashMapUnmanaged(std.ArrayListUnmanaged([]u8)) = .{},
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: Allocator) Dependencies {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(deps: *Dependencies) void {
        deps.arena.deinit();
        deps.* = undefined;
    }

    pub fn add(deps: *Dependencies, target: []const u8, dependencies: []const []const u8) Allocator.Error!void {
        const arena = deps.arena.allocator();
        const gop = try deps.paths.getOrPut(arena, target);
        if (!gop.found_existing) {
            gop.key_ptr.* = try arena.dupe(u8, target);
            gop.value_ptr.* = .{};
        }
        try gop.value_ptr.ensureUnusedCapacity(arena, dependencies.len);
        for (dependencies) |dependency| {
            gop.value_ptr.appendAssumeCapacity(try arena.dupe(u8, dependency));
        }
    }

    pub fn addRepository(deps: *Dependencies, target: []const u8, repository: gir.Repository) Allocator.Error!void {
        try deps.add(target, &.{repository.path});
        if (repository.fix_path) |fix_path| try deps.add(target, &.{fix_path});
    }

    pub fn write(deps: Dependencies, writer: anytype) @TypeOf(writer).Error!void {
        for (deps.paths.keys(), deps.paths.values()) |target, prereqs| {
            try writer.print("{s}:", .{target});
            for (prereqs.items) |prereq| {
                try writer.print(" {s}", .{prereq});
            }
            try writer.writeByte('\n');
        }
    }
};

pub const Diagnostics = struct {
    errors: std.ArrayListUnmanaged([]u8) = .{},
    allocator: Allocator,

    pub fn deinit(diag: *Diagnostics) void {
        for (diag.errors.items) |err| diag.allocator.free(err);
        diag.errors.deinit(diag.allocator);
        diag.* = undefined;
    }

    pub fn add(diag: *Diagnostics, comptime fmt: []const u8, args: anytype) Allocator.Error!void {
        const formatted = try std.fmt.allocPrint(diag.allocator, fmt, args);
        errdefer diag.allocator.free(formatted);
        try diag.errors.append(diag.allocator, formatted);
    }

    /// Report any errors present and fail if any are present.
    fn report(diag: Diagnostics, comptime fmt: []const u8, args: anytype) void {
        if (diag.errors.items.len > 0) {
            for (diag.errors.items) |err| {
                log.err("{s}", .{err});
            }
            fatal(fmt, args);
        }
    }
};

// Inspired by https://github.com/judofyr/parg
const ArgIterator = struct {
    args: std.process.ArgIterator,
    state: union(enum) {
        normal,
        short: []const u8,
        long: struct {
            option: []const u8,
            value: []const u8,
        },
        params_only,
    } = .normal,

    const Arg = union(enum) {
        option: union(enum) {
            short: u8,
            long: []const u8,

            fn is(option: @This(), short: ?u8, long: ?[]const u8) bool {
                return switch (option) {
                    .short => |c| short == c,
                    .long => |s| mem.eql(u8, long orelse return false, s),
                };
            }

            pub fn format(option: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
                switch (option) {
                    .short => |c| try writer.print("-{c}", .{c}),
                    .long => |s| try writer.print("--{s}", .{s}),
                }
            }
        },
        param: []const u8,
        unexpected_value: struct {
            option: []const u8,
            value: []const u8,
        },
    };

    fn deinit(iter: *ArgIterator) void {
        iter.args.deinit();
        iter.* = undefined;
    }

    fn next(iter: *ArgIterator) ?Arg {
        switch (iter.state) {
            .normal => {
                const arg = iter.args.next() orelse return null;
                if (mem.eql(u8, arg, "--")) {
                    iter.state = .params_only;
                    return .{ .param = iter.args.next() orelse return null };
                } else if (mem.startsWith(u8, arg, "--")) {
                    if (mem.indexOfScalar(u8, arg, '=')) |equals_index| {
                        const option = arg["--".len..equals_index];
                        iter.state = .{ .long = .{
                            .option = option,
                            .value = arg[equals_index + 1 ..],
                        } };
                        return .{ .option = .{ .long = option } };
                    } else {
                        return .{ .option = .{ .long = arg["--".len..] } };
                    }
                } else if (mem.startsWith(u8, arg, "-") and arg.len > 1) {
                    if (arg.len > 2) {
                        iter.state = .{ .short = arg["-".len + 1 ..] };
                    }
                    return .{ .option = .{ .short = arg["-".len] } };
                } else {
                    return .{ .param = arg };
                }
            },
            .short => |rest| {
                if (rest.len > 1) {
                    iter.state = .{ .short = rest[1..] };
                }
                return .{ .option = .{ .short = rest[0] } };
            },
            .long => |long| return .{ .unexpected_value = .{
                .option = long.option,
                .value = long.value,
            } },
            .params_only => return .{ .param = iter.args.next() orelse return null },
        }
    }

    fn optionValue(iter: *ArgIterator) ?[]const u8 {
        switch (iter.state) {
            .normal => return iter.args.next(),
            .short => |rest| {
                iter.state = .normal;
                return rest;
            },
            .long => |long| {
                iter.state = .normal;
                return long.value;
            },
            .params_only => unreachable,
        }
    }
};

test {
    _ = translate;
}
