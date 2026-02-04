const std = @import("std");
const c = @import("c.zig").c;
const Engine = @import("engine.zig").Engine;

test "Airbrush Density Metric" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    try engine.addLayer("Background");

    // Set Tool to Airbrush
    engine.setMode(.airbrush);
    engine.setBrushType(.circle);
    engine.setBrushSize(20); // Large brush to see scattering
    engine.setFgColor(0, 0, 0, 255); // Black

    // Draw a single spot (stationary "stroke") or short line
    // Center at 100, 100.
    // Radius 10. Area ~ 314 pixels.
    // Paint once.
    engine.paintStroke(100, 100, 100, 100, 1.0);

    const layer = &engine.layers.items[0];
    const buf = layer.buffer;

    // Check bounding box 80..120
    const x_start = 80;
    const x_end = 120;
    const y_start = 80;
    const y_end = 120;
    const w = x_end - x_start;
    const h = y_end - y_start;

    const format = c.babl_format("R'G'B'A u8");
    const stride = w * 4;
    const size: usize = @intCast(w * h * 4);

    const allocator = std.heap.c_allocator;
    const pixels = try allocator.alloc(u8, size);
    defer allocator.free(pixels);

    const rect = c.GeglRectangle{ .x = x_start, .y = y_start, .width = w, .height = h };
    c.gegl_buffer_get(buf, &rect, 1.0, format, pixels.ptr, stride, c.GEGL_ABYSS_NONE);

    var painted_pixels: usize = 0;
    var total_pixels_in_circle: usize = 0;

    var py: c_int = 0;
    while (py < h) : (py += 1) {
        var px: c_int = 0;
        while (px < w) : (px += 1) {
            const gx = x_start + px;
            const gy = y_start + py;

            // Check if inside ideal circle (Radius 10)
            // Note: brush_size is diameter usually? In engine:
            // const half = @divFloor(brush_size, 2);
            // const radius_sq = ... pow(brush_size/2, 2)
            // So brush_size 20 -> Radius 10.
            const dx = gx - 100;
            const dy = gy - 100;
            if (dx*dx + dy*dy <= 100) { // 10^2
                total_pixels_in_circle += 1;

                const idx = (@as(usize, @intCast(py)) * @as(usize, @intCast(w)) + @as(usize, @intCast(px))) * 4;
                const alpha = pixels[idx + 3];
                if (alpha > 0) {
                    painted_pixels += 1;
                }
            }
        }
    }

    const density = @as(f64, @floatFromInt(painted_pixels)) / @as(f64, @floatFromInt(total_pixels_in_circle));
    std.debug.print("\nAirbrush Density: {d:.4}\n", .{density});

    // Baseline Expectation: Current implementation paints SOLID circle.
    // So density should be 1.0 (or very close).
    // Future Expectation: Density < 0.8 (Scattered).

    // Assert it is scattered (low density but not empty)
    try std.testing.expect(density < 0.5);
    try std.testing.expect(density > 0.05);
}
