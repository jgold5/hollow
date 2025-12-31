const std = @import("std");
const Ctx = @import("../core/ctx.zig").Ctx;
const ParsedMdFile = @import("../commands/build_cmd.zig").ParsedMdFile;

pub fn applyTemplate(allocator: std.mem.Allocator, template: []const u8, ctx: *const TemplateContext) ![]const u8 {
    var out_buf = std.ArrayList(u8).init(allocator);
    var i: usize = 0;
    while (true) {
        const open = std.mem.indexOfPos(u8, template, i, "{{") orelse {
            try out_buf.appendSlice(template[i..]);
            break;
        };
        try out_buf.appendSlice(template[i..open]);
        const close = std.mem.indexOfPos(u8, template, open + 2, "}}") orelse return error.UnclosedPlaceholder;
        const key = std.mem.trim(u8, template[open + 2 .. close], " \t");
        const value = ctx.values.get(key) orelse return error.MissingTemplateKey;
        try out_buf.appendSlice(value);
        i = close + 2;
    }
    return out_buf.toOwnedSlice();
}

pub fn buildTemplateContext(allocator: std.mem.Allocator, values_to_insert: std.StringHashMap([]const u8), rendered_html: []const u8) !TemplateContext {
    var value_map = std.StringHashMap([]const u8).init(allocator);
    var it = values_to_insert.iterator();
    while (it.next()) |entry| {
        try value_map.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    try value_map.put("content", rendered_html);
    return TemplateContext{ .values = value_map };
}

const TemplateContext = struct {
    values: std.StringHashMap([]const u8),
};
