const std = @import("std");
const builtin = @import("builtin");
const gir = @import("gir.zig");
const translate = @import("translate.zig");
const log = std.log;
const mem = std.mem;
const Allocator = mem.Allocator;

const usage =
    \\Usage: zig-gobject [options] [root...]
    \\
    \\Generates bindings for the given root namespaces and their dependencies.
    \\
    \\Options:
    \\  -h, --help                          Show this help
    \\      --bindings-dir DIR              Add a directory to the bindings search path (for manual bindings)
    \\      --extensions-dir DIR            Add a directory to the extensions search path
    \\      --gir-dir DIR                   Add a directory to the GIR search path
    \\      --output-dir DIR                Set the output directory
    \\      --abi-test-output-dir DIR       Set the output directory for ABI tests
;

var log_tty_config: std.io.tty.Config = undefined; // Will be initialized immediately in main

pub const std_options = struct {
    pub const log_level = if (builtin.mode == .Debug) log.Level.debug else log.Level.info;
    pub const logFn = logImpl;
};

pub fn logImpl(
    comptime level: log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = if (scope == .default)
        comptime level.asText() ++ ": "
    else
        comptime level.asText() ++ "(" ++ @tagName(scope) ++ "): ";
    const mutex = std.debug.getStderrMutex();
    mutex.lock();
    defer mutex.unlock();
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

    const allocator = std.heap.c_allocator;

    var gir_path = std.ArrayList(std.fs.Dir).init(allocator);
    defer gir_path.deinit();
    defer for (gir_path.items) |*dir| dir.close();
    var bindings_path = std.ArrayList(std.fs.Dir).init(allocator);
    defer bindings_path.deinit();
    defer for (bindings_path.items) |*dir| dir.close();
    var extensions_path = std.ArrayList(std.fs.Dir).init(allocator);
    defer extensions_path.deinit();
    defer for (extensions_path.items) |*dir| dir.close();
    var output_dir: ?std.fs.Dir = null;
    defer if (output_dir) |*dir| dir.close();
    var abi_test_output_dir: ?std.fs.Dir = null;
    defer if (abi_test_output_dir) |*dir| dir.close();
    var roots = std.ArrayList(gir.Include).init(allocator);
    defer roots.deinit();
    defer for (roots.items) |root| {
        allocator.free(root.name);
        allocator.free(root.version);
    };

    var args: ArgIterator = .{ .args = try std.process.argsWithAllocator(allocator) };
    defer args.deinit();
    _ = args.next();
    while (args.next()) |arg| {
        switch (arg) {
            .option => |option| if (option.is('h', "help")) {
                std.io.getStdOut().writeAll(usage) catch {};
                std.process.exit(0);
            } else if (option.is(null, "bindings-dir")) {
                const path = args.optionValue() orelse fatal("expected value for --bindings-dir", .{});
                const dir = std.fs.cwd().openDir(path, .{}) catch |err| fatal("failed to open bindings directory {s}: {}", .{ path, err });
                try bindings_path.append(dir);
            } else if (option.is(null, "extensions-dir")) {
                const path = args.optionValue() orelse fatal("expected value for --extensions-dir", .{});
                const dir = std.fs.cwd().openDir(path, .{}) catch |err| fatal("failed to open extensions directory {s}: {}", .{ path, err });
                try extensions_path.append(dir);
            } else if (option.is(null, "gir-dir")) {
                const path = args.optionValue() orelse fatal("expected value for --gir-dir", .{});
                const dir = std.fs.cwd().openDir(path, .{}) catch |err| fatal("failed to open GIR directory {s}: {}", .{ path, err });
                try gir_path.append(dir);
            } else if (option.is(null, "output-dir")) {
                const path = args.optionValue() orelse fatal("expected value for --output-dir", .{});
                output_dir = std.fs.cwd().makeOpenPath(path, .{}) catch |err| fatal("failed to open output directory {s}: {}", .{ path, err });
            } else if (option.is(null, "abi-test-output-dir")) {
                const path = args.optionValue() orelse fatal("expected value for --abi-test-output-dir", .{});
                abi_test_output_dir = std.fs.cwd().makeOpenPath(path, .{}) catch |err| fatal("failed to open ABI test output directory {s}: {}", .{ path, err });
            },
            .param => |param| {
                const sep_pos = mem.indexOfScalar(u8, param, '-') orelse fatal("invalid GIR repository name: {s}", .{param});
                try roots.append(.{
                    .name = try allocator.dupe(u8, param[0..sep_pos]),
                    .version = try allocator.dupe(u8, param[sep_pos + 1 ..]),
                });
            },
            .unexpected_value => |unexpected_value| fatal("unexpected value to --{s}: {s}", .{
                unexpected_value.option,
                unexpected_value.value,
            }),
        }
    }

    if (output_dir == null) fatal("no output directory provided", .{});
    var src_out_dir = output_dir.?.makeOpenPath("src", .{}) catch |err| fatal("failed to create output src directory: {}", .{err});
    defer src_out_dir.close();

    const repositories = repositories: {
        var diag: gir.Diagnostics = .{ .allocator = allocator };
        defer diag.deinit();
        const repositories = try gir.findRepositories(allocator, gir_path.items, roots.items, &diag);
        if (diag.errors.items.len > 0) {
            for (diag.errors.items) |err| {
                log.err("{s}", .{err});
            }
            fatal("failed to find and parse GIR repositories", .{});
        }
        break :repositories repositories;
    };
    defer allocator.free(repositories);
    defer for (repositories) |*repository| repository.deinit();
    translate.createBindings(allocator, repositories, bindings_path.items, extensions_path.items, src_out_dir) catch |err| fatal("failed to create bindings: {}", .{err});
    translate.createBuildFile(allocator, repositories, output_dir.?) catch |err| fatal("failed to create build file: {}", .{err});
    if (abi_test_output_dir) |dir| {
        translate.createAbiTests(allocator, repositories, dir) catch |err| fatal("failed to create ABI tests: {}", .{err});
    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    log.err(format, args);
    std.process.exit(1);
}

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
