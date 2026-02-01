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
