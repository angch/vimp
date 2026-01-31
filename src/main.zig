const std = @import("std");

const c = @import("c.zig").c;
const Engine = @import("engine.zig").Engine;

// Global state for simplicity in this phase
const Tool = enum {
    brush,
    pencil,
    airbrush,
    eraser,
    bucket_fill,
    rect_select,
    ellipse_select,
    // pencil, // Reorder if desired, but append is safer for diffs usually
};

var engine: Engine = .{};
var surface: ?*c.cairo_surface_t = null;
var prev_x: f64 = 0;
var prev_y: f64 = 0;
var mouse_x: f64 = 0;
var mouse_y: f64 = 0;
var current_tool: Tool = .brush;

var layers_list_box: ?*c.GtkWidget = null;
var undo_list_box: ?*c.GtkWidget = null;
var drawing_area: ?*c.GtkWidget = null;
var apply_preview_btn: ?*c.GtkWidget = null;
var discard_preview_btn: ?*c.GtkWidget = null;

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
            .brush => {
                engine.setMode(.paint);
                engine.setBrushType(.circle);
            },
            .pencil => {
                engine.setMode(.paint);
                engine.setBrushType(.square);
            },
            .airbrush => {
                engine.setMode(.airbrush);
                engine.setBrushType(.circle);
            },
            .eraser => {
                engine.setMode(.erase);
                // Eraser shape? Usually square or round. Let's default to circle for now or keep previous behavior.
                // Previous behavior was square (default).
                // Let's make eraser square for consistency with typical pixel erasers, or circle.
                // Let's stick to square for eraser for now as it was default.
                engine.setBrushType(.square);
            },
            .bucket_fill => engine.setMode(.fill),
            .rect_select => {
                engine.setSelectionMode(.rectangle);
            },
            .ellipse_select => {
                engine.setSelectionMode(.ellipse);
            },
        }
    }
}

fn refresh_undo_ui() void {
    if (undo_list_box) |box| {
        // Clear children
        var child = c.gtk_widget_get_first_child(@ptrCast(box));
        while (child != null) {
            const next = c.gtk_widget_get_next_sibling(child);
            c.gtk_list_box_remove(@ptrCast(box), child);
            child = next;
        }

        // Add undo commands
        for (engine.undo_stack.items) |cmd| {
            const desc = cmd.description();
            const label = c.gtk_label_new(desc);
            c.gtk_widget_set_halign(label, c.GTK_ALIGN_START);
            c.gtk_widget_set_margin_start(label, 5);
            c.gtk_list_box_insert(@ptrCast(box), label, -1);
        }
    }
}

// Keep these alive
var brush_tool = Tool.brush;
var pencil_tool = Tool.pencil;
var airbrush_tool = Tool.airbrush;
var eraser_tool = Tool.eraser;
var bucket_fill_tool = Tool.bucket_fill;
var rect_select_tool = Tool.rect_select;
var ellipse_select_tool = Tool.ellipse_select;

// View State
var view_scale: f64 = 1.0;
var view_x: f64 = 0.0;
var view_y: f64 = 0.0;

