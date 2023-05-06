const std = @import("std");
const c = @import("c.zig");
const Allocator = std.mem.Allocator;

pub fn parseBytes(bytes: []const u8, url: [:0]const u8) !*c.xmlDoc {
    return c.xmlReadMemory(bytes.ptr, @intCast(c_int, bytes.len), url, null, 0) orelse return error.InvalidXml;
}

pub fn parseFile(file: [:0]const u8) !*c.xmlDoc {
    return c.xmlReadFile(file.ptr, null, 0) orelse return error.InvalidXml;
}

pub fn nodeIs(node: *const c.xmlNode, ns_name: ?[:0]const u8, local_name: [:0]const u8) bool {
    if (!std.mem.eql(u8, local_name, std.mem.sliceTo(node.name, 0))) {
        return false;
    }
    if (ns_name) |n| {
        return node.ns != null and std.mem.eql(u8, n, std.mem.sliceTo(node.ns.*.href, 0));
    } else {
        return node.ns == null;
    }
}

pub fn nodeContent(allocator: Allocator, node: *const c.xmlNode) ![:0]u8 {
    const content = c.xmlNodeGetContent(node);
    defer free(content);
    if (content) |str| {
        return try allocator.dupeZ(u8, std.mem.sliceTo(str, 0));
    } else {
        return try allocator.dupeZ(u8, "");
    }
}

pub fn attrIs(attr: *const c.xmlAttr, ns_name: ?[:0]const u8, local_name: [:0]const u8) bool {
    if (!std.mem.eql(u8, local_name, std.mem.sliceTo(attr.name, 0))) {
        return false;
    }
    if (ns_name) |n| {
        return attr.ns != null and std.mem.eql(u8, n, std.mem.sliceTo(attr.ns.*.href, 0));
    } else {
        return attr.ns == null;
    }
}

pub fn attrContent(allocator: Allocator, attr: *const c.xmlAttr) ![:0]u8 {
    return try nodeContent(allocator, attr.children);
}

pub fn attrContentBool(allocator: Allocator, attr: *const c.xmlAttr) !bool {
    const raw = try attrContent(allocator, attr);
    defer allocator.free(raw);
    return std.mem.eql(u8, raw, "1");
}

pub fn attrContentInt(allocator: Allocator, comptime T: type, attr: *const c.xmlAttr) !T {
    const raw = try attrContent(allocator, attr);
    defer allocator.free(raw);
    return std.fmt.parseInt(T, raw, 10) catch return error.InvalidGir;
}

pub fn free(ptr: ?*anyopaque) void {
    c.xmlFree.?(ptr);
}
