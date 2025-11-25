const std = @import("std");

pub const md = @import("core/markdown.zig");
pub const b = @import("commands/build_cmd.zig");

test "root" {
    std.testing.refAllDecls(@This());
}