fn draw_func(
    widget: [*c]c.GtkDrawingArea,
    cr: ?*c.cairo_t,
    width: c_int,
    height: c_int,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    _ = user_data;
    _ = widget;

    if (surface == null) {
        if (width > 0 and height > 0) {
            const s = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, width, height);
            if (c.cairo_surface_status(s) != c.CAIRO_STATUS_SUCCESS) {
                std.debug.print("Failed to create surface: {}\n", .{c.cairo_surface_status(s)});
                c.cairo_surface_destroy(s);
                return;
            }
            surface = s;
        } else {
            return;
        }
    }

    // US-003: Render from GEGL
    if (surface) |s| {
        // Verify surface is still valid
        if (c.cairo_surface_status(s) != c.CAIRO_STATUS_SUCCESS) {
            c.cairo_surface_destroy(s);
            surface = null;
            return;
        }

        c.cairo_surface_flush(s);
        const data = c.cairo_image_surface_get_data(s);
        if (data == null) {
            std.debug.print("Surface data is null\n", .{});
            return;
        }

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

            // Draw Selection Overlay
            if (engine.selection) |sel| {
                const r: f64 = @floatFromInt(sel.x);
                const g: f64 = @floatFromInt(sel.y);
                const w: f64 = @floatFromInt(sel.width);
                const h: f64 = @floatFromInt(sel.height);

                // Convert to Screen Coordinates
                const sx = r * view_scale - view_x;
                const sy = g * view_scale - view_y;
                const sw = w * view_scale;
                const sh = h * view_scale;

                c.cairo_save(cr_ctx);

                if (engine.selection_mode == .ellipse) {
                    var matrix: c.cairo_matrix_t = undefined;
                    c.cairo_get_matrix(cr_ctx, &matrix);

                    c.cairo_translate(cr_ctx, sx + sw / 2.0, sy + sh / 2.0);
                    c.cairo_scale(cr_ctx, sw / 2.0, sh / 2.0);
                    c.cairo_arc(cr_ctx, 0.0, 0.0, 1.0, 0.0, 2.0 * std.math.pi);

                    c.cairo_set_matrix(cr_ctx, &matrix);
                } else {
                    c.cairo_rectangle(cr_ctx, sx, sy, sw, sh);
                }

                // Marching ants (static for now)
                const dash: [2]f64 = .{ 4.0, 4.0 };
                c.cairo_set_dash(cr_ctx, &dash, 2, 0);
                c.cairo_set_source_rgb(cr_ctx, 1.0, 1.0, 1.0); // White
                c.cairo_set_line_width(cr_ctx, 1.0);
                c.cairo_stroke_preserve(cr_ctx);

                c.cairo_set_source_rgb(cr_ctx, 0.0, 0.0, 0.0); // Black contrast
                c.cairo_set_dash(cr_ctx, &dash, 2, 4.0); // Offset
                c.cairo_stroke(cr_ctx);
                c.cairo_restore(cr_ctx);
            }
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
    gesture: ?*c.GtkGestureDrag,
    x: f64,
    y: f64,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    prev_x = x;
    prev_y = y;

    if (user_data != null) {
        const ud = user_data.?;
        // alignCast might panic if ud is not aligned to *GtkWidget (8 bytes usually)
        // ud comes from @ptrCast(@alignCast(drawing_area)) which should be aligned.
        const widget: *c.GtkWidget = @ptrCast(@alignCast(ud));

        // Check button safely
        var button: c_uint = 0;
        if (gesture) |g| {
            button = c.gtk_gesture_single_get_current_button(@ptrCast(g));
        }

        if (button == 1) {
            if (current_tool == .bucket_fill) {
                engine.beginTransaction();
                const c_x = (view_x + x) / view_scale;
                const c_y = (view_y + y) / view_scale;
                engine.bucketFill(c_x, c_y) catch |err| {
                    std.debug.print("Bucket fill failed: {}\n", .{err});
                };
                engine.commitTransaction();
                c.gtk_widget_queue_draw(widget);
            } else if (current_tool == .rect_select or current_tool == .ellipse_select) {
                // Start selection - maybe clear existing?
                engine.beginSelection();
                engine.clearSelection();
                c.gtk_widget_queue_draw(widget);
            } else {
                // Paint tools
                engine.beginTransaction();
            }
        }
    }
}

fn drag_update(
    gesture: ?*c.GtkGestureDrag,
    offset_x: f64,
    offset_y: f64,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    if (user_data == null) return;
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
        if (current_tool == .bucket_fill) {
            // Bucket fill handled in drag_begin, do nothing on drag
            return;
        }

        const c_prev_x = (view_x + prev_x) / view_scale;
        const c_prev_y = (view_y + prev_y) / view_scale;
        const c_curr_x = (view_x + current_x) / view_scale;
        const c_curr_y = (view_y + current_y) / view_scale;

        if (current_tool == .rect_select or current_tool == .ellipse_select) {
            // Dragging selection
            // Start point was recorded in drag_begin implicitly?
            // No, drag_update gives offset from start.
            // start_sx, start_sy from gtk_gesture_drag_get_start_point are screen coords.

            const start_world_x = (view_x + start_sx) / view_scale;
            const start_world_y = (view_y + start_sy) / view_scale;

            // Calculate min/max
            const min_x: c_int = @intFromFloat(@min(start_world_x, c_curr_x));
            const min_y: c_int = @intFromFloat(@min(start_world_y, c_curr_y));
            const max_x: c_int = @intFromFloat(@max(start_world_x, c_curr_x));
            const max_y: c_int = @intFromFloat(@max(start_world_y, c_curr_y));

            engine.setSelection(min_x, min_y, max_x - min_x, max_y - min_y);
            c.gtk_widget_queue_draw(widget);

            prev_x = current_x;
            prev_y = current_y;
            return;
        }

        // Default pressure 1.0 for now
        engine.paintStroke(c_prev_x, c_prev_y, c_curr_x, c_curr_y, 1.0);
        c.gtk_widget_queue_draw(widget);
    }

    prev_x = current_x;
    prev_y = current_y;
}

