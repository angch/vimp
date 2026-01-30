const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the main executable
    const exe = b.addExecutable(.{
        .name = "vimp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link against system libraries
    exe.linkLibC();
    exe.linkSystemLibrary("gtk4");
    exe.linkSystemLibrary("gegl-0.4");
    exe.linkSystemLibrary("babl-0.1");

    // Vendored paths from tools/build_gegl.sh (or libs cache)
    exe.addIncludePath(b.path("libs/usr/include/gegl-0.4"));
    exe.addIncludePath(b.path("libs/usr/include/babl-0.1"));
    exe.addLibraryPath(b.path("libs/usr/lib/x86_64-linux-gnu"));
    exe.addRPath(b.path("libs/usr/lib/x86_64-linux-gnu"));

    // Install the artifact
    b.installArtifact(exe);

    // Run support
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const gegl_path = b.pathFromRoot("libs/usr/lib/x86_64-linux-gnu/gegl-0.4");
    const babl_path = b.pathFromRoot("libs/usr/lib/x86_64-linux-gnu/babl-0.1");
    // Only set if not already set, but setEnvironmentVariable overrides.
    // Ideally we check if env var exists, but for now specific to vendoring request:
    run_cmd.setEnvironmentVariable("GEGL_PATH", gegl_path);
    run_cmd.setEnvironmentVariable("BABL_PATH", babl_path);

    // Plugins need to find libgegl-0.4.so.0 and libbabl-0.1.so.0
    const lib_path = b.pathFromRoot("libs/usr/lib/x86_64-linux-gnu");
    run_cmd.setEnvironmentVariable("LD_LIBRARY_PATH", lib_path);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Check step support
    const check_step = b.step("check", "Check if compilation works");
    check_step.dependOn(&exe.step);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_hierarchy.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit_tests.linkLibC();
    unit_tests.linkSystemLibrary("gtk4");
    unit_tests.linkSystemLibrary("gegl-0.4");
    unit_tests.linkSystemLibrary("babl-0.1");

    // GIMP source include paths
    unit_tests.addIncludePath(b.path("src"));
    unit_tests.addIncludePath(b.path("ref/gimp"));
    unit_tests.addIncludePath(b.path("ref/gimp/app"));

    // Libs
    unit_tests.addIncludePath(b.path("libs/usr/include/gegl-0.4"));
    unit_tests.addIncludePath(b.path("libs/usr/include/babl-0.1"));
    unit_tests.addLibraryPath(b.path("libs/usr/lib/x86_64-linux-gnu"));
    unit_tests.addRPath(b.path("libs/usr/lib/x86_64-linux-gnu"));

    const run_unit_tests = b.addRunArtifact(unit_tests);
    run_unit_tests.setEnvironmentVariable("GEGL_PATH", gegl_path);
    run_unit_tests.setEnvironmentVariable("BABL_PATH", babl_path);
    run_unit_tests.setEnvironmentVariable("LD_LIBRARY_PATH", lib_path);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const engine_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/engine.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    engine_tests.linkLibC();
    engine_tests.linkSystemLibrary("gtk4");
    engine_tests.linkSystemLibrary("gegl-0.4");
    engine_tests.linkSystemLibrary("babl-0.1");
    engine_tests.addIncludePath(b.path("libs/usr/include/gegl-0.4"));
    engine_tests.addIncludePath(b.path("libs/usr/include/babl-0.1"));
    engine_tests.addLibraryPath(b.path("libs/usr/lib/x86_64-linux-gnu")); // Ensure we find vendored libs
    engine_tests.addRPath(b.path("libs/usr/lib/x86_64-linux-gnu"));

    const run_engine_tests = b.addRunArtifact(engine_tests);
    run_engine_tests.setEnvironmentVariable("GEGL_PATH", gegl_path);
    run_engine_tests.setEnvironmentVariable("BABL_PATH", babl_path);
    run_engine_tests.setEnvironmentVariable("LD_LIBRARY_PATH", lib_path);
    // Pass DISPLAY and HOME for GEGL/GTK
    if (std.process.getEnvVarOwned(b.allocator, "DISPLAY")) |disp| {
        run_engine_tests.setEnvironmentVariable("DISPLAY", disp);
    } else |_| {}
    if (std.process.getEnvVarOwned(b.allocator, "HOME")) |home| {
        run_engine_tests.setEnvironmentVariable("HOME", home);
    } else |_| {}

    test_step.dependOn(&run_engine_tests.step);
}
