const std = @import("std");
pub const b = @import("commands/build.zig");

test "root" {
    std.testing.refAllDecls(@This());

}