fn drag_end(
    gesture: ?*c.GtkGestureDrag,
    offset_x: f64,
    offset_y: f64,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    _ = gesture;
    _ = offset_x;
    _ = offset_y;
    _ = user_data;

    // Commit transaction if any (e.g. from paint tools)
    engine.commitTransaction();
    refresh_undo_ui();
}

fn new_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    std.debug.print("New activated\n", .{});
}

fn open_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    std.debug.print("Open activated\n", .{});
}

fn save_surface_to_file(s: *c.cairo_surface_t, filename: [*c]const u8) void {
    const result = c.cairo_surface_write_to_png(s, filename);
    if (result == c.CAIRO_STATUS_SUCCESS) {
        std.debug.print("File saved to: {s}\n", .{filename});
    } else {
        std.debug.print("Error saving file: {d}\n", .{result});
    }
}

fn save_file(filename: [*c]const u8) void {
    if (surface) |s| {
        if (c.cairo_surface_status(s) == c.CAIRO_STATUS_SUCCESS) {
            save_surface_to_file(s, filename);
        } else {
            std.debug.print("Surface invalid, cannot save.\n", .{});
        }
    } else {
        std.debug.print("No surface to save.\n", .{});
    }
}

fn save_finish(source_object: ?*c.GObject, res: ?*c.GAsyncResult, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    _ = user_data;
    var err: ?*c.GError = null;
    const file = c.gtk_file_dialog_save_finish(@ptrCast(source_object), res, &err);
    if (file) |f| {
        const path = c.g_file_get_path(f);
        if (path) |p| {
            save_file(p);
            c.g_free(p);
        }
        c.g_object_unref(f);
    } else {
        if (err) |e| {
            std.debug.print("Error saving: {s}\n", .{e.*.message});
            c.g_error_free(e);
        }
    }
}

fn save_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: *c.GtkWindow = @ptrCast(@alignCast(user_data));
    const dialog = c.gtk_file_dialog_new();
    c.gtk_file_dialog_set_title(dialog, "Save Canvas");
    c.gtk_file_dialog_set_initial_name(dialog, "untitled.png");

    // Optional: Set filters for PNG
    const filters = c.g_list_store_new(c.gtk_file_filter_get_type());
    const filter_png = c.gtk_file_filter_new();
    c.gtk_file_filter_set_name(filter_png, "PNG Image");
    c.gtk_file_filter_add_pattern(filter_png, "*.png");
    c.g_list_store_append(filters, filter_png); // Transfer ownership? ListStore holds ref.
    c.g_object_unref(filter_png);

    // GtkFileDialog takes ownership of filters? No, it uses the model.
    // gtk_file_dialog_set_filters (GtkFileDialog *self, GListModel *filters)
    c.gtk_file_dialog_set_filters(dialog, @ptrCast(filters));
    c.g_object_unref(filters);

    c.gtk_file_dialog_save(dialog, window, null, @ptrCast(&save_finish), null);
    c.g_object_unref(dialog);
}

test "save surface" {
    const s = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, 10, 10);
    defer c.cairo_surface_destroy(s);
    save_surface_to_file(s, "test_save.png");
    // Verify file exists
    const file = std.fs.cwd().openFile("test_save.png", .{}) catch |err| {
        std.debug.print("Failed to open test file: {}\n", .{err});
        return err;
    };
    file.close();
    std.fs.cwd().deleteFile("test_save.png") catch {};
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

fn undo_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.undo();
    queue_draw();
    refresh_undo_ui();
}

fn redo_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.redo();
    queue_draw();
    refresh_undo_ui();
}

