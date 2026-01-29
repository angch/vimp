const std = @import("std");

const c = @import("c.zig").c;
const Engine = @import("engine.zig").Engine;

// Global state for simplicity in this phase
var engine: Engine = .{};
var surface: ?*c.cairo_surface_t = null;
var prev_x: f64 = 0;
var prev_y: f64 = 0;

pub fn main() !void {
    engine.init();
    defer engine.deinit();

    // Construct the graph as per US-002
    engine.setupGraph();

    // Create the application
    const app = c.gtk_application_new("org.vimp.app", c.G_APPLICATION_DEFAULT_FLAGS);
    defer c.g_object_unref(app);

    // Connect the activate signal
    _ = c.g_signal_connect_data(
        app,
        "activate",
        @ptrCast(&activate),
        null,
        null,
        0,
    );

    // Run the application
    const status = c.g_application_run(@ptrCast(app), 0, null);
    _ = status;
}

fn draw_func(
    drawing_area: [*c]c.GtkDrawingArea,
    cr: ?*c.cairo_t,
    width: c_int,
    height: c_int,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    _ = user_data;
    _ = drawing_area;

    if (surface == null) {
        surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, width, height);
        // Clear to white
        const cr_surf = c.cairo_create(surface);
        c.cairo_set_source_rgb(cr_surf, 1, 1, 1);
        c.cairo_paint(cr_surf);
        c.cairo_destroy(cr_surf);
    }

    if (surface) |s| {
        if (cr) |cr_ctx| {
            c.cairo_set_source_surface(cr_ctx, s, 0, 0);
            c.cairo_paint(cr_ctx);
        }
    }
}

fn drag_begin(
    gesture: *c.GtkGestureDrag,
    x: f64,
    y: f64,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    _ = gesture;
    _ = user_data;
    prev_x = x;
    prev_y = y;
}

fn drag_update(
    gesture: *c.GtkGestureDrag,
    offset_x: f64,
    offset_y: f64,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {

    // We need original start coordinates.
    var start_sx: f64 = 0;
    var start_sy: f64 = 0;
    _ = c.gtk_gesture_drag_get_start_point(gesture, &start_sx, &start_sy);

    const current_x = start_sx + offset_x;
    const current_y = start_sy + offset_y;

    const widget: *c.GtkWidget = @ptrCast(@alignCast(user_data));

    if (surface) |s| {
        const cr = c.cairo_create(s);
        c.cairo_set_source_rgb(cr, 0, 0, 0);
        c.cairo_set_line_width(cr, 2);

        c.cairo_move_to(cr, prev_x, prev_y);
        c.cairo_line_to(cr, current_x, current_y);
        c.cairo_stroke(cr);
        c.cairo_destroy(cr);
    }

    prev_x = current_x;
    prev_y = current_y;

    c.gtk_widget_queue_draw(widget);
}

fn activate(app: *c.GtkApplication, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    _ = user_data;

    const window = c.gtk_application_window_new(app);
    c.gtk_window_set_title(@ptrCast(window), "Vimp");
    c.gtk_window_set_default_size(@ptrCast(window), 800, 600);

    const header_bar = c.gtk_header_bar_new();
    c.gtk_window_set_titlebar(@ptrCast(window), header_bar);

    // Main layout container (Horizontal Box)
    const main_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 0);
    c.gtk_window_set_child(@ptrCast(window), main_box);

    // Sidebar (Left)
    const sidebar = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    c.gtk_widget_set_size_request(sidebar, 200, -1);
    c.gtk_widget_add_css_class(sidebar, "sidebar");
    c.gtk_box_append(@ptrCast(main_box), sidebar);

    // Main Content (Right)
    const content = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    c.gtk_widget_set_hexpand(content, 1);
    c.gtk_widget_add_css_class(content, "content");
    c.gtk_box_append(@ptrCast(main_box), content);

    // Drawing Area
    const drawing_area = c.gtk_drawing_area_new();
    c.gtk_widget_set_hexpand(drawing_area, 1);
    c.gtk_widget_set_vexpand(drawing_area, 1);
    c.gtk_drawing_area_set_draw_func(@ptrCast(drawing_area), draw_func, null, null);
    c.gtk_box_append(@ptrCast(content), drawing_area);

    // Gestures
    const drag = c.gtk_gesture_drag_new();
    c.gtk_widget_add_controller(drawing_area, @ptrCast(drag));

    _ = c.g_signal_connect_data(drag, "drag-begin", @ptrCast(&drag_begin), null, null, 0);

    _ = c.g_signal_connect_data(drag, "drag-update", @ptrCast(&drag_update), drawing_area, // passed as user_data
        null, 0);

    // CSS Styling
    const css_provider = c.gtk_css_provider_new();
    const css =
        \\.sidebar { background-color: #e0e0e0; border-right: 1px solid #c0c0c0; }
        \\.content { background-color: #ffffff; }
    ;
    c.gtk_css_provider_load_from_data(css_provider, css, -1);

    const display = c.gtk_widget_get_display(@ptrCast(window));
    c.gtk_style_context_add_provider_for_display(display, @ptrCast(css_provider), c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    c.g_object_unref(css_provider);

    c.gtk_window_present(@ptrCast(window));
}
