const std = @import("std");
const md = @import("../core/markdown.zig");
const Ctx = @import("../core/ctx.zig").Ctx;

pub fn discoverProjectRoot(allocator: std.mem.Allocator, cwd: []const u8, project_arg: ?[]const u8) ![]const u8 {
    if (project_arg) |p| if (try validateRoot(allocator, p)) |res| return res;
    if (try getEnvOwned(allocator, "HOLLOW_ROOT")) |env_root| {
        defer allocator.free(env_root);
        if (try validateRoot(allocator, env_root)) |res| return res;
    }
    return try upwardSearch(allocator, cwd);
}

fn validateRoot(allocator: std.mem.Allocator, path_in: []const u8) !?[]const u8 {
    const abs = try toAbsoluteReal(allocator, path_in);
    var d = std.fs.openDirAbsolute(abs, .{ .iterate = false }) catch return null;
    defer d.close();
    const cfg_path = try std.fs.path.join(allocator, &[_][]const u8{ abs, "hollow.toml" });
    const cfg_file = std.fs.openFileAbsolute(cfg_path, .{}) catch {
        allocator.free(cfg_path);
        return null;
    };
    defer allocator.free(cfg_path);
    cfg_file.close();
    return abs;
}

fn toAbsoluteReal(allocator: std.mem.Allocator, path_in: []const u8) ![]const u8 {
    var buf_opt: ?[]u8 = null;
    defer if (buf_opt) |b| allocator.free(b);
    var path = path_in;
    if (path.len >= 2 and path[0] == '~' and path[1] == '/') {
        if (try getEnvOwned(allocator, "HOME")) |home| {
            buf_opt = try std.fs.path.join(allocator, &[_][]const u8{ home, path[2..] });
            allocator.free(home);
            path = buf_opt.?;
        }
    }
    const abs = if (std.fs.path.isAbsolute(path)) try std.fs.realpathAlloc(allocator, path) else blk: {
        const proc_cwd_buf = try std.fs.cwd().realpathAlloc(allocator, ".");
        defer allocator.free(proc_cwd_buf);
        const joined = try std.fs.path.join(allocator, &[_][]const u8{ proc_cwd_buf, path });
        const rp = std.fs.realpathAlloc(allocator, joined) catch |e| {
            allocator.free(joined);
            return e;
        };
        allocator.free(joined);
        break :blk rp;
    };
    return abs;
}

fn getEnvOwned(allocator: std.mem.Allocator, name: []const u8) !?[]u8 {
    return std.process.getEnvVarOwned(allocator, name) catch |e| switch (e) {
        error.EnvironmentVariableNotFound => null,
        else => e,
    };
}

fn upwardSearch(allocator: std.mem.Allocator, start_cwd: []const u8) ![]const u8 {
    var curr = try toAbsoluteReal(allocator, start_cwd);
    defer allocator.free(curr);
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        if (try validateRoot(allocator, curr)) |res| return res;
        const maybe_parent = std.fs.path.dirname(curr);
        if (maybe_parent == null) break;
        const parent = maybe_parent.?;
        if (std.mem.eql(u8, parent, curr)) break;
        const new_curr = try allocator.dupe(u8, parent);
        allocator.free(curr);
        curr = new_curr;
    }
    return error.ProjectRootNotFound;
}

pub fn run(ctx: *Ctx) !void {
    const proc_cwd_buf = try ctx.cwd.realpathAlloc(ctx.allocator, ".");
    defer ctx.allocator.free(proc_cwd_buf);
    const root = try discoverProjectRoot(ctx.allocator, proc_cwd_buf, null);
    ctx.project_root = root;
    try setOutDir(ctx);
    const mdFiles = try findMdFiles(ctx);
    defer ctx.allocator.free(mdFiles);
    for (mdFiles) |entry| {
        defer ctx.allocator.free(entry.absPath);
        defer ctx.allocator.free(entry.relPath);
        try mdToHtml(ctx, entry);
    }
}

fn setOutDir(ctx: *Ctx) !void {
    const o = try std.fs.path.join(ctx.allocator, &.{ ctx.project_root.?, "out" });
    try ctx.cwd.makePath(o);
}

const MdFile = struct {
    absPath: []const u8,
    relPath: []const u8,
};

fn findMdFiles(ctx: *Ctx) ![]MdFile {
    var out = std.ArrayList(MdFile).init(ctx.allocator);
    defer out.deinit();
    const rootAsDir = try std.fs.openDirAbsolute(ctx.project_root.?, .{ .iterate = true });
    var walker = try rootAsDir.walk(ctx.allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        const ext = std.fs.path.extension(entry.basename);
        const abs = try std.fs.path.join(ctx.allocator, &.{ ctx.project_root.?, entry.path });
        if (std.mem.eql(u8, ext, ".md")) {
            try out.append(MdFile{ .absPath = abs, .relPath = try ctx.allocator.dupe(u8, entry.path) });
        }
    }
    return out.toOwnedSlice();
}

fn mdToHtml(ctx: *Ctx, md_file: MdFile) !void {
    const curr = try ctx.cwd.openFile(md_file.absPath, .{});
    const end = try curr.getEndPos();
    const file_buf = try ctx.allocator.alloc(u8, end);
    defer ctx.allocator.free(file_buf);
    _ = try curr.readAll(file_buf);
    const out_file = try make_out_file(ctx, md_file);
    var out_file_handle = try std.fs.openFileAbsolute(out_file, .{ .mode = .read_write });
    defer ctx.allocator.free(out_file);
    defer out_file_handle.close();
    _ = md.md_html(file_buf.ptr, file_buf.len, md.hmtl_callback, @ptrCast(&out_file_handle), 0, 0);
    //std.debug.print("out file: {s}\n", .{out_file});
}

