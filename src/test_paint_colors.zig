const std = @import("std");
const c = @import("c.zig").c;
const Engine = @import("engine.zig").Engine;

test "Engine paint stroke primary color" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    try engine.addLayer("Background");

    // Set FG Red, BG Blue
    engine.setFgColor(255, 0, 0, 255);
    engine.setBgColor(0, 0, 255, 255);

    // Paint at 100,100 with default (Primary/FG)
    engine.paintStroke(100, 100, 100, 100, 1.0);

    const buf = engine.layers.list.items[0].buffer;
    var pixel: [4]u8 = undefined;
    const rect = c.GeglRectangle{ .x = 100, .y = 100, .width = 1, .height = 1 };
    const format = c.babl_format("R'G'B'A u8");
    c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);

    // Expect Red
    try std.testing.expectEqual(pixel[0], 255);
    try std.testing.expectEqual(pixel[2], 0);
}

test "Engine paint stroke secondary color" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    try engine.addLayer("Background");

    // Set FG Red, BG Blue
    engine.setFgColor(255, 0, 0, 255);
    engine.setBgColor(0, 0, 255, 255);

    // Paint at 100,100 with Secondary (BG)
    engine.paintStrokeWithColor(100, 100, 100, 100, 1.0, engine.bg_color);

    const buf = engine.layers.list.items[0].buffer;
    var pixel: [4]u8 = undefined;
    const rect = c.GeglRectangle{ .x = 100, .y = 100, .width = 1, .height = 1 };
    const format = c.babl_format("R'G'B'A u8");
    c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);

    // Expect Blue (R=0, B=255)
    try std.testing.expectEqual(pixel[0], 0);
    try std.testing.expectEqual(pixel[2], 255);
}
