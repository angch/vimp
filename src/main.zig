const std = @import("std");

const c = @import("c.zig").c;
const Engine = @import("engine.zig").Engine;

// Global state for simplicity in this phase
const Tool = enum {
    brush,
    eraser,
};

var engine: Engine = .{};
var surface: ?*c.cairo_surface_t = null;
var prev_x: f64 = 0;
var prev_y: f64 = 0;
var current_tool: Tool = .brush;

pub fn main() !void {
    engine.init();
    defer engine.deinit();

    // Construct the graph as per US-002
    engine.setupGraph();

    // Create the application
    // Use NON_UNIQUE to avoid dbus complications in dev
    const flags = c.G_APPLICATION_NON_UNIQUE;
    const app = c.gtk_application_new("org.vimp.app.dev", flags);
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

fn color_changed(
    button: *c.GtkColorButton,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    _ = user_data;
    var rgba: c.GdkRGBA = undefined;
    c.gtk_color_chooser_get_rgba(@ptrCast(button), &rgba);

    const r: u8 = @intFromFloat(rgba.red * 255.0);
    const g: u8 = @intFromFloat(rgba.green * 255.0);
    const b: u8 = @intFromFloat(rgba.blue * 255.0);
    const a: u8 = @intFromFloat(rgba.alpha * 255.0);

    engine.setFgColor(r, g, b, a);
}

fn brush_size_changed(
    range: *c.GtkRange,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    _ = user_data;
    const value = c.gtk_range_get_value(range);
    const size: c_int = @intFromFloat(value);
    engine.setBrushSize(size);
}

fn tool_toggled(
    button: *c.GtkToggleButton,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    if (c.gtk_toggle_button_get_active(button) == 1) {
        const tool_ptr = @as(*Tool, @ptrCast(@alignCast(user_data)));
        current_tool = tool_ptr.*;
        std.debug.print("Tool switched to: {}\n", .{current_tool});

        switch (current_tool) {
            .brush => engine.setMode(.paint),
            .eraser => engine.setMode(.erase),
        }
    }
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
    }

    // US-003: Render from GEGL
    if (surface) |s| {
        // We render regardless of whether it's new, because GEGL graph might have changed.
        // In a real app we'd optimize this (damage rects etc), but for now, full redraw.

        c.cairo_surface_flush(s);
        const data = c.cairo_image_surface_get_data(s);
        const stride = c.cairo_image_surface_get_stride(s);
        const s_width = c.cairo_image_surface_get_width(s);
        const s_height = c.cairo_image_surface_get_height(s);

        engine.blit(s_width, s_height, data, stride);

        c.cairo_surface_mark_dirty(s);
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

    // US-004: Paint on the GEGL buffer instead of Cairo surface directly
    engine.paintStroke(prev_x, prev_y, current_x, current_y);

    prev_x = current_x;
    prev_y = current_y;

    c.gtk_widget_queue_draw(widget);
}

// Keep these alive
var brush_tool = Tool.brush;
var eraser_tool = Tool.eraser;

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
    const sidebar = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_size_request(sidebar, 200, -1);
    c.gtk_widget_add_css_class(sidebar, "sidebar");
    c.gtk_box_append(@ptrCast(main_box), sidebar);

    // Tools Header
    const tools_label = c.gtk_label_new("Tools");
    c.gtk_box_append(@ptrCast(sidebar), tools_label);

    // Tools Container
    const tools_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 5);
    c.gtk_widget_set_halign(tools_box, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(sidebar), tools_box);

    const createToolButton = struct {
        fn func(tool_val: *Tool, icon_path: [:0]const u8, group: ?*c.GtkToggleButton) *c.GtkWidget {
            const btn = if (group) |_| c.gtk_toggle_button_new() else c.gtk_toggle_button_new();
            if (group) |g| c.gtk_toggle_button_set_group(@ptrCast(btn), g);

            const img = c.gtk_image_new_from_file(icon_path);
            c.gtk_widget_set_size_request(img, 24, 24);
            c.gtk_button_set_child(@ptrCast(btn), img);

            _ = c.g_signal_connect_data(btn, "toggled", @ptrCast(&tool_toggled), tool_val, null, 0);
            return btn;
        }
    }.func;

    // Brush
    const brush_btn = createToolButton(&brush_tool, "assets/brush.png", null);
    c.gtk_box_append(@ptrCast(tools_box), brush_btn);
    c.gtk_toggle_button_set_active(@ptrCast(brush_btn), 1);

    // Eraser
    const eraser_btn = createToolButton(&eraser_tool, "assets/eraser.png", @ptrCast(brush_btn));
    c.gtk_box_append(@ptrCast(tools_box), eraser_btn);

    // Separator
    c.gtk_box_append(@ptrCast(sidebar), c.gtk_separator_new(c.GTK_ORIENTATION_HORIZONTAL));

    // Color Selection
    const color_btn = c.gtk_color_button_new();
    c.gtk_widget_set_valign(color_btn, c.GTK_ALIGN_START);
    c.gtk_widget_set_halign(color_btn, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(sidebar), color_btn);
    _ = c.g_signal_connect_data(color_btn, "color-set", @ptrCast(&color_changed), null, null, 0);

    // Brush Size Slider
    const size_slider = c.gtk_scale_new_with_range(c.GTK_ORIENTATION_HORIZONTAL, 1.0, 50.0, 1.0);
    c.gtk_range_set_value(@ptrCast(size_slider), 3.0);
    c.gtk_widget_set_hexpand(size_slider, 0);
    c.gtk_box_append(@ptrCast(sidebar), size_slider);
    _ = c.g_signal_connect_data(size_slider, "value-changed", @ptrCast(&brush_size_changed), null, null, 0);

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
    _ = c.g_signal_connect_data(drag, "drag-update", @ptrCast(&drag_update), drawing_area, null, 0);

    // CSS Styling
    const css_provider = c.gtk_css_provider_new();
    const css =
        \\.sidebar { background-color: #e0e0e0; border-right: 1px solid #c0c0c0; padding: 10px; }
        \\.content { background-color: #ffffff; }
    ;
    c.gtk_css_provider_load_from_data(css_provider, css, -1);

    const display = c.gtk_widget_get_display(@ptrCast(window));
    c.gtk_style_context_add_provider_for_display(display, @ptrCast(css_provider), c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    c.g_object_unref(css_provider);

    c.gtk_window_present(@ptrCast(window));
}
