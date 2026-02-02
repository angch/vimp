const std = @import("std");
const c = @import("../c.zig").c;
const Engine = @import("../engine.zig").Engine;

pub const ThumbnailContext = struct {
    engine: *Engine,
    view_x: *f64,
    view_y: *f64,
    view_scale: *f64,
    main_drawing_area: *c.GtkWidget,
    queue_draw_main: *const fn () void,
};

var active_window: ?*c.GtkWindow = null;
var active_area: ?*c.GtkWidget = null;
var active_context: ?*ThumbnailContext = null;

fn draw_func(
    _: [*c]c.GtkDrawingArea,
    cr: ?*c.cairo_t,
    width: c_int,
    height: c_int,
    _: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    if (active_context == null) return;
    const ctx = active_context.?;
    const engine = ctx.engine;

    if (engine.output_node == null) {
        c.cairo_set_source_rgb(cr, 0.2, 0.2, 0.2);
        c.cairo_paint(cr);
        return;
    }

    const bbox = c.gegl_node_get_bounding_box(engine.output_node);
    if (bbox.width <= 0 or bbox.height <= 0) return;

    const w_img: f64 = @floatFromInt(bbox.width);
    const h_img: f64 = @floatFromInt(bbox.height);
    const w_win: f64 = @floatFromInt(width);
    const h_win: f64 = @floatFromInt(height);

    const scale_x = w_win / w_img;
    const scale_y = h_win / h_img;
    const scale = @min(scale_x, scale_y);

    const draw_w = w_img * scale;
    const draw_h = h_img * scale;
    const off_x = (w_win - draw_w) / 2.0;
    const off_y = (h_win - draw_h) / 2.0;

    const i_draw_w: c_int = @intFromFloat(draw_w);
    const i_draw_h: c_int = @intFromFloat(draw_h);

    if (i_draw_w > 0 and i_draw_h > 0) {
        // Use heap allocator for temporary buffer
        const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, i_draw_w);
        const size: usize = @intCast(stride * i_draw_h);

        const buf = std.heap.c_allocator.alloc(u8, size) catch return;
        defer std.heap.c_allocator.free(buf);

        const rect = c.GeglRectangle{ .x = 0, .y = 0, .width = i_draw_w, .height = i_draw_h };
        const format = c.babl_format("cairo-ARGB32");

        c.gegl_node_blit(engine.output_node, scale, &rect, format, buf.ptr, stride, c.GEGL_BLIT_DEFAULT);

        const surf = c.cairo_image_surface_create_for_data(buf.ptr, c.CAIRO_FORMAT_ARGB32, i_draw_w, i_draw_h, stride);
        c.cairo_set_source_surface(cr, surf, off_x, off_y);
        c.cairo_paint(cr);
        c.cairo_surface_finish(surf);
        c.cairo_surface_destroy(surf);
    }

    // Viewport Rect
    const vx = ctx.view_x.*;
    const vy = ctx.view_y.*;
    const vs = ctx.view_scale.*;

    const main_w = c.gtk_widget_get_width(ctx.main_drawing_area);
    const main_h = c.gtk_widget_get_height(ctx.main_drawing_area);

    const cx = vx / vs;
    const cy = vy / vs;
    const cw = @as(f64, @floatFromInt(main_w)) / vs;
    const ch = @as(f64, @floatFromInt(main_h)) / vs;

    const tv_x = cx * scale + off_x;
    const tv_y = cy * scale + off_y;
    const tv_w = cw * scale;
    const tv_h = ch * scale;

    c.cairo_set_source_rgb(cr, 1.0, 0.0, 0.0);
    c.cairo_set_line_width(cr, 2.0);
    c.cairo_rectangle(cr, tv_x, tv_y, tv_w, tv_h);
    c.cairo_stroke(cr);
}

