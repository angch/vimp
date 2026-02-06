const std = @import("std");
const c = @import("c.zig").c;
const Engine = @import("engine.zig").Engine;

test "Engine draw curve" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    try engine.addLayer("Background");

    engine.setFgColor(255, 0, 0, 255); // Red
    engine.setBrushSize(1);

    // Draw Curve from 0,0 to 100,0
    // Control Points pulling up to 0,50 and 100,50
    // x1=0, y1=0
    // x2=100, y2=0
    // cx1=0, cy1=50
    // cx2=100, cy2=50
    // Midpoint (t=0.5):
    // B(0.5) = 0.125*P1 + 0.375*CP1 + 0.375*CP2 + 0.125*P2
    // x = 0 + 0 + 37.5 + 12.5 = 50.
    // y = 0 + 18.75 + 18.75 + 0 = 37.5.
    // So pixel at 50, 37 should be hit.

    try engine.drawCurve(0, 0, 100, 0, 0, 50, 100, 50);

    const buf = engine.layers.list.items[0].buffer;
    const format = c.babl_format("R'G'B'A u8");
    var pixel: [4]u8 = undefined;

    // Check Midpoint Area (50, 37) -> Red
    c.gegl_buffer_get(buf, &c.GeglRectangle{ .x = 50, .y = 37, .width = 1, .height = 1 }, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
    // Allow some tolerance if antialiasing or interpolation, but with size 1 and paintStroke it should be solid enough.
    try std.testing.expectEqual(pixel[0], 255);

    // Check Baseline (50, 0) -> Transparent (Should arch over it)
    c.gegl_buffer_get(buf, &c.GeglRectangle{ .x = 50, .y = 0, .width = 1, .height = 1 }, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
    try std.testing.expectEqual(pixel[0], 0);
}
