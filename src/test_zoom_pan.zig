const std = @import("std");
const CanvasUtils = @import("canvas_utils.zig");

test "Zoom and Pan Logic" {
    // Initial State (Start of Gesture)
    const base_scale: f64 = 1.0;
    const base_view_x: f64 = 0.0;
    const base_view_y: f64 = 0.0;

    // Initial Center of Gesture (e.g. 2 fingers on screen center)
    const start_cx: f64 = 100.0;
    const start_cy: f64 = 100.0;

    // Case 1: Pure Pan (Right by 50px)
    // Fingers move to 150, 100. Scale remains 1.0.
    {
        const curr_cx: f64 = 150.0;
        const curr_cy: f64 = 100.0;
        const scale: f64 = 1.0;

        // Logic
        const res = CanvasUtils.calculateZoom(base_scale, base_view_x, base_view_y, start_cx, start_cy, scale);
        // view_x = calculated_x - (curr_cx - start_cx)
        const view_x = res.view_x - (curr_cx - start_cx);
        const view_y = res.view_y - (curr_cy - start_cy);

        // Expected:
        // calculateZoom(1.0, 0, 0, 100, 100, 1.0) -> view_x = 0
        // pan_delta = 150 - 100 = 50
        // view_x = 0 - 50 = -50
        // view_y = 0 - 0 = 0
        try std.testing.expectApproxEqAbs(view_x, -50.0, 0.001);
        try std.testing.expectApproxEqAbs(view_y, 0.0, 0.001);
        try std.testing.expectApproxEqAbs(res.scale, 1.0, 0.001);
    }

    // Case 2: Pure Zoom (2x around center)
    // Fingers stay at 100, 100. Scale becomes 2.0.
    {
        const curr_cx: f64 = 100.0;
        const curr_cy: f64 = 100.0;
        const scale: f64 = 2.0;

        const res = CanvasUtils.calculateZoom(base_scale, base_view_x, base_view_y, start_cx, start_cy, scale);
        const view_x = res.view_x - (curr_cx - start_cx);
        const view_y = res.view_y - (curr_cy - start_cy);

        // Expected:
        // calculateZoom(1.0, 0, 0, 100, 100, 2.0)
        // new_view_x = (0 + 100) * 2 - 100 = 100
        // pan_delta = 0
        // view_x = 100
        try std.testing.expectApproxEqAbs(view_x, 100.0, 0.001);
        try std.testing.expectApproxEqAbs(view_y, 100.0, 0.001);
        try std.testing.expectApproxEqAbs(res.scale, 2.0, 0.001);
    }

    // Case 3: Mixed (Zoom 2x AND Pan Right 50px)
    // Fingers spread and move right.
    // Scale 2.0. Center moves to 150, 100.
    {
        const curr_cx: f64 = 150.0;
        const curr_cy: f64 = 100.0;
        const scale: f64 = 2.0;

        const res = CanvasUtils.calculateZoom(base_scale, base_view_x, base_view_y, start_cx, start_cy, scale);
        const view_x = res.view_x - (curr_cx - start_cx);
        const view_y = res.view_y - (curr_cy - start_cy);

        // Expected:
        // calculateZoom logic gives "Zoom around START center" result = 100 (as above)
        // pan_delta = 50
        // view_x = 100 - 50 = 50
        try std.testing.expectApproxEqAbs(view_x, 50.0, 0.001);
        try std.testing.expectApproxEqAbs(view_y, 100.0, 0.001);
        try std.testing.expectApproxEqAbs(res.scale, 2.0, 0.001);
    }
}
