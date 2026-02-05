const std = @import("std");
const Engine = @import("engine.zig").Engine;
const EngineIO = @import("engine.zig").io;
const c = @import("c.zig").c;

fn ensureDirs() !void {
    const cwd = std.fs.cwd();
    cwd.makePath("tests/baselines") catch |e| {
        if (e != error.PathAlreadyExists) return e;
    };
    cwd.makePath("tests/output") catch |e| {
        if (e != error.PathAlreadyExists) return e;
    };
    cwd.makePath("tests/failures") catch |e| {
        if (e != error.PathAlreadyExists) return e;
    };
}

fn loadImageToBuffer(path: []const u8) !*c.GeglBuffer {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const path_z = try std.heap.c_allocator.dupeZ(u8, path);
    defer std.heap.c_allocator.free(path_z);

    const load_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:load", "path", path_z.ptr, @as(?*anyopaque, null));
    if (load_node == null) return error.GeglLoadFailed;

    const bbox = c.gegl_node_get_bounding_box(load_node);
    if (bbox.width <= 0 or bbox.height <= 0) return error.InvalidImage;

    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(&bbox, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));
    if (write) |w| {
        _ = c.gegl_node_link(load_node, w);
        _ = c.gegl_node_process(w);
    } else {
        c.g_object_unref(new_buffer);
        return error.GeglGraphFailed;
    }

    return new_buffer.?;
}

fn compareImages(path_a: []const u8, path_b: []const u8) !bool {
    const buf_a = try loadImageToBuffer(path_a);
    defer c.g_object_unref(buf_a);

    const buf_b = try loadImageToBuffer(path_b);
    defer c.g_object_unref(buf_b);

    const ext_a = c.gegl_buffer_get_extent(buf_a);
    const ext_b = c.gegl_buffer_get_extent(buf_b);

    if (ext_a.*.width != ext_b.*.width or ext_a.*.height != ext_b.*.height) {
        std.debug.print("Dimension mismatch: {d}x{d} vs {d}x{d}\n", .{ext_a.*.width, ext_a.*.height, ext_b.*.width, ext_b.*.height});
        return false;
    }

    const w = ext_a.*.width;
    const h = ext_a.*.height;
    const size: usize = @intCast(w * h * 4);

    const allocator = std.heap.c_allocator;
    const data_a = try allocator.alloc(u8, size);
    defer allocator.free(data_a);
    const data_b = try allocator.alloc(u8, size);
    defer allocator.free(data_b);

    const format = c.babl_format("R'G'B'A u8");
    c.gegl_buffer_get(buf_a, ext_a, 1.0, format, data_a.ptr, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
    c.gegl_buffer_get(buf_b, ext_b, 1.0, format, data_b.ptr, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);

    // Pixel Compare
    var diff_count: usize = 0;
    const tolerance = 2; // Allow small difference for compression artifacts

    for (0..size) |i| {
        const diff = if (data_a[i] > data_b[i]) data_a[i] - data_b[i] else data_b[i] - data_a[i];
        if (diff > tolerance) {
            diff_count += 1;
        }
    }

    if (diff_count > 0) {
        std.debug.print("Image mismatch: {d} differing bytes\n", .{diff_count});
        return false;
    }

    return true;
}

fn checkBaseline(engine: *Engine, test_name: []const u8) !void {
    try ensureDirs();
    const allocator = std.heap.c_allocator;

    const baseline_path = try std.fmt.allocPrint(allocator, "tests/baselines/{s}.png", .{test_name});
    defer allocator.free(baseline_path);

    const output_path = try std.fmt.allocPrint(allocator, "tests/output/{s}.png", .{test_name});
    defer allocator.free(output_path);

    // Export current state to output
    try EngineIO.exportImage(engine, output_path);

    // Check if baseline exists
    const file = std.fs.cwd().openFile(baseline_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Baseline not found for {s}. Creating new baseline.\n", .{test_name});
            // Copy output to baseline
            try std.fs.cwd().copyFile(output_path, std.fs.cwd(), baseline_path, .{});
            return;
        }
        return err;
    };
    file.close();

    // Compare
    const match = try compareImages(baseline_path, output_path);
    if (!match) {
        const fail_path = try std.fmt.allocPrint(allocator, "tests/failures/{s}_diff.png", .{test_name});
        defer allocator.free(fail_path);
        try std.fs.cwd().copyFile(output_path, std.fs.cwd(), fail_path, .{});
        return error.VisualRegressionFailed;
    }
}

test "Visual: Basic Rect" {
    var engine = Engine{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    try engine.addLayer("Background");

    engine.setFgColor(255, 0, 0, 255);
    try engine.drawRectangle(50, 50, 100, 100, 0, true);

    try checkBaseline(&engine, "basic_rect");
}

test "Visual: Gradient and Blur" {
    var engine = Engine{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    try engine.addLayer("Background");

    engine.setFgColor(0, 0, 255, 255);
    engine.setBgColor(255, 255, 0, 255);
    try engine.drawGradient(0, 0, 200, 200);

    try engine.applyGaussianBlur(5.0);

    try checkBaseline(&engine, "gradient_blur");
}

test "Visual: Text" {
    var engine = Engine{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    try engine.addLayer("Background");

    engine.setFgColor(0, 0, 0, 255);
    try engine.drawText("Vimp", 50, 50, 48);

    try checkBaseline(&engine, "text_render");
}
