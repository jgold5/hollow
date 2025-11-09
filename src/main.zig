//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const init = @import("commands/init.zig");
const build = @import("commands/build.zig");
const Ctx = @import("core/ctx.zig").Ctx;

pub fn main() !u8 {
    var args = std.process.args();
    _ = args.next();
    const parent = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const alloc = arena.allocator();
    const ctx = try Ctx.init(alloc);
    const cmd = args.next().?;
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
                _ = try build.run();
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

const Cmd = enum { init, build, serve, invalid };

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

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "use other module" {
    try std.testing.expectEqual(@as(i32, 150), lib.add(100, 50));
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("hollow_lib");