fn refresh_header_ui() void {
    if (apply_preview_btn) |btn| {
        c.gtk_widget_set_visible(btn, if (engine.preview_mode != .none) 1 else 0);
    }
    if (discard_preview_btn) |btn| {
        c.gtk_widget_set_visible(btn, if (engine.preview_mode != .none) 1 else 0);
    }
}

fn blur_small_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.setPreviewBlur(5.0);
    refresh_header_ui();
    queue_draw();
}

fn blur_medium_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.setPreviewBlur(10.0);
    refresh_header_ui();
    queue_draw();
}

fn blur_large_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.setPreviewBlur(20.0);
    refresh_header_ui();
    queue_draw();
}

fn apply_preview_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.commitPreview() catch |err| {
        std.debug.print("Commit preview failed: {}\n", .{err});
    };
    refresh_header_ui();
    queue_draw();
    refresh_undo_ui();
}

fn discard_preview_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.cancelPreview();
    refresh_header_ui();
    queue_draw();
}

fn split_view_change_state(action: *c.GSimpleAction, value: *c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const enabled = c.g_variant_get_boolean(value) != 0;
    engine.setSplitView(enabled);
    c.g_simple_action_set_state(action, value);
    queue_draw();
}

fn sidebar_toggled(
    _: *c.GtkButton,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    const split_view: *c.AdwOverlaySplitView = @ptrCast(@alignCast(user_data));
    const is_shown = c.adw_overlay_split_view_get_show_sidebar(split_view);
    c.adw_overlay_split_view_set_show_sidebar(split_view, if (is_shown != 0) 0 else 1);
}

fn queue_draw() void {
    if (drawing_area) |w| {
        c.gtk_widget_queue_draw(w);
    }
}

fn refresh_layers_ui() void {
    if (layers_list_box) |box| {
        // Clear children
        var child = c.gtk_widget_get_first_child(@ptrCast(box));
        while (child != null) {
            const next = c.gtk_widget_get_next_sibling(child);
            c.gtk_list_box_remove(@ptrCast(box), child);
            child = next;
        }

        // Add layers (reversed: Top layer first)
        var i: usize = engine.layers.items.len;
        while (i > 0) {
            i -= 1;
            const idx = i;
            const layer = &engine.layers.items[idx];
            const user_data: ?*anyopaque = if (idx == 0) null else @ptrFromInt(idx);

            const row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 5);

            // Visible Check
            const vis_check = c.gtk_check_button_new();
            c.gtk_check_button_set_active(@ptrCast(vis_check), if (layer.visible) 1 else 0);
            c.gtk_widget_set_tooltip_text(vis_check, "Visible");
            _ = c.g_signal_connect_data(vis_check, "toggled", @ptrCast(&layer_visibility_toggled), user_data, null, 0);
            c.gtk_box_append(@ptrCast(row), vis_check);

            // Lock Check
            const lock_check = c.gtk_check_button_new();
            c.gtk_check_button_set_active(@ptrCast(lock_check), if (layer.locked) 1 else 0);
            c.gtk_widget_set_tooltip_text(lock_check, "Lock");
            _ = c.g_signal_connect_data(lock_check, "toggled", @ptrCast(&layer_lock_toggled), user_data, null, 0);
            c.gtk_box_append(@ptrCast(row), lock_check);

            // Name Label
            const name_span = std.mem.span(@as([*:0]const u8, @ptrCast(&layer.name)));
            const label = c.gtk_label_new(name_span.ptr);
            c.gtk_widget_set_hexpand(label, 1);
            c.gtk_widget_set_halign(label, c.GTK_ALIGN_START);
            c.gtk_box_append(@ptrCast(row), label);

            c.gtk_list_box_insert(@ptrCast(box), row, -1);

            // Select if active (Wait, creating row doesn't give GtkListBoxRow easily here unless we query or wrap)
            // GtkListBox wraps generic widget in a GtkListBoxRow automatically.
            // We can get it after insertion? Or explicitly create GtkListBoxRow.
            // Let's rely on auto-wrapping and iterate children to select? Or just ignore selection visual for now if tricky?
            // Actually, correct way: create GtkListBoxRow, set child, insert Row.
            // But we can verify active layer by list selection later.
        }
    }
}

fn layer_visibility_toggled(_: *c.GtkCheckButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const idx = @intFromPtr(user_data);
    engine.toggleLayerVisibility(idx);
    queue_draw();
    refresh_undo_ui();
}

