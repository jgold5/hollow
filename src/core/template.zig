const std = @import("std");

pub fn applyTemplate(allocator: std.mem.Allocator, template: []const u8, content: []const u8) ![]const u8 {
    const start = std.mem.indexOf(u8, template, "{{").?;
    const end = std.mem.indexOf(u8, template, "}}").?;
    var sb = std.ArrayList(u8).init(allocator);
    defer sb.deinit();
    try sb.appendSlice(template[0..start]);
    try sb.appendSlice(content);
    try sb.appendSlice(template[(end + 2)..]);
    return try sb.toOwnedSlice();
}
