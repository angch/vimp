const std = @import("std");
const Engine = @import("engine.zig").Engine;
const c = @import("c.zig").c;

test "Engine draw rounded rectangle" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    try engine.addLayer("Background");

    engine.setFgColor(255, 0, 0, 255); // Red

    // Draw Filled Rounded Rect at 10,10 size 40x40, radius 10
    // Rect range: x=[10, 50), y=[10, 50)
    try engine.drawRoundedRectangle(10, 10, 40, 40, 10, 1, true);

    if (engine.layers.items.len > 0) {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = undefined;
        const format = c.babl_format("R'G'B'A u8");

        // 1. Center (30, 30) -> Red
        c.gegl_buffer_get(buf, &c.GeglRectangle{ .x = 30, .y = 30, .width = 1, .height = 1 }, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 255);
        try std.testing.expectEqual(pixel[3], 255);

        // 2. Corner Top-Left (10, 10) -> Transparent (Outside radius)
        // Radius center is at (10+10, 10+10) = (20, 20).
        // (10,10) is dist sqrt(100+100) ~ 14.1 from (20,20). > 10.
        // Actually, coordinate 10 is the pixel index. Pixel center is 10.5.
        // Radius center 20.0?
        // drawRoundedRectangle uses:
        // cx = 20.0 (half_w)
        // cy = 20.0 (half_h)
        // r_val = 10.0
        // px=0 (relative local x for 10).
        // dx = abs(0 + 0.5 - 20.0) = 19.5
        // qx = 19.5 - (20.0 - 10.0) = 9.5
        // qy = 9.5
        // dist = sqrt(9.5^2 + 9.5^2) + ... - 10.0
        // dist = 13.43 - 10.0 = 3.43 > 0. OUTSIDE.

        c.gegl_buffer_get(buf, &c.GeglRectangle{ .x = 10, .y = 10, .width = 1, .height = 1 }, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 0);
        try std.testing.expectEqual(pixel[3], 0);

        // 3. Inside Corner (15, 15) -> Red
        // px=5 (relative).
        // dx = abs(5.5 - 20) = 14.5
        // qx = 14.5 - 10 = 4.5
        // dist = sqrt(4.5^2 + 4.5^2) - 10 = 6.36 - 10 = -3.64 < 0. INSIDE.
        c.gegl_buffer_get(buf, &c.GeglRectangle{ .x = 15, .y = 15, .width = 1, .height = 1 }, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 255);
    }
}
