const std = @import("std");
const Ctx = @import("../core/ctx.zig").Ctx;

pub fn run(ctx: *const Ctx, opts: InitOpts) !Project {
    const a = ctx.allocator;
    const root = opts.project_root orelse ".";
    try ctx.cwd.makePath(root);
    const cfg_file = try std.fs.path.join(a, &.{ root, "hollow.toml" });
    defer a.free(cfg_file);

    if (try fileExists(cfg_file) and !opts.force) {
        return Project{
            .root_path = try a.dupe(u8, root),
            .config_path = try a.dupe(u8, cfg_file),
        };
    }
    const dirs = [_][]const u8{ "content", "layouts", "public", "themes/default", ".hollow/cache", "templates" };
    for (dirs) |d| {
        const p = try std.fs.path.join(a, &.{ root, d });
        defer a.free(p);
        try ctx.cwd.makePath(p);
    }

    const base_index_file = try std.fs.path.join(a, &.{ root, "content", "index.md" });
    const default_template_file = try std.fs.path.join(a, &.{ root, "templates", "default.html" });
    defer a.free(base_index_file);

    const default_index =
        \\---
        \\ title: Index Page
        \\ date: 2025-11-11
        \\---
        \\# Hollow
        \\
        \\Hollow is a minimal static site generator focused on clarity over features.
        \\
        \\It takes Markdown content, renders it through a small, explicit template contract, and writes predictable HTML output. No plugins, no magic, no hidden state.
        \\
        \\## Philosophy
        \\
        \\- One clear build path  
        \\- Explicit data flow  
        \\- Boring, debuggable behavior  
        \\
        \\If you can trace the build in your head, Hollow is doing its job.
    ;

    const default_cfg =
        \\[project]
        \\name = "hollow-site"
        \\version = "0.1.0"
        \\[paths]
        \\content = "content"
        \\public = "public"
    ;

    const default_template =
        \\<html>
        \\  <head><title>{{ title }}</title></head>
        \\  <body>
        \\  <time datetime="{{ date }}">{{ date }}</time>
        \\    {{ content }}
        \\  </body>
        \\</html>
    ;

    try writeAll(cfg_file, default_cfg);
    try writeAll(base_index_file, default_index);
    try writeAll(default_template_file, default_template);
    return Project{ .root_path = try a.dupe(u8, root), .config_path = try a.dupe(u8, cfg_file) };
}

pub const InitOpts = struct {
    project_root: ?[]const u8 = null,
    force: bool = false,
};

pub const Project = struct {
    root_path: []const u8,
    config_path: []const u8,
};

fn fileExists(path: []const u8) !bool {
    const f = std.fs.cwd().openFile(path, .{}) catch |e| switch (e) {
        error.FileNotFound => return false,
        else => return e,
    };
    f.close();
    return true;
}

fn writeAll(path: []const u8, data: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(data);
}