fn layer_lock_toggled(_: *c.GtkCheckButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const idx = @intFromPtr(user_data);
    engine.toggleLayerLock(idx);
    refresh_undo_ui();
}

fn layer_add_clicked(_: *c.GtkButton, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.addLayer("New Layer") catch return;
    refresh_layers_ui();
    refresh_undo_ui();
    queue_draw();
}

fn layer_remove_clicked(_: *c.GtkButton, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.removeLayer(engine.active_layer_idx);
    refresh_layers_ui();
    refresh_undo_ui();
    queue_draw();
}

fn layer_up_clicked(_: *c.GtkButton, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const idx = engine.active_layer_idx;
    if (idx + 1 < engine.layers.items.len) {
        engine.reorderLayer(idx, idx + 1);
        refresh_layers_ui();
        refresh_undo_ui();
        queue_draw();
    }
}

fn layer_down_clicked(_: *c.GtkButton, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const idx = engine.active_layer_idx;
    if (idx > 0) {
        engine.reorderLayer(idx, idx - 1);
        refresh_layers_ui();
        refresh_undo_ui();
        queue_draw();
    }
}

fn layer_selected(_: *c.GtkListBox, row: ?*c.GtkListBoxRow, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    if (row) |r| {
        const index_in_list = c.gtk_list_box_row_get_index(r);
        if (index_in_list >= 0) {
            const k: usize = @intCast(index_in_list);
            if (k < engine.layers.items.len) {
                const layer_idx = engine.layers.items.len - 1 - k;
                engine.setActiveLayer(layer_idx);
            }
        }
    }
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
    add_action(app, "save", @ptrCast(&save_activated), window);
    add_action(app, "about", @ptrCast(&about_activated), null);
    add_action(app, "quit", @ptrCast(&quit_activated), app);
    add_action(app, "undo", @ptrCast(&undo_activated), null);
    add_action(app, "redo", @ptrCast(&redo_activated), null);
    add_action(app, "blur-small", @ptrCast(&blur_small_activated), null);
    add_action(app, "blur-medium", @ptrCast(&blur_medium_activated), null);
    add_action(app, "blur-large", @ptrCast(&blur_large_activated), null);
    add_action(app, "apply-preview", @ptrCast(&apply_preview_activated), null);
    add_action(app, "discard-preview", @ptrCast(&discard_preview_activated), null);

    // Split View Action (Stateful)
    const split_action = c.g_simple_action_new_stateful("split-view", null, c.g_variant_new_boolean(0));
    _ = c.g_signal_connect_data(split_action, "change-state", @ptrCast(&split_view_change_state), null, null, 0);
    c.g_action_map_add_action(@ptrCast(app), @ptrCast(split_action));

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
    set_accel(app, "app.undo", "<Ctrl>z");
    set_accel(app, "app.redo", "<Ctrl>y");

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

    // Undo/Redo
    const undo_btn = c.gtk_button_new_from_icon_name("edit-undo-symbolic");
    c.gtk_actionable_set_action_name(@ptrCast(undo_btn), "app.undo");
    c.gtk_widget_set_tooltip_text(undo_btn, "Undo");
    c.adw_header_bar_pack_start(@ptrCast(header_bar), undo_btn);

    const redo_btn = c.gtk_button_new_from_icon_name("edit-redo-symbolic");
    c.gtk_actionable_set_action_name(@ptrCast(redo_btn), "app.redo");
    c.gtk_widget_set_tooltip_text(redo_btn, "Redo");
    c.adw_header_bar_pack_start(@ptrCast(header_bar), redo_btn);

    // Filters Menu
    const filters_menu = c.g_menu_new();
    c.g_menu_append(filters_menu, "Blur (5px)", "app.blur-small");
    c.g_menu_append(filters_menu, "Blur (10px)", "app.blur-medium");
    c.g_menu_append(filters_menu, "Blur (20px)", "app.blur-large");
    c.g_menu_append(filters_menu, "Split View", "app.split-view");

    const filters_btn = c.gtk_menu_button_new();
    c.gtk_menu_button_set_label(@ptrCast(filters_btn), "Filters");
    c.gtk_menu_button_set_menu_model(@ptrCast(filters_btn), @ptrCast(@alignCast(filters_menu)));
    c.gtk_widget_set_tooltip_text(filters_btn, "Image Filters");
    c.adw_header_bar_pack_start(@ptrCast(header_bar), filters_btn);

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
        fn func(tool_val: *Tool, icon_path: [:0]const u8, tooltip: [:0]const u8, group: ?*c.GtkToggleButton, is_icon_name: bool) *c.GtkWidget {
            const btn = if (group) |_| c.gtk_toggle_button_new() else c.gtk_toggle_button_new();
            if (group) |g| c.gtk_toggle_button_set_group(@ptrCast(btn), g);

            const img = if (is_icon_name)
                c.gtk_image_new_from_icon_name(icon_path)
            else
                c.gtk_image_new_from_file(icon_path);

            c.gtk_widget_set_size_request(img, 24, 24);
            c.gtk_button_set_child(@ptrCast(btn), img);
            c.gtk_widget_set_tooltip_text(btn, tooltip);

            _ = c.g_signal_connect_data(btn, "toggled", @ptrCast(&tool_toggled), tool_val, null, 0);
            return btn;
        }
    }.func;

    // Brush
    const brush_btn = createToolButton(&brush_tool, "assets/brush.png", "Brush", null, false);
    c.gtk_box_append(@ptrCast(tools_box), brush_btn);
    c.gtk_toggle_button_set_active(@ptrCast(brush_btn), 1);

    // Pencil
    const pencil_btn = createToolButton(&pencil_tool, "assets/pencil.png", "Pencil", @ptrCast(brush_btn), false);
    c.gtk_box_append(@ptrCast(tools_box), pencil_btn);

    // Airbrush
    const airbrush_btn = createToolButton(&airbrush_tool, "assets/airbrush.png", "Airbrush", @ptrCast(brush_btn), false);
    c.gtk_box_append(@ptrCast(tools_box), airbrush_btn);

    // Eraser
    const eraser_btn = createToolButton(&eraser_tool, "assets/eraser.png", "Eraser", @ptrCast(brush_btn), false);
    c.gtk_box_append(@ptrCast(tools_box), eraser_btn);

    // Bucket Fill
    const fill_btn = createToolButton(&bucket_fill_tool, "assets/bucket.png", "Bucket Fill", @ptrCast(brush_btn), false);
    c.gtk_box_append(@ptrCast(tools_box), fill_btn);

    // Rect Select
    const select_btn = createToolButton(&rect_select_tool, "edit-select-symbolic", "Rectangle Select", @ptrCast(brush_btn), true);
    c.gtk_box_append(@ptrCast(tools_box), select_btn);

    // Ellipse Select
    const ellipse_btn = createToolButton(&ellipse_select_tool, "media-record-symbolic", "Ellipse Select", @ptrCast(brush_btn), true);
    c.gtk_box_append(@ptrCast(tools_box), ellipse_btn);

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

    // Layers Section
    c.gtk_box_append(@ptrCast(sidebar), c.gtk_separator_new(c.GTK_ORIENTATION_HORIZONTAL));

    c.gtk_box_append(@ptrCast(sidebar), c.gtk_label_new("Layers"));

    const layers_list = c.gtk_list_box_new();
    c.gtk_widget_set_vexpand(layers_list, 1);
    c.gtk_list_box_set_selection_mode(@ptrCast(layers_list), c.GTK_SELECTION_SINGLE);
    _ = c.g_signal_connect_data(layers_list, "row-selected", @ptrCast(&layer_selected), null, null, 0);

    const scrolled = c.gtk_scrolled_window_new();
    c.gtk_scrolled_window_set_child(@ptrCast(scrolled), layers_list);
    c.gtk_widget_set_vexpand(scrolled, 1);
    c.gtk_box_append(@ptrCast(sidebar), scrolled);

    layers_list_box = layers_list;

    const layers_btns = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 5);
    c.gtk_widget_set_halign(layers_btns, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(sidebar), layers_btns);

    const add_layer_btn = c.gtk_button_new_from_icon_name("list-add-symbolic");
    c.gtk_widget_set_tooltip_text(add_layer_btn, "Add Layer");
    c.gtk_box_append(@ptrCast(layers_btns), add_layer_btn);
    _ = c.g_signal_connect_data(add_layer_btn, "clicked", @ptrCast(&layer_add_clicked), null, null, 0);

    const remove_layer_btn = c.gtk_button_new_from_icon_name("list-remove-symbolic");
    c.gtk_widget_set_tooltip_text(remove_layer_btn, "Remove Layer");
    c.gtk_box_append(@ptrCast(layers_btns), remove_layer_btn);
    _ = c.g_signal_connect_data(remove_layer_btn, "clicked", @ptrCast(&layer_remove_clicked), null, null, 0);

    const up_layer_btn = c.gtk_button_new_from_icon_name("go-up-symbolic");
    c.gtk_widget_set_tooltip_text(up_layer_btn, "Move Up");
    c.gtk_box_append(@ptrCast(layers_btns), up_layer_btn);
    _ = c.g_signal_connect_data(up_layer_btn, "clicked", @ptrCast(&layer_up_clicked), null, null, 0);

    const down_layer_btn = c.gtk_button_new_from_icon_name("go-down-symbolic");
    c.gtk_widget_set_tooltip_text(down_layer_btn, "Move Down");
    c.gtk_box_append(@ptrCast(layers_btns), down_layer_btn);
    _ = c.g_signal_connect_data(down_layer_btn, "clicked", @ptrCast(&layer_down_clicked), null, null, 0);

    // Undo History Section
    c.gtk_box_append(@ptrCast(sidebar), c.gtk_separator_new(c.GTK_ORIENTATION_HORIZONTAL));
    c.gtk_box_append(@ptrCast(sidebar), c.gtk_label_new("Undo History"));

    const undo_list = c.gtk_list_box_new();
    c.gtk_list_box_set_selection_mode(@ptrCast(undo_list), c.GTK_SELECTION_NONE);

    const undo_scrolled = c.gtk_scrolled_window_new();
    c.gtk_scrolled_window_set_child(@ptrCast(undo_scrolled), undo_list);
    c.gtk_widget_set_vexpand(undo_scrolled, 1);
    c.gtk_box_append(@ptrCast(sidebar), undo_scrolled);

    undo_list_box = undo_list;

    // Main Content (Right / Content Pane)
    const content = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    c.gtk_widget_set_hexpand(content, 1);
    c.gtk_widget_add_css_class(content, "content");

    // Set as content in split view
    c.adw_overlay_split_view_set_content(@ptrCast(split_view), content);

    // Drawing Area
    const area = c.gtk_drawing_area_new();
    drawing_area = area;
    c.gtk_widget_set_hexpand(area, 1);
    c.gtk_widget_set_vexpand(area, 1);
    c.gtk_drawing_area_set_draw_func(@ptrCast(area), draw_func, null, null);
    c.gtk_box_append(@ptrCast(content), area);

    // Gestures
    const drag = c.gtk_gesture_drag_new();
    // Allow Middle Click (Button 2)
    c.gtk_gesture_single_set_button(@ptrCast(drag), 0); // 0 = all buttons
    c.gtk_widget_add_controller(area, @ptrCast(drag));

    _ = c.g_signal_connect_data(drag, "drag-begin", @ptrCast(&drag_begin), @ptrCast(area), null, 0);
    _ = c.g_signal_connect_data(drag, "drag-update", @ptrCast(&drag_update), @ptrCast(area), null, 0);
    _ = c.g_signal_connect_data(drag, "drag-end", @ptrCast(&drag_end), @ptrCast(area), null, 0);

    // Motion Controller (for mouse tracking)
    const motion = c.gtk_event_controller_motion_new();
    c.gtk_widget_add_controller(area, @ptrCast(motion));
    _ = c.g_signal_connect_data(motion, "motion", @ptrCast(&motion_func), null, null, 0);

    // Scroll Gesture
    const scroll_flags = c.GTK_EVENT_CONTROLLER_SCROLL_VERTICAL | c.GTK_EVENT_CONTROLLER_SCROLL_HORIZONTAL;
    const scroll = c.gtk_event_controller_scroll_new(scroll_flags);
    c.gtk_widget_add_controller(area, @ptrCast(scroll));
    _ = c.g_signal_connect_data(scroll, "scroll", @ptrCast(&scroll_func), area, null, 0);

    // Refresh Layers UI initially
    refresh_layers_ui();
    refresh_undo_ui();

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