fn update_position(x: f64, y: f64) void {
    if (active_context == null) return;
    const ctx = active_context.?;
    const engine = ctx.engine;

    if (engine.output_node == null) return;
    const bbox = c.gegl_node_get_bounding_box(engine.output_node);

    const w_win = @as(f64, @floatFromInt(c.gtk_widget_get_width(active_area.?)));
    const h_win = @as(f64, @floatFromInt(c.gtk_widget_get_height(active_area.?)));

    const w_img: f64 = @floatFromInt(bbox.width);
    const h_img: f64 = @floatFromInt(bbox.height);

    const scale = @min(w_win / w_img, h_win / h_img);
    const off_x = (w_win - w_img * scale) / 2.0;
    const off_y = (h_win - h_img * scale) / 2.0;

    const cx = (x - off_x) / scale;
    const cy = (y - off_y) / scale;

    const main_w = c.gtk_widget_get_width(ctx.main_drawing_area);
    const main_h = c.gtk_widget_get_height(ctx.main_drawing_area);
    const vs = ctx.view_scale.*;

    const cw = @as(f64, @floatFromInt(main_w)) / vs;
    const ch = @as(f64, @floatFromInt(main_h)) / vs;

    const new_cx_tl = cx - cw / 2.0;
    const new_cy_tl = cy - ch / 2.0;

    ctx.view_x.* = new_cx_tl * vs;
    ctx.view_y.* = new_cy_tl * vs;

    ctx.queue_draw_main();
    refresh();
}

fn on_click(
    gesture: *c.GtkGestureClick,
    _: c_int,
    x: f64,
    y: f64,
    _: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    const button = c.gtk_gesture_single_get_current_button(@ptrCast(gesture));
    if (button == 1) {
        update_position(x, y);
    }
}

var start_x: f64 = 0;
var start_y: f64 = 0;

fn drag_begin(
    _: *c.GtkGestureDrag,
    x: f64,
    y: f64,
    _: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    start_x = x;
    start_y = y;
    update_position(x, y);
}

fn drag_update(
    _: *c.GtkGestureDrag,
    offset_x: f64,
    offset_y: f64,
    _: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    update_position(start_x + offset_x, start_y + offset_y);
}

fn on_close(_: *c.GtkWindow, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) c.gboolean {
    c.gtk_widget_set_visible(@ptrCast(active_window.?), 0);
    return 1;
}

pub fn show(parent: *c.GtkWindow, ctx: *ThumbnailContext) void {
    active_context = ctx;

    if (active_window) |w| {
        c.gtk_window_present(w);
        return;
    }

    const window = c.gtk_window_new();
    c.gtk_window_set_transient_for(@ptrCast(window), parent);
    c.gtk_window_set_title(@ptrCast(window), "Overview");
    c.gtk_window_set_default_size(@ptrCast(window), 200, 200);
    c.gtk_window_set_destroy_with_parent(@ptrCast(window), 1);

    _ = c.g_signal_connect_data(window, "close-request", @ptrCast(&on_close), null, null, 0);

    const area = c.gtk_drawing_area_new();
    c.gtk_drawing_area_set_draw_func(@ptrCast(area), draw_func, null, null);
    c.gtk_window_set_child(@ptrCast(window), area);

    const drag = c.gtk_gesture_drag_new();
    c.gtk_widget_add_controller(area, @ptrCast(drag));
    _ = c.g_signal_connect_data(drag, "drag-begin", @ptrCast(&drag_begin), null, null, 0);
    _ = c.g_signal_connect_data(drag, "drag-update", @ptrCast(&drag_update), null, null, 0);

    const click = c.gtk_gesture_click_new();
    c.gtk_widget_add_controller(area, @ptrCast(click));
    _ = c.g_signal_connect_data(click, "pressed", @ptrCast(&on_click), null, null, 0);

    active_window = @ptrCast(window);
    active_area = area;

    c.gtk_window_present(@ptrCast(window));
}

pub fn refresh() void {
    if (active_area) |area| {
        c.gtk_widget_queue_draw(area);
    }
}
