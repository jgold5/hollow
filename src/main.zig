//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

pub fn main() !u8 {
    var args = std.process.args();
    _ = args.next();
    const cmd = args.next().?;
    if (std.mem.eql(u8, cmd, "build")) {
        std.debug.print("Building now\n", .{});
        return 0;
    } else if (std.mem.eql(u8, cmd, "init")) {
        std.debug.print("Initing now\n", .{});
        return 0;
    } else if (std.mem.eql(u8, cmd, "serve")) {
        std.debug.print("Serving now\n", .{});
        return 0;
    } else if (std.mem.eql(u8, cmd, "--help")) {
        std.debug.print("{s}\n", .{help});
        return 0;
    } else if (std.mem.eql(u8, cmd, "--version")) {
        std.debug.print("Versioning now\n", .{});
        return 0;
    } else {
        std.debug.print("Invalid command '{s}'\n", .{cmd});
        return 64;
    }
}

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
