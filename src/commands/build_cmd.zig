const std = @import("std");
const md = @import("../core/markdown.zig");
const Ctx = @import("../core/ctx.zig").Ctx;
const template = @import("../core/template.zig");
const log = std.log.scoped(.build);

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
    const mdFiles = try findMdFiles(ctx.allocator, ctx.project_root.?);
    defer ctx.allocator.free(mdFiles);
    try copyAssets(ctx);
    for (mdFiles) |entry| {
        const raw = try readMdFile(ctx.allocator, ctx.cwd, entry);
        var parsed = try parseMdFile(ctx.allocator, raw);
        printStringMap(parsed.meta);
        defer parsed.deinit(ctx.allocator);
        const out_file = try makeOutFile(ctx, entry);
        defer ctx.allocator.free(out_file);
        var out_handle = try std.fs.openFileAbsolute(out_file, .{ .mode = .read_write });
        defer out_handle.close();
        defer ctx.allocator.free(entry.absPath);
        defer ctx.allocator.free(entry.relPath);
        var content_arr = try mdToArr(ctx, parsed);
        content_arr = try insertBaseUrl(ctx.allocator, content_arr);
        const template_arr = try loadDefaultTemplate(ctx);
        var template_context = try template.buildTemplateContext(ctx.allocator, ctx.config, parsed.meta, content_arr);
        const content_with_frontmatter = try template.applyTemplate(ctx.allocator, template_arr, &template_context);
        const content_with_template = try template.applyTemplate(ctx.allocator, content_with_frontmatter, &template_context);
        try out_handle.writeAll(content_with_template);
        defer template_context.values.deinit();
        defer ctx.allocator.free(content_arr);
        defer ctx.allocator.free(template_arr);
        defer ctx.allocator.free(content_with_template);
        defer ctx.allocator.free(content_with_frontmatter);
    }
}

fn readMdFile(allocator: std.mem.Allocator, cwd: std.fs.Dir, md_file: MdFile) !RawMdFile {
    const curr = try cwd.openFile(md_file.absPath, .{});
    const end = try curr.getEndPos();
    const file_buf = try allocator.alloc(u8, end);
    _ = try curr.readAll(file_buf);
    if (!std.mem.startsWith(u8, file_buf, "---\n")) {
        return error.IncorrectFileStart;
    }
    const close_start = std.mem.indexOf(u8, file_buf, "\n---\n") orelse return error.MissingClosingMeta;
    const meta_buf = file_buf[4..close_start];
    const body_buf = file_buf[(close_start + 4)..];
    return RawMdFile{ .buffer = file_buf, .meta = meta_buf, .body = body_buf };
}

fn printStringMap(map: std.StringHashMap([]const u8)) void {
    var it = map.iterator();
    std.debug.print("{{\n", .{});
    while (it.next()) |e| {
        std.debug.print(
            "  \"{s}\" => \"{s}\"\n",
            .{ e.key_ptr.*, e.value_ptr.* },
        );
    }
    std.debug.print("}}\n", .{});
}

fn parseMdFile(allocator: std.mem.Allocator, raw_md_file: RawMdFile) !ParsedMdFile {
    var meta_map = std.StringHashMap([]const u8).init(allocator);
    var it = std.mem.splitScalar(u8, raw_md_file.meta, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " ");
        const i = std.mem.indexOfScalar(u8, trimmed, ':') orelse return error.ImproperMeta;
        const k = trimmed[0..i];
        const v = trimmed[i + 1 ..];
        const k_trimmed = std.mem.trim(u8, k, " ");
        const v_trimmed = std.mem.trim(u8, v, " ");
        try meta_map.put(k_trimmed, v_trimmed);
    }
    return ParsedMdFile{ .body = raw_md_file.body, .buffer = raw_md_file.buffer, .meta = meta_map };
}

fn setOutDir(ctx: *Ctx) !void {
    const o = try std.fs.path.join(ctx.allocator, &.{ ctx.project_root.?, "out" });
    try ctx.cwd.deleteTree(o);
    try ctx.cwd.makePath(o);
}

fn loadDefaultTemplate(ctx: *Ctx) ![]u8 {
    const defaultTemplate = try std.fs.path.join(ctx.allocator, &.{ ctx.project_root.?, "/templates/default.html" });
    const curr = try ctx.cwd.openFile(defaultTemplate, .{});
    const end = try curr.getEndPos();
    const file_buf = try ctx.allocator.alloc(u8, end);
    _ = try curr.readAll(file_buf);
    return file_buf;
}

const MdFile = struct {
    absPath: []const u8,
    relPath: []const u8,
};

const RawMdFile = struct {
    buffer: []u8,
    meta: []const u8,
    body: []const u8,
};

const ParsedMdFile = struct {
    buffer: []u8,
    meta: std.StringHashMap([]const u8),
    body: []const u8,

    fn deinit(self: *ParsedMdFile, allocator: std.mem.Allocator) void {
        allocator.free(self.buffer);
        self.meta.deinit();
    }
};

