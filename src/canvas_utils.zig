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
