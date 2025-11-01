const std = @import("std");

pub const Ctx = struct {
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    env: std.process.EnvMap,
    log: std.fs.File,

    pub fn init(allocator: std.mem.Allocator) !Ctx {
        return .{ .allocator = allocator, .cwd = std.fs.cwd(), .env = try std.process.getEnvMap(allocator), .log = std.io.getStdErr() };
    }

    pub fn deinit(self: *Ctx) void {
        self.env.deinit();
    }

    pub fn getenv(self: *const Ctx, key: []const u8) ?[]const u8 {
        return self.env.get(key);
    }

    pub fn logf(self: *const Ctx, comptime fmt: []const u8, args: anytype) void {
        _ = self.log.writer().print(fmt, args) catch {};
    }
};
