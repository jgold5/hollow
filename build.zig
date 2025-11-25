const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // EXE (module root = src/)
    const exe = b.addExecutable(.{
        .name = "hollow",
        .root_module = exe_mod,
    });

    // md4c
    const md4c = b.addStaticLibrary(.{
        .name = "md4c",
        .target = target,
        .optimize = optimize,
    });
    md4c.linkLibC();
    md4c.addIncludePath(b.path("thirdparty/md4c"));
    md4c.addCSourceFiles(.{
        .files = &.{
            "thirdparty/md4c/md4c.c",
            "thirdparty/md4c/md4c-html.c",
            "thirdparty/md4c/entity.c",
        },
        .flags = &.{},
    });
    exe.linkLibrary(md4c);
    b.installArtifact(exe);

    // TESTS (module root = src/)
    const tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.linkLibrary(md4c);

    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run tests").dependOn(&run_tests.step);
}
