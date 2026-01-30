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
var mouse_x: f64 = 0;
var mouse_y: f64 = 0;
var current_tool: Tool = .brush;

pub fn main() !void {
    engine.init();
    defer engine.deinit();

    // Construct the graph as per US-002
    engine.setupGraph();

    // Create the application
    // Use NON_UNIQUE to avoid dbus complications in dev
    const flags = c.G_APPLICATION_NON_UNIQUE;
    // Migrate to AdwApplication
    const app = c.adw_application_new("org.vimp.app.dev", flags);
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

// Keep these alive
var brush_tool = Tool.brush;
var eraser_tool = Tool.eraser;

// View State
var view_scale: f64 = 1.0;
var view_x: f64 = 0.0;
var view_y: f64 = 0.0;

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
        c.cairo_surface_flush(s);
        const data = c.cairo_image_surface_get_data(s);
        const stride = c.cairo_image_surface_get_stride(s);
        const s_width = c.cairo_image_surface_get_width(s);
        const s_height = c.cairo_image_surface_get_height(s);

        engine.blitView(s_width, s_height, data, stride, view_scale, view_x, view_y);

        c.cairo_surface_mark_dirty(s);
    }

    if (surface) |s| {
        if (cr) |cr_ctx| {
            c.cairo_set_source_surface(cr_ctx, s, 0, 0);
            c.cairo_paint(cr_ctx);
        }
    }
}

fn motion_func(
    controller: *c.GtkEventControllerMotion,
    x: f64,
    y: f64,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    _ = controller;
    _ = user_data;
    mouse_x = x;
    mouse_y = y;
}

fn scroll_func(
    controller: *c.GtkEventControllerScroll,
    dx: f64,
    dy: f64,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) c.gboolean {
    const widget: *c.GtkWidget = @ptrCast(@alignCast(user_data));

    // Check modifiers (Ctrl for Zoom)
    const state = c.gtk_event_controller_get_current_event_state(@ptrCast(controller));
    const is_ctrl = (state & c.GDK_CONTROL_MASK) != 0;

    if (is_ctrl) {
        // Zoom at mouse cursor
        // Zoom factor
        const zoom_factor: f64 = if (dy > 0) 0.9 else 1.1; // Scroll down = Zoom out

        const new_scale = view_scale * zoom_factor;
        // Limit scale
        if (new_scale < 0.1 or new_scale > 20.0) return 0;

        // ViewX_new = (ViewX_old + MouseX) * Factor - MouseX
        view_x = (view_x + mouse_x) * zoom_factor - mouse_x;
        view_y = (view_y + mouse_y) * zoom_factor - mouse_y;
        view_scale = new_scale;
    } else {
        // Pan
        // Scroll down (positive dy) -> Move View Down (increase ViewY) -> Content moves Up?
        // Standard Web/Doc: Scroll Down -> Content moves Up.
        // ViewY increases.
        // Speed factor
        const speed = 20.0;
        view_x += dx * speed;
        view_y += dy * speed;
    }

    c.gtk_widget_queue_draw(widget);

    return 1; // Handled
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
    const widget: *c.GtkWidget = @ptrCast(@alignCast(user_data));

    // Check which button is pressed
    // gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(gesture))
    const button = c.gtk_gesture_single_get_current_button(@ptrCast(gesture));

    // Get start point
    var start_sx: f64 = 0;
    var start_sy: f64 = 0;
    _ = c.gtk_gesture_drag_get_start_point(gesture, &start_sx, &start_sy);

    const current_x = start_sx + offset_x;
    const current_y = start_sy + offset_y;

    if (button == 2) {
        // Pan (Middle Mouse)
        const dx = current_x - prev_x;
        const dy = current_y - prev_y;

        view_x -= dx;
        view_y -= dy;

        c.gtk_widget_queue_draw(widget);
    } else if (button == 1) {
        // Paint (Left Mouse)
        const c_prev_x = (view_x + prev_x) / view_scale;
        const c_prev_y = (view_y + prev_y) / view_scale;
        const c_curr_x = (view_x + current_x) / view_scale;
        const c_curr_y = (view_y + current_y) / view_scale;

        engine.paintStroke(c_prev_x, c_prev_y, c_curr_x, c_curr_y);
        c.gtk_widget_queue_draw(widget);
    }

    prev_x = current_x;
    prev_y = current_y;
}

