const std = @import("std");
const Ctx = @import("../core/ctx.zig").Ctx;

pub fn run(ctx: *const Ctx, opts: InitOpts) !Project {
    const a = ctx.allocator;
    const root = opts.project_root orelse ".";
    try ctx.cwd.makePath(root);
    const cfgRel = try std.fs.path.join(a, &.{ root, "hollow.toml" });
    defer a.free(cfgRel);

    if (try fileExists(cfgRel) and !opts.force) {
        return Project{
            .root_path = try a.dupe(u8, root),
            .config_path = try a.dupe(u8, cfgRel),
        };
    }
    const dirs = [_][]const u8{ "content", "layouts", "public", "themes/default", ".hollow/cache" };
    for (dirs) |d| {
        const p = try std.fs.path.join(a, &.{ root, d });
        defer a.free(p);
        try ctx.cwd.makePath(p);
    }

    const baseIndex = try std.fs.path.join(a, &.{ root, "content", "index.md" });
    defer a.free(baseIndex);

    const default_index =
        \\# Welcome
        \\This is your new hollow site.
        \\Edit content/index.md to get started
    ;

    const default_cfg =
        \\[project]
        \\name = "hollow-site"
        \\version = "0.1.0"
        \\[paths]
        \\content = "content"
        \\public = "public"
    ;
    try writeAll(cfgRel, default_cfg);
    try writeAll(baseIndex, default_index);
    return Project{ .root_path = try a.dupe(u8, root), .config_path = try a.dupe(u8, cfgRel) };
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
