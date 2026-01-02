//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");
const init = @import("commands/init_cmd.zig");
const build = @import("commands/build_cmd.zig");
const Ctx = @import("core/ctx.zig").Ctx;
const BuildConfig = @import("core/ctx.zig").BuildConfig;

pub fn main() !u8 {
    const parent = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    var ctx = try Ctx.init(alloc);
    const build_cfg = try parseFlags(ctx.allocator, args);
    if (build_cfg) |cfg| {
        ctx.config = cfg;
    }
    const cmd = args[1];
    if (std.mem.startsWith(u8, cmd, "--")) {
        if (std.mem.eql(u8, cmd, "--help")) {
            std.debug.print("{s}\n", .{help});
            return 0;
        } else if (std.mem.eql(u8, cmd, "--version")) {
            std.debug.print("Versioning now\n", .{});
            return 0;
        } else {
            std.debug.print("Invalid command '{s}'\n", .{cmd});
            return 64;
        }
    } else {
        switch (parseSubcommand(cmd)) {
            Cmd.init => {
                const opts: init.InitOpts = .{ .project_root = "hollow" };
                _ = try init.run(&ctx, opts);
                return 0;
            },
            Cmd.build => {
                _ = try build.run(&ctx);
                return 0;
            },
            else => return 64,
        }
    }
}

fn parseSubcommand(cmd: [:0]const u8) Cmd {
    if (std.mem.eql(u8, cmd, "build")) {
        return Cmd.build;
    } else if (std.mem.eql(u8, cmd, "init")) {
        return Cmd.init;
    } else if (std.mem.eql(u8, cmd, "serve")) {
        return Cmd.serve;
    } else {
        return Cmd.invalid;
    }
}

fn parseFlags(allocator: std.mem.Allocator, args: [][:0]u8) !?BuildConfig {
    var expect: Flag = .none;
    var cfg = BuildConfig{ .base_url = "" };
    if (args.len < 3) return null;
    for (args[2..]) |arg| {
        if (expect != .none) {
            cfg.base_url = try normalizeBaseUrl(allocator, arg);
            expect = .none;
        } else if (std.mem.eql(u8, arg, "--base-url")) {
            expect = .base_url;
        }
    }
    if (expect != .none) return error.MissingValue;
    return cfg;
}

fn normalizeBaseUrl(allocator: std.mem.Allocator, arg: []const u8) ![]const u8 {
    if (std.mem.eql(u8, arg, "/")) {
        return allocator.dupe(u8, "");
    }
    var view: []const u8 = arg;
    if (std.mem.endsWith(u8, view, "/")) {
        view = std.mem.trimRight(u8, view, "/");
    }
    if (std.mem.startsWith(u8, view, "/")) {
        return allocator.dupe(u8, view);
    }
    var buf = try allocator.alloc(u8, view.len + 1);
    buf[0] = '/';
    std.mem.copyForwards(u8, buf[1..], view);
    return buf;
}

const Cmd = enum { init, build, serve, invalid };

const Flag = enum { base_url, none };

const help =
    \\hollow — static site tool
    \\USAGE: hollow <command> [options]
    \\COMMANDS: init, build, serve
    \\FLAGS: -h/--help, -V/--version, --verbose, --quiet
    \\EXAMPLES:
    \\hollow --help
    \\hollow init
    \\hollow build
    \\hollow serve
;