fn make_out_file(ctx: *Ctx, md_file: MdFile) ![]const u8 {
    const content_root = try std.fs.path.join(ctx.allocator, &.{ ctx.project_root.?, "content" });
    const path_from_content_root = try std.fs.path.relative(ctx.allocator, content_root, md_file.relPath);
    const path_to_out_file = try std.fs.path.join(ctx.allocator, &.{ ctx.project_root.?, "out", path_from_content_root });
    const dir_of_out_file = std.fs.path.dirname(path_to_out_file).?;
    const out_file_name = std.fs.path.stem(path_to_out_file);
    var sb = std.ArrayList(u8).init(ctx.allocator);
    defer sb.deinit();
    try sb.appendSlice(out_file_name);
    try sb.appendSlice(".html");
    const out_html_file = try sb.toOwnedSlice();
    const final_out_path = try std.fs.path.join(ctx.allocator, &.{ dir_of_out_file, out_html_file });
    _ = try ctx.cwd.makePath(dir_of_out_file);
    const f = try std.fs.cwd().createFile(final_out_path, .{ .truncate = true });
    defer ctx.allocator.free(content_root);
    defer ctx.allocator.free(path_from_content_root);
    defer ctx.allocator.free(path_to_out_file);
    defer ctx.allocator.free(out_file_name);
    defer ctx.allocator.free(out_html_file);
    defer ctx.allocator.free(dir_of_out_file);
    defer f.close();
    return final_out_path;
}

fn chdirScoped(a: std.mem.Allocator, into: []const u8) !void {
    const prev = try std.process.getCwdAlloc(a);
    defer a.free(prev);
    try std.posix.chdir(into);
    errdefer std.posix.chdir(prev);
}

//test "Discover root in parent of parent" {
//    const a = std.testing.allocator;
//    var tmp = std.testing.tmpDir(.{});
//    defer tmp.cleanup();
//    try tmp.dir.makePath("proj/sub/leaf");
//    try tmp.dir.writeFile(.{ .sub_path = "proj/hollow.toml", .data = "" });
//    const start = try tmp.dir.realpathAlloc(a, "proj/sub/leaf");
//    defer a.free(start);
//    try chdirScoped(a, start);
//    var got = try discoverProjectRoot(a, start, null);
//    const want = try tmp.dir.realpathAlloc(a, "proj");
//    defer a.free(want);
//    defer got.deinit();
//    try std.testing.expectEqualStrings(want, got);
//}

//test "MD To HTML" {
//    const alloc = std.testing.allocator;
//    var tmp = std.testing.tmpDir(.{});
//    defer tmp.cleanup();
//    try tmp.dir.makePath("proj/");
//    try tmp.dir.makePath("proj/sub/");
//    try tmp.dir.writeFile(.{ .sub_path = "proj/hollow.md", .data = "# HI" });
//    try tmp.dir.writeFile(.{ .sub_path = "proj/sub/a.md", .data = "## HELLO" });
//    try tmp.dir.writeFile(.{ .sub_path = "proj/hollow.toml", .data = "" });
//    const start = try tmp.dir.realpathAlloc(alloc, "proj/");
//    defer alloc.free(start);
//    try chdirScoped(alloc, start);
//    const root = try discoverProjectRoot(alloc, start, null);
//    std.debug.print("ROOT: {s}", .{root});
//    defer alloc.free(root);
//    const mdFiles = try findMdFiles(alloc, root);
//    defer alloc.free(mdFiles);
//    for (mdFiles) |entry| {
//        defer alloc.free(entry.absPath);
//        defer alloc.free(entry.relPath);
//        const curr = try std.fs.cwd().openFile(entry.absPath, .{});
//        const end = try curr.getEndPos();
//        const fileBuf = try alloc.alloc(u8, end);
//        defer alloc.free(fileBuf);
//        _ = try curr.readAll(fileBuf);
//        var outBuf = std.ArrayList(u8).init(alloc);
//        defer outBuf.deinit();
//        _ = md.md_html(fileBuf.ptr, fileBuf.len, md.hmtl_callback, @ptrCast(&outBuf), 0, 0);
//        std.debug.print("MD File: {s}\n", .{outBuf.items});
//    }
//}

//test "Find MD files" {
//    const a = std.testing.allocator;
//    var tmp = std.testing.tmpDir(.{});
//    defer tmp.cleanup();
//    try tmp.dir.makePath("proj/");
//    try tmp.dir.makePath("proj/sub/");
//    try tmp.dir.writeFile(.{ .sub_path = "proj/hollow.md", .data = "" });
//    try tmp.dir.writeFile(.{ .sub_path = "proj/sub/a.md", .data = "" });
//    try tmp.dir.writeFile(.{ .sub_path = "proj/hollow.toml", .data = "" });
//    const start = try tmp.dir.realpathAlloc(a, "proj/");
//    defer a.free(start);
//    try chdirScoped(a, start);
//    var root = try discoverProjectRoot(a, start, null);
//    defer root.deinit();
//    const mdFiles = try findMdFiles(a, root);
//    defer a.free(mdFiles);
//    for (mdFiles) |f| {
//        defer a.free(f.relPath);
//        defer a.free(f.absPath);
//        std.debug.print("{s}\n", .{f.relPath});
//        std.debug.print("{s}\n", .{f.absPath});
//    }
//}
