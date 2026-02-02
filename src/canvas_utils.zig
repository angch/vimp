const std = @import("std");
const c = @import("c.zig").c;

fn calculateGridRange(view_pos: f64, view_len: f64, scale: f64) struct { start: f64, end: f64 } {
    const start = @ceil(view_pos / scale);
    const end = @floor((view_pos + view_len) / scale);
    return .{ .start = start, .end = end };
}

pub fn drawPixelGrid(cr: *c.cairo_t, width: f64, height: f64, view_scale: f64, view_x: f64, view_y: f64) void {
    if (view_scale < 8.0) return;

    // Use a lighter gray
    c.cairo_set_source_rgba(cr, 0.5, 0.5, 0.5, 0.3);
    c.cairo_set_line_width(cr, 1.0);

    const x_range = calculateGridRange(view_x, width, view_scale);
    const y_range = calculateGridRange(view_y, height, view_scale);

    var i: f64 = x_range.start;
    while (i <= x_range.end) : (i += 1.0) {
        const x = i * view_scale - view_x;
        // Sharp lines usually benefit from 0.5 offset if stroke width is 1.0 (odd)
        const x_sharp = @floor(x) + 0.5;

        c.cairo_move_to(cr, x_sharp, 0);
        c.cairo_line_to(cr, x_sharp, height);
    }

    var j: f64 = y_range.start;
    while (j <= y_range.end) : (j += 1.0) {
        const y = j * view_scale - view_y;
        const y_sharp = @floor(y) + 0.5;

        c.cairo_move_to(cr, 0, y_sharp);
        c.cairo_line_to(cr, width, y_sharp);
    }

    c.cairo_stroke(cr);
}

pub fn snapAngle(start_x: f64, start_y: f64, end_x: f64, end_y: f64, step_degrees: f64) struct { x: f64, y: f64 } {
    const dx = end_x - start_x;
    const dy = end_y - start_y;
    const dist = @sqrt(dx * dx + dy * dy);

    if (dist == 0) return .{ .x = end_x, .y = end_y };

    const angle = std.math.atan2(dy, dx);
    const step_rad = step_degrees * (std.math.pi / 180.0);
    const snapped_angle = @round(angle / step_rad) * step_rad;

    const new_dx = dist * @cos(snapped_angle);
    const new_dy = dist * @sin(snapped_angle);

    return .{ .x = start_x + new_dx, .y = start_y + new_dy };
}

/// Calculates new view state for zooming around a focal point
pub fn calculateZoom(
    current_scale: f64,
    view_x: f64,
    view_y: f64,
    focal_x: f64,
    focal_y: f64,
    zoom_factor: f64,
) struct { scale: f64, view_x: f64, view_y: f64 } {
    const new_scale = current_scale * zoom_factor;
    // New View Pos = (Old View Pos + Focus) * Factor - Focus
    const new_view_x = (view_x + focal_x) * zoom_factor - focal_x;
    const new_view_y = (view_y + focal_y) * zoom_factor - focal_y;
    return .{ .scale = new_scale, .view_x = new_view_x, .view_y = new_view_y };
}

test "calculateGridRange" {
    const r1 = calculateGridRange(0.0, 100.0, 10.0);
    try std.testing.expectEqual(r1.start, 0.0);
    try std.testing.expectEqual(r1.end, 10.0);

    const r2 = calculateGridRange(5.0, 100.0, 10.0);
    try std.testing.expectEqual(r2.start, 1.0);
    try std.testing.expectEqual(r2.end, 10.0);

    const r3 = calculateGridRange(-5.0, 20.0, 10.0);
    try std.testing.expectEqual(r3.start, 0.0);
    try std.testing.expectEqual(r3.end, 1.0);
}

test "snapAngle" {
    // 0 degrees (Horizontal Right)
    const p1 = snapAngle(0, 0, 100, 10, 45.0);
    // Angle atan2(10, 100) ~ 5.7 deg -> snap to 0
    try std.testing.expectApproxEqAbs(p1.x, 100.498, 0.1); // Length is sqrt(100^2+10^2) ~ 100.5
    try std.testing.expectApproxEqAbs(p1.y, 0.0, 0.1);

    // 45 degrees
    const p2 = snapAngle(0, 0, 100, 90, 45.0);
    // Angle atan2(90, 100) ~ 42 deg -> snap to 45
    // Length ~ 134.5
    // x = 134.5 * cos(45) ~ 95
    // y = 134.5 * sin(45) ~ 95
    try std.testing.expectApproxEqAbs(p2.x, 95.1, 1.0);
    try std.testing.expectApproxEqAbs(p2.y, 95.1, 1.0);

    // 90 degrees (Vertical Down)
    const p3 = snapAngle(0, 0, 10, 100, 45.0);
    // Angle atan2(100, 10) ~ 84 deg -> snap to 90
    try std.testing.expectApproxEqAbs(p3.x, 0.0, 0.1);
    try std.testing.expectApproxEqAbs(p3.y, 100.5, 0.1);
}

test "calculateZoom" {
    // Initial: Scale 1.0, View 0,0.
    // Focus: 100, 100 (Screen coords)
    // Zoom Factor: 2.0 (Zoom In)
    const res = calculateZoom(1.0, 0.0, 0.0, 100.0, 100.0, 2.0);

    try std.testing.expectApproxEqAbs(res.scale, 2.0, 0.001);
    // new_view_x = (0 + 100) * 2 - 100 = 100
    try std.testing.expectApproxEqAbs(res.view_x, 100.0, 0.001);
    try std.testing.expectApproxEqAbs(res.view_y, 100.0, 0.001);

    // Case 2: Already panned and zoomed
    // Scale 2.0. View 100, 100.
    // Focus 50, 50.
    // Zoom Factor 0.5 (Zoom Out back to 1.0)
    const res2 = calculateZoom(2.0, 100.0, 100.0, 50.0, 50.0, 0.5);

    try std.testing.expectApproxEqAbs(res2.scale, 1.0, 0.001);
    // new_view_x = (100 + 50) * 0.5 - 50 = 150 * 0.5 - 50 = 75 - 50 = 25
    try std.testing.expectApproxEqAbs(res2.view_x, 25.0, 0.001);
}
