const std = @import("std");
const Ctx = @import("../core/ctx.zig").Ctx;

pub const DiscoverResult = struct {
    project_root: []const u8,
    config_path: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DiscoverResult) void {
        self.allocator.free(self.project_root);
        self.allocator.free(self.config_path);
    }
};

pub fn discoverProjectRoot(allocator: std.mem.Allocator, cwd: []const u8, project_arg: ?[]const u8) !DiscoverResult {
    if (project_arg) |p| if (try validateRoot(allocator, p)) |res| return res;
    if (try getEnvOwned(allocator, "HOLLOW_ROOT")) |env_root| {
        defer allocator.free(env_root);
        if (try validateRoot(allocator, env_root)) |res| return res;
    }
    return try upwardSearch(allocator, cwd);
}

fn validateRoot(allocator: std.mem.Allocator, path_in: []const u8) !?DiscoverResult {
    const abs = try toAbsoluteReal(allocator, path_in);
    defer allocator.free(abs);
    var d = std.fs.openDirAbsolute(abs, .{ .iterate = false }) catch return null;
    defer d.close();
    const cfg_path = try std.fs.path.join(allocator, &[_][]const u8{ abs, "hollow.toml" });
    const cfg_file = std.fs.openFileAbsolute(cfg_path, .{}) catch {
        allocator.free(cfg_path);
        return null;
    };
    cfg_file.close();
    return DiscoverResult{ .allocator = allocator, .project_root = try allocator.dupe(u8, abs), .config_path = cfg_path };
}

fn toAbsoluteReal(allocator: std.mem.Allocator, path_in: []const u8) ![]u8 {
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

fn upwardSearch(allocator: std.mem.Allocator, start_cwd: []const u8) !DiscoverResult {
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

pub fn run() !void {}

fn chdirScoped(a: std.mem.Allocator, into: []const u8) !void {
    const prev = try std.process.getCwdAlloc(a);
    defer a.free(prev);
    try std.posix.chdir(into);
    errdefer std.posix.chdir(prev);
}

test "Discover root in parent of parent" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("proj/sub/leaf");
    try tmp.dir.writeFile(.{ .sub_path = "proj/hollow.toml", .data = "" });
    const start = try tmp.dir.realpathAlloc(a, "proj/sub/leaf");
    defer a.free(start);
    try chdirScoped(a, start);
    var got = try discoverProjectRoot(a, start, null);
    const want = try tmp.dir.realpathAlloc(a, "proj");
    defer a.free(want);
    defer got.deinit();
    try std.testing.expectEqualStrings(want, got.project_root);
}

test "Discover root in CWD" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("proj");
    try tmp.dir.writeFile(.{ .sub_path = "proj/hollow.toml", .data = "" });
    const start = try tmp.dir.realpathAlloc(a, "proj");
    defer a.free(start);
    try chdirScoped(a, start);
    var got = try discoverProjectRoot(a, start, null);
    const want = try tmp.dir.realpathAlloc(a, "proj");
    defer a.free(want);
    defer got.deinit();
    try std.testing.expectEqualStrings(want, got.project_root);
}