fn new_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    std.debug.print("New activated\n", .{});
}

fn open_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    std.debug.print("Open activated\n", .{});
}

fn save_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    std.debug.print("Save activated\n", .{});
}

fn about_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    std.debug.print("Vimp Application\nVersion 0.1\n", .{});
}

fn quit_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const app: *c.GtkApplication = @ptrCast(@alignCast(user_data));
    const windows = c.gtk_application_get_windows(app);
    if (windows) |list| {
        const window = list.*.data;
        c.gtk_window_close(@ptrCast(@alignCast(window)));
    }
    // Alternatively: c.g_application_quit(@ptrCast(app));
    // But closing the window is more "Adwaita" friendly if it manages the lifecycle.
    c.g_application_quit(@ptrCast(app));
}

fn sidebar_toggled(
    _: *c.GtkButton,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    const split_view: *c.AdwOverlaySplitView = @ptrCast(@alignCast(user_data));
    const is_shown = c.adw_overlay_split_view_get_show_sidebar(split_view);
    c.adw_overlay_split_view_set_show_sidebar(split_view, if (is_shown != 0) 0 else 1);
}

fn activate(app: *c.GtkApplication, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    _ = user_data;

    // Use AdwApplicationWindow
    const window = c.adw_application_window_new(app);
    c.gtk_window_set_title(@ptrCast(window), "Vimp");
    c.gtk_window_set_default_size(@ptrCast(window), 800, 600);

    // Actions Setup
    const add_action = struct {
        fn func(application: *c.GtkApplication, name: [:0]const u8, callback: c.GCallback, data: ?*anyopaque) void {
            const action = c.g_simple_action_new(name, null);
            _ = c.g_signal_connect_data(action, "activate", callback, data, null, 0);
            c.g_action_map_add_action(@ptrCast(application), @ptrCast(action));
        }
    }.func;

    add_action(app, "new", @ptrCast(&new_activated), null);
    add_action(app, "open", @ptrCast(&open_activated), null);
    add_action(app, "save", @ptrCast(&save_activated), null);
    add_action(app, "about", @ptrCast(&about_activated), null);
    add_action(app, "quit", @ptrCast(&quit_activated), app);

    // Keyboard Shortcuts
    const set_accel = struct {
        fn func(application: *c.GtkApplication, action: [:0]const u8, accel: [:0]const u8) void {
            const accels = [_]?[*:0]const u8{ accel, null };
            c.gtk_application_set_accels_for_action(application, action, @ptrCast(&accels));
        }
    }.func;
    set_accel(app, "app.quit", "<Ctrl>q");
    set_accel(app, "app.new", "<Ctrl>n");
    set_accel(app, "app.open", "<Ctrl>o");
    set_accel(app, "app.save", "<Ctrl>s");

    const toolbar_view = c.adw_toolbar_view_new();
    c.adw_application_window_set_content(@ptrCast(window), toolbar_view);

    // AdwOverlaySplitView
    const split_view = c.adw_overlay_split_view_new();
    c.adw_toolbar_view_set_content(@ptrCast(toolbar_view), split_view);

    const header_bar = c.adw_header_bar_new();
    c.adw_toolbar_view_add_top_bar(@ptrCast(toolbar_view), header_bar);

    // Sidebar Toggle Button
    const sidebar_btn = c.gtk_button_new_from_icon_name("sidebar-show-symbolic");
    c.gtk_widget_set_tooltip_text(sidebar_btn, "Toggle Sidebar");
    c.adw_header_bar_pack_start(@ptrCast(header_bar), sidebar_btn);
    _ = c.g_signal_connect_data(sidebar_btn, "clicked", @ptrCast(&sidebar_toggled), split_view, null, 0);
    // Only show button when collapsed
    _ = c.g_object_bind_property(@ptrCast(split_view), "collapsed", @ptrCast(sidebar_btn), "visible", c.G_BINDING_SYNC_CREATE);

    // Primary Actions (Start)
    const new_btn = c.gtk_button_new_from_icon_name("document-new-symbolic");
    c.gtk_actionable_set_action_name(@ptrCast(new_btn), "app.new");
    c.gtk_widget_set_tooltip_text(new_btn, "New");
    c.adw_header_bar_pack_start(@ptrCast(header_bar), new_btn);

    const open_btn = c.gtk_button_new_from_icon_name("document-open-symbolic");
    c.gtk_actionable_set_action_name(@ptrCast(open_btn), "app.open");
    c.gtk_widget_set_tooltip_text(open_btn, "Open");
    c.adw_header_bar_pack_start(@ptrCast(header_bar), open_btn);

    const save_btn = c.gtk_button_new_from_icon_name("document-save-symbolic");
    c.gtk_actionable_set_action_name(@ptrCast(save_btn), "app.save");
    c.gtk_widget_set_tooltip_text(save_btn, "Save");
    c.adw_header_bar_pack_start(@ptrCast(header_bar), save_btn);

    // Hamburger Menu (End)
    const menu = c.g_menu_new();
    c.g_menu_append(menu, "About Vimp", "app.about");
    c.g_menu_append(menu, "Quit", "app.quit");

    const menu_btn = c.gtk_menu_button_new();
    c.gtk_menu_button_set_icon_name(@ptrCast(menu_btn), "open-menu-symbolic");
    c.gtk_menu_button_set_menu_model(@ptrCast(menu_btn), @ptrCast(@alignCast(menu)));
    c.gtk_widget_set_tooltip_text(menu_btn, "Menu");

    c.adw_header_bar_pack_end(@ptrCast(header_bar), menu_btn);

    // Sidebar (Left / Sidebar Pane)
    const sidebar = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_size_request(sidebar, 200, -1);
    c.gtk_widget_add_css_class(sidebar, "sidebar");

    // Set as sidebar in split view
    c.adw_overlay_split_view_set_sidebar(@ptrCast(split_view), sidebar);

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

    // Main Content (Right / Content Pane)
    const content = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    c.gtk_widget_set_hexpand(content, 1);
    c.gtk_widget_add_css_class(content, "content");

    // Set as content in split view
    c.adw_overlay_split_view_set_content(@ptrCast(split_view), content);

    // Drawing Area
    const drawing_area = c.gtk_drawing_area_new();
    c.gtk_widget_set_hexpand(drawing_area, 1);
    c.gtk_widget_set_vexpand(drawing_area, 1);
    c.gtk_drawing_area_set_draw_func(@ptrCast(drawing_area), draw_func, null, null);
    c.gtk_box_append(@ptrCast(content), drawing_area);

    // Gestures
    const drag = c.gtk_gesture_drag_new();
    // Allow Middle Click (Button 2)
    c.gtk_gesture_single_set_button(@ptrCast(drag), 0); // 0 = all buttons
    c.gtk_widget_add_controller(drawing_area, @ptrCast(drag));

    _ = c.g_signal_connect_data(drag, "drag-begin", @ptrCast(&drag_begin), null, null, 0);
    _ = c.g_signal_connect_data(drag, "drag-update", @ptrCast(&drag_update), drawing_area, null, 0);

    // Motion Controller (for mouse tracking)
    const motion = c.gtk_event_controller_motion_new();
    c.gtk_widget_add_controller(drawing_area, @ptrCast(motion));
    _ = c.g_signal_connect_data(motion, "motion", @ptrCast(&motion_func), null, null, 0);

    // Scroll Gesture
    const scroll_flags = c.GTK_EVENT_CONTROLLER_SCROLL_VERTICAL | c.GTK_EVENT_CONTROLLER_SCROLL_HORIZONTAL;
    const scroll = c.gtk_event_controller_scroll_new(scroll_flags);
    c.gtk_widget_add_controller(drawing_area, @ptrCast(scroll));
    _ = c.g_signal_connect_data(scroll, "scroll", @ptrCast(&scroll_func), drawing_area, null, 0);

    // CSS Styling
    const css_provider = c.gtk_css_provider_new();
    const css =
        \\.sidebar { background-color: shade(@theme_bg_color, 0.95); border-right: 1px solid alpha(currentColor, 0.15); padding: 10px; }
        \\.content { background-color: @theme_bg_color; }
    ;
    // Note: Adwaita handles colors better, using shared variables
    c.gtk_css_provider_load_from_data(css_provider, css, -1);

    const display = c.gtk_widget_get_display(@ptrCast(window));
    c.gtk_style_context_add_provider_for_display(display, @ptrCast(css_provider), c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    c.g_object_unref(css_provider);

    c.gtk_window_present(@ptrCast(window));
}
