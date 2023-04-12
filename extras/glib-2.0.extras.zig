const glib = @import("glib-2.0");

pub fn Bytes(comptime Self: type) type {
    return struct {
        pub fn newFromSlice(bytes: []const u8) *Self {
            // TODO: the const cast is only needed due to a mistranslation of the array type in new
            return Self.new(@constCast(bytes.ptr), bytes.len);
        }
    };
}
