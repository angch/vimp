const std = @import("std");
const c = @import("c.zig").c;
const Engine = @import("engine.zig").Engine;
const Salvage = @import("salvage.zig").Salvage;

test "Salvage recoverFile" {
    // Note: This test requires a display for GDK to work fully if texture download relies on GL context,
    // but gdk_texture_new_from_file usually works with software fallback.
    // However, CI environments might fail if GTK init is not done or no display.
    // Engine.init() calls gegl_init().

    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // Create a temp PNG file
    const filename = "test_salvage.png";
    const s = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, 64, 64);
    defer c.cairo_surface_destroy(s);

    // Fill Red
    const cr = c.cairo_create(s);
    c.cairo_set_source_rgb(cr, 1.0, 0.0, 0.0);
    c.cairo_paint(cr);
    c.cairo_destroy(cr);

    const status = c.cairo_surface_write_to_png(s, filename);
    try std.testing.expectEqual(status, c.CAIRO_STATUS_SUCCESS);
    defer std.fs.cwd().deleteFile(filename) catch {};

    // Attempt Recovery
    try Salvage.recoverFile(&engine, filename);

    // Verify Layer Added
    try std.testing.expectEqual(engine.layers.items.len, 1);

    const layer = &engine.layers.items[0];
    const extent = c.gegl_buffer_get_extent(layer.buffer);
    try std.testing.expectEqual(extent.*.width, 64);
    try std.testing.expectEqual(extent.*.height, 64);

    // Verify Pixel Color (Red)
    var pixel: [4]u8 = undefined;
    const rect = c.GeglRectangle{ .x = 32, .y = 32, .width = 1, .height = 1 };
    const format = c.babl_format("R'G'B'A u8");
    c.gegl_buffer_get(layer.buffer, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);

    // GDK texture download provides RGBA.
    // gegl_buffer_set with "R'G'B'A u8" should match.
    // Red: 255, 0, 0, 255
    try std.testing.expectEqual(pixel[0], 255); // Red
    try std.testing.expectEqual(pixel[1], 0);
    try std.testing.expectEqual(pixel[2], 0);
    try std.testing.expectEqual(pixel[3], 255);
}
