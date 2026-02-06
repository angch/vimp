const std = @import("std");
const engine_mod = @import("engine.zig");
const Engine = engine_mod.Engine;
const c = @import("c.zig").c;

test "Engine drawPolygon filled" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    try engine.addLayer("Background");

    engine.setFgColor(255, 0, 0, 255); // Red

    // Draw Triangle
    var points = std.ArrayList(Engine.Point){};
    defer points.deinit(std.heap.c_allocator);
    try points.append(std.heap.c_allocator, .{ .x = 10.0, .y = 10.0 });
    try points.append(std.heap.c_allocator, .{ .x = 30.0, .y = 10.0 });
    try points.append(std.heap.c_allocator, .{ .x = 20.0, .y = 30.0 });

    try engine.drawPolygon(points.items, 1, true);

    const buf = engine.layers.list.items[0].buffer;
    const format = c.babl_format("R'G'B'A u8");
    var pixel: [4]u8 = undefined;

    // Check Inside (20, 20)
    c.gegl_buffer_get(buf, &c.GeglRectangle{ .x = 20, .y = 20, .width = 1, .height = 1 }, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
    try std.testing.expectEqual(pixel[0], 255);

    // Check Outside (10, 30) - Left of bottom vertex
    c.gegl_buffer_get(buf, &c.GeglRectangle{ .x = 10, .y = 30, .width = 1, .height = 1 }, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
    try std.testing.expectEqual(pixel[0], 0);
}

test "Engine drawPolygon outline" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    try engine.addLayer("Background");

    engine.setFgColor(255, 0, 0, 255); // Red

    // Draw Box
    var points = std.ArrayList(Engine.Point){};
    defer points.deinit(std.heap.c_allocator);
    try points.append(std.heap.c_allocator, .{ .x = 10.0, .y = 10.0 });
    try points.append(std.heap.c_allocator, .{ .x = 30.0, .y = 10.0 });
    try points.append(std.heap.c_allocator, .{ .x = 30.0, .y = 30.0 });
    try points.append(std.heap.c_allocator, .{ .x = 10.0, .y = 30.0 });

    try engine.drawPolygon(points.items, 1, false);

    const buf = engine.layers.list.items[0].buffer;
    const format = c.babl_format("R'G'B'A u8");
    var pixel: [4]u8 = undefined;

    // Check Edge (20, 10)
    c.gegl_buffer_get(buf, &c.GeglRectangle{ .x = 20, .y = 10, .width = 1, .height = 1 }, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
    try std.testing.expectEqual(pixel[0], 255);

    // Check Center (20, 20) -> Should be Transparent
    c.gegl_buffer_get(buf, &c.GeglRectangle{ .x = 20, .y = 20, .width = 1, .height = 1 }, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
    try std.testing.expectEqual(pixel[0], 0);
}
