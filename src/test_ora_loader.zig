const std = @import("std");
const c = @import("c.zig").c;
const Engine = @import("engine.zig").Engine;
const EngineIO = @import("engine.zig").io;

fn createDummyPng(allocator: std.mem.Allocator, path: []const u8) !void {
    // Create a 10x10 red PNG
    const s = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, 10, 10);
    defer c.cairo_surface_destroy(s);
    const cr = c.cairo_create(s);
    defer c.cairo_destroy(cr);
    c.cairo_set_source_rgb(cr, 1.0, 0.0, 0.0);
    c.cairo_paint(cr);

    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    _ = c.cairo_surface_write_to_png(s, path_z.ptr);
}

test "Engine load ORA" {
    var engine = Engine{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    const allocator = std.heap.c_allocator;
    const rnd = std.time.nanoTimestamp();
    const test_dir_name = try std.fmt.allocPrint(allocator, "test_ora_{d}", .{rnd});
    defer allocator.free(test_dir_name);

    try std.fs.cwd().makePath(test_dir_name);
    defer std.fs.cwd().deleteTree(test_dir_name) catch {};

    // 1. Create content
    const stack_xml =
        \\<image w="100" h="100">
        \\  <stack>
        \\    <layer name="Layer 1" src="data/layer1.png" x="10" y="20" visibility="visible" opacity="1.0" />
        \\  </stack>
        \\</image>
    ;
    const stack_path = try std.fs.path.join(allocator, &[_][]const u8{test_dir_name, "stack.xml"});
    defer allocator.free(stack_path);
    try std.fs.cwd().writeFile(.{ .sub_path = stack_path, .data = stack_xml });

    const data_dir = try std.fs.path.join(allocator, &[_][]const u8{test_dir_name, "data"});
    defer allocator.free(data_dir);
    try std.fs.cwd().makePath(data_dir);

    const img_path = try std.fs.path.join(allocator, &[_][]const u8{data_dir, "layer1.png"});
    defer allocator.free(img_path);
    try createDummyPng(allocator, img_path);

    const mimetype_path = try std.fs.path.join(allocator, &[_][]const u8{test_dir_name, "mimetype"});
    defer allocator.free(mimetype_path);
    try std.fs.cwd().writeFile(.{ .sub_path = mimetype_path, .data = "image/openraster" });

    // 2. Zip it
    const zip_path = try std.fmt.allocPrint(allocator, "{s}.ora", .{test_dir_name});
    defer allocator.free(zip_path);
    defer std.fs.cwd().deleteFile(zip_path) catch {};

    // run zip -r zip_path . inside test_dir
    {
        // We need zip_path to be absolute or relative to cwd?
        // zip command runs in cwd.
        // We want to run it inside test_dir.
        // std.process.Child has cwd.
        const abs_zip = try std.fs.cwd().realpathAlloc(allocator, ".");
        defer allocator.free(abs_zip);
        const full_zip = try std.fs.path.join(allocator, &[_][]const u8{abs_zip, zip_path});
        defer allocator.free(full_zip);

        var proc = std.process.Child.init(&[_][]const u8{"zip", "-r", "-q", full_zip, "."}, allocator);
        proc.cwd = test_dir_name;
        proc.stdin_behavior = .Ignore;
        proc.stdout_behavior = .Ignore;
        proc.stderr_behavior = .Ignore;
        _ = try proc.spawnAndWait();
    }

    // 3. Load ORA
    try EngineIO.loadOra(&engine, zip_path, true);

    // 4. Verify
    try std.testing.expectEqual(engine.canvas_width, 100);
    try std.testing.expectEqual(engine.canvas_height, 100);
    try std.testing.expectEqual(engine.layers.list.items.len, 1);

    const layer = &engine.layers.list.items[0];
    const name = std.mem.span(@as([*:0]const u8, @ptrCast(&layer.name)));
    try std.testing.expectEqualStrings("Layer 1", name);

    // Verify content position (x=10, y=20)
    // Check pixel at 10,20 (Should be Red)
    // Check pixel at 9,19 (Should be Transparent)

    const buf = layer.buffer;
    var pixel: [4]u8 = undefined;
    const format = c.babl_format("R'G'B'A u8");

    // 10, 20
    c.gegl_buffer_get(buf, &c.GeglRectangle{ .x = 10, .y = 20, .width = 1, .height = 1 }, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
    // Red?
    // Wait, createDummyPng creates red.
    try std.testing.expectEqual(pixel[0], 255);

    // 9, 19
    c.gegl_buffer_get(buf, &c.GeglRectangle{ .x = 9, .y = 19, .width = 1, .height = 1 }, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
    try std.testing.expectEqual(pixel[3], 0);
}

test "Engine save ORA" {
    const allocator = std.heap.c_allocator;
    const rnd = std.time.nanoTimestamp();
    const save_path = try std.fmt.allocPrint(allocator, "test_save_{d}.ora", .{rnd});
    defer allocator.free(save_path);
    defer std.fs.cwd().deleteFile(save_path) catch {};

    {
        var engine = Engine{};
        engine.init();
        defer engine.deinit();
        engine.setupGraph();

        // 1. Create content
        engine.setCanvasSize(200, 200);
        try engine.addLayer("Test Layer");
        engine.setFgColor(0, 0, 255, 255); // Blue
        engine.paintStroke(100, 100, 100, 100, 1.0); // Paint dot at 100,100

        // 2. Save ORA
        try EngineIO.saveOra(&engine, save_path);
    }

    // 3. Load ORA into new engine
    var engine2 = Engine{};
    engine2.init();
    defer engine2.deinit();

    try EngineIO.loadOra(&engine2, save_path, true);

    // 4. Verify
    try std.testing.expectEqual(engine2.canvas_width, 200);
    try std.testing.expectEqual(engine2.canvas_height, 200);
    try std.testing.expectEqual(engine2.layers.list.items.len, 1);

    const layer = &engine2.layers.list.items[0];
    const name = std.mem.span(@as([*:0]const u8, @ptrCast(&layer.name)));
    try std.testing.expectEqualStrings("Test Layer", name);

    // Check pixel at 100,100
    const buf = layer.buffer;
    var pixel: [4]u8 = undefined;
    const format = c.babl_format("R'G'B'A u8");
    c.gegl_buffer_get(buf, &c.GeglRectangle{ .x = 100, .y = 100, .width = 1, .height = 1 }, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);

    try std.testing.expectEqual(pixel[2], 255); // Blue
    try std.testing.expectEqual(pixel[0], 0);
}
