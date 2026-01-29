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

    // Vendored paths from tools/setup_libs.sh (User Request: Download libs)
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
    run_cmd.setEnvironmentVariable("GEGL_PATH", gegl_path);
    run_cmd.setEnvironmentVariable("BABL_PATH", babl_path);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Check step support
    const check_step = b.step("check", "Check if compilation works");
    check_step.dependOn(&exe.step);
}
