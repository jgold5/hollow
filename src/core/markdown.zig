const std = @import("std");

pub extern fn md_html(
    input: [*]const u8,
    input_size: usize,
    process_output: *const fn ([*]const u8, usize, *anyopaque) callconv(.C) void,
    userdata: *anyopaque,
    parser_flags: c_uint,
    renderer_flags: c_uint,
) c_int;

pub fn hmtl_callback(text: [*]const u8, size: usize, userdata: *anyopaque) callconv(.C) void {
    const file: *std.fs.File = @ptrCast(@alignCast(userdata));
    const chunk = text[0..size];
    _ = file.writeAll(chunk) catch {};
}
