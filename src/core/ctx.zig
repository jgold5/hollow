const std = @import("std");

pub const Ctx = struct {
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    env: std.process.EnvMap,
    log: std.fs.File,
    project_root: ?[]const u8,
    out_dir: ?[]const u8,
    config: BuildConfig,

    pub fn init(allocator: std.mem.Allocator) !Ctx {
        return .{ .allocator = allocator, .cwd = std.fs.cwd(), .env = try std.process.getEnvMap(allocator), .log = std.io.getStdErr(), .project_root = null, .out_dir = null, .config = BuildConfig{ .base_url = "" } };
    }

    pub fn deinit(self: *Ctx) void {
        self.env.deinit();
        if (self.project_root) |p| self.allocator.free(p);
        if (self.out_dir) |o| self.allocator.free(o);
        if (self.config.base_url) |b| self.allocator.free(b);
    }

    pub fn getenv(self: *const Ctx, key: []const u8) ?[]const u8 {
        return self.env.get(key);
    }

    pub fn logf(self: *const Ctx, comptime fmt: []const u8, args: anytype) void {
        _ = self.log.writer().print(fmt, args) catch {};
    }
};

pub const BuildConfig = struct {
    base_url: []const u8,
};
