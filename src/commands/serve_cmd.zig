const std = @import("std");
const Ctx = @import("../core/ctx.zig").Ctx;
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

fn setOutDir(ctx: *Ctx) !void {
    const o = try std.fs.path.join(ctx.allocator, &.{ ctx.project_root.?, "out" });
    var d = std.fs.cwd().openDir(o, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.err("output dir missing", .{});
            return err;
        },
        else => return err,
    };
    d.close();
    ctx.out_dir = o;
}

pub fn run(ctx: *Ctx) !void {
    const proc_cwd_buf = try ctx.cwd.realpathAlloc(ctx.allocator, ".");
    defer ctx.allocator.free(proc_cwd_buf);
    const root = try discoverProjectRoot(ctx.allocator, proc_cwd_buf, null);
    ctx.project_root = root;
    try setOutDir(ctx);
    const addr = try std.net.Address.parseIp4("127.0.0.1", ctx.port);
    var server = try std.net.Address.listen(addr, .{});
    while (true) {
        try handleConection(ctx, &server);
    }
    server.deinit();
}

fn handleConection(ctx: *Ctx, server: *std.net.Server) !void {
    var conn = try server.accept();
    var req = std.ArrayList(u8).init(ctx.allocator);
    defer req.deinit();
    var buf: [1024]u8 = undefined;
    var n: usize = 0;
    while (true) {
        n = try conn.stream.read(buf[0..]);
        if (std.mem.containsAtLeast(u8, buf[0..n], 1, "\r\n\r\n")) {
            try req.appendSlice(buf[0..n]);
            break;
        }
        try req.appendSlice(buf[0..n]);
    }
    const full_req = try req.toOwnedSlice();
    const end_of_header = std.mem.indexOf(u8, full_req, "\r\n").?;
    const header = full_req[0..end_of_header];
    var it = std.mem.splitScalar(u8, header, ' ');
    const req_type: []const u8 = it.next() orelse return error.MissingRequestType;
    const path: []const u8 = it.next() orelse return error.MissingRequestPath;
    const version: []const u8 = it.next() orelse return error.MissingVersion;
    _ = version;
    const normalized_path = try normalizePath(ctx.allocator, path);
    log.info("{s} request for {s}", .{ req_type, normalized_path });
    defer ctx.allocator.free(normalized_path);
    const joined_path = try joinWithFS(ctx.allocator, ctx.out_dir.?, normalized_path);
    const writer = conn.stream.writer();
    const file = std.fs.openFileAbsolute(joined_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            try writer.writeAll("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n");
            return;
        },
        else => return err,
    };
    const stat = try file.stat();
    const file_size = stat.size;
    const status_header = "HTTP/1.1 200 OK\r\n";
    const content_type_header = "Content-Type: text/html\r\n";
    try writer.writeAll(status_header);
    try writer.writeAll(content_type_header);
    try writer.print("Content-Length: {}\r\n", .{file_size});
    try writer.writeAll("\r\n");
    var file_buf: [1024]u8 = undefined;
    var file_n: usize = 0;
    while (true) {
        file_n = try file.read(file_buf[0..]);
        if (file_n == 0) {
            break;
        }
        try writer.writeAll(file_buf[0..file_n]);
    }
    defer ctx.allocator.free(joined_path);
    ctx.allocator.free(full_req);
    conn.stream.close();
}

fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (std.mem.containsAtLeast(u8, path, 1, "..")) return error.PathTraversal;
    if (std.mem.eql(u8, path, "/")) {
        return allocator.dupe(u8, "/index.html");
    }
    return allocator.dupe(u8, path);
}

fn joinWithFS(allocator: std.mem.Allocator, out_dir: []const u8, path: []const u8) ![]const u8 {
    return std.fs.path.join(allocator, &.{ out_dir, path });
}