fn findMdFiles(
    allocator: std.mem.Allocator,
    project_root: []const u8,
) ![]MdFile {
    var out = std.ArrayList(MdFile).init(allocator);
    defer out.deinit();
    const rootAsDir = try std.fs.openDirAbsolute(project_root, .{ .iterate = true });
    var walker = try rootAsDir.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        const ext = std.fs.path.extension(entry.basename);
        const abs = try std.fs.path.join(allocator, &.{ project_root, entry.path });
        if (std.mem.eql(u8, ext, ".md")) {
            try out.append(MdFile{ .absPath = abs, .relPath = try allocator.dupe(u8, entry.path) });
        }
    }
    return out.toOwnedSlice();
}

fn mdToArr(ctx: *Ctx, md_file: ParsedMdFile) ![]u8 {
    var out_buf = std.ArrayList(u8).init(ctx.allocator);
    defer out_buf.deinit();
    _ = md.md_html(md_file.body.ptr, md_file.body.len, md.arr_callback, &out_buf, 0, 0);
    return out_buf.toOwnedSlice();
}

fn makeOutFile(ctx: *Ctx, md_file: MdFile) ![]const u8 {
    const content_root = try std.fs.path.join(ctx.allocator, &.{ ctx.project_root.?, "content" });
    const path_from_content_root = try std.fs.path.relative(ctx.allocator, content_root, md_file.relPath);
    const path_to_out_file = try std.fs.path.join(ctx.allocator, &.{ ctx.project_root.?, "out", path_from_content_root });
    const dir_of_out_file = std.fs.path.dirname(path_to_out_file).?;
    const out_file_name = std.fs.path.stem(path_to_out_file);
    const final_out_path = try std.fs.path.join(ctx.allocator, &.{ dir_of_out_file, out_file_name });
    const out_file = try std.fs.path.join(ctx.allocator, &.{ final_out_path, "index.html" });
    _ = try ctx.cwd.makePath(final_out_path);
    const f = try std.fs.cwd().createFile(out_file, .{ .truncate = true });
    log.debug("resolved output path: {s}", .{final_out_path});
    log.info("emitted page: {s}", .{out_file});
    f.close();
    ctx.allocator.free(content_root);
    ctx.allocator.free(path_from_content_root);
    ctx.allocator.free(path_to_out_file);
    ctx.allocator.free(dir_of_out_file);
    ctx.allocator.free(out_file_name);
    ctx.allocator.free(final_out_path);
    return out_file;
}

fn chdirScoped(a: std.mem.Allocator, into: []const u8) !void {
    const prev = try std.process.getCwdAlloc(a);
    defer a.free(prev);
    try std.posix.chdir(into);
    errdefer std.posix.chdir(prev);
}

fn copyAssets(ctx: *Ctx) !void {
    var src_assets_dir = ctx.cwd.openDir("assets", .{ .iterate = true }) catch return;
    const dest_assets_path = try std.fs.path.join(ctx.allocator, &.{ ctx.project_root.?, "out", "assets" });
    defer ctx.allocator.free(dest_assets_path);
    try ctx.cwd.makePath(dest_assets_path);
    var dest_assets_dir = ctx.cwd.openDir(dest_assets_path, .{ .iterate = true }) catch return;
    defer src_assets_dir.close();
    defer dest_assets_dir.close();
    try copyDir(src_assets_dir, dest_assets_dir);
}

fn copyDir(src: std.fs.Dir, dest: std.fs.Dir) !void {
    var it = src.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .file => {
                try src.copyFile(entry.name, dest, entry.name, .{});
                log.info("emitted asset: {s}", .{entry.name});
            },
            .directory => {
                log.debug("resolved output path: {s}", .{entry.name});
                try dest.makeDir(entry.name);
                var src_child = try src.openDir(entry.name, .{ .iterate = true });
                defer src_child.close();
                var dest_child = try dest.openDir(entry.name, .{ .iterate = true });
                defer dest_child.close();
                try copyDir(src_child, dest_child);
            },
            else => {},
        }
    }
}

fn insertBaseUrl(allocator: std.mem.Allocator, html: []u8) ![]u8 {
    var out_buf = std.ArrayList(u8).init(allocator);
    defer out_buf.deinit();
    var i: usize = 0;
    while (i < html.len) : (i += 1) {
        if (html[i] == 's' and html.len > (i + 12) and std.mem.eql(u8, html[i .. i + 12], "src=\"/assets")) {
            try out_buf.appendSlice("src=\"{{ base_url }}/assets");
            i += 11;
        } else if (html[i] == 'h' and html.len > (i + 13) and std.mem.eql(u8, html[i .. i + 13], "href=\"/assets")) {
            try out_buf.appendSlice("href=\"{{ base_url }}/assets");
            i += 12;
        } else {
            try out_buf.append(html[i]);
        }
    }
    return out_buf.toOwnedSlice();
}
