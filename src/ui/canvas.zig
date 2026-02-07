const std = @import("std");
const c = @import("../c.zig").c;
const Engine = @import("../engine.zig").Engine;
const CanvasUtils = @import("../canvas_utils.zig");
const ToolInterface = @import("../tools/interface.zig").ToolInterface;
const ThumbnailWindow = @import("../widgets/thumbnail_window.zig");

pub const CanvasCallbacks = struct {
    refresh_undo_ui: *const fn () void,
    reset_transform_ui: *const fn () void,
};

pub const Canvas = struct {
    // Widgets
    widget: *c.GtkWidget, // The Overlay
    drawing_area: *c.GtkWidget,
    osd_label: *c.GtkWidget,
    osd_revealer: *c.GtkWidget,
    transform_action_bar: *c.GtkWidget,
    drop_revealer: *c.GtkWidget,
    drop_label: *c.GtkWidget,

    // References
    engine: *Engine,
    callbacks: CanvasCallbacks,

    // View State
    view_scale: f64 = 1.0,
    view_x: f64 = 0.0,
    view_y: f64 = 0.0,
    show_pixel_grid: bool = true,
    canvas_dirty: bool = true,
    surface: ?*c.cairo_surface_t = null,

    // Interaction State
    active_tool_interface: ?ToolInterface = null,
    is_dragging_interaction: bool = false,
    drag_button: c_uint = 0,
    prev_x: f64 = 0,
    prev_y: f64 = 0,
    mouse_x: f64 = 0,
    mouse_y: f64 = 0,

    // Zoom Gesture State
    zoom_base_scale: f64 = 1.0,
    zoom_base_view_x: f64 = 0.0,
    zoom_base_view_y: f64 = 0.0,
    zoom_base_cx: f64 = 0.0,
    zoom_base_cy: f64 = 0.0,

    // Animation State
    ants_offset: f64 = 0.0,
    ants_timer_id: c_uint = 0,
    osd_timeout_id: c_uint = 0,

    pub fn create(allocator: std.mem.Allocator, engine: *Engine, callbacks: CanvasCallbacks) !*Canvas {
        const self = try allocator.create(Canvas);
        self.* = .{
            .widget = undefined,
            .drawing_area = undefined,
            .osd_label = undefined,
            .osd_revealer = undefined,
            .transform_action_bar = undefined,
            .drop_revealer = undefined,
            .drop_label = undefined,
            .engine = engine,
            .callbacks = callbacks,
        };

        // Overlay (Canvas)
        const overlay = c.gtk_overlay_new();
        self.widget = @ptrCast(overlay);
        c.gtk_widget_set_hexpand(self.widget, 1);
        c.gtk_widget_set_vexpand(self.widget, 1);

        // Drawing Area
        const area = c.gtk_drawing_area_new();
        self.drawing_area = area;
        c.gtk_widget_set_hexpand(area, 1);
        c.gtk_widget_set_vexpand(area, 1);
        c.gtk_widget_set_focusable(area, 1);
        c.gtk_drawing_area_set_draw_func(@ptrCast(area), draw_func, self, null);
        c.gtk_overlay_set_child(@ptrCast(overlay), area);

        // OSD Widget
        const osd_revealer = c.gtk_revealer_new();
        self.osd_revealer = osd_revealer;
        c.gtk_widget_set_valign(osd_revealer, c.GTK_ALIGN_END);
        c.gtk_widget_set_halign(osd_revealer, c.GTK_ALIGN_CENTER);
        c.gtk_widget_set_margin_bottom(osd_revealer, 40);
        c.gtk_revealer_set_transition_type(@ptrCast(osd_revealer), c.GTK_REVEALER_TRANSITION_TYPE_CROSSFADE);

        const osd_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 0);
        c.gtk_widget_add_css_class(osd_box, "osd");
        c.gtk_revealer_set_child(@ptrCast(osd_revealer), osd_box);

        const osd_label = c.gtk_label_new("");
        self.osd_label = osd_label;
        c.gtk_box_append(@ptrCast(osd_box), osd_label);

        c.gtk_overlay_add_overlay(@ptrCast(overlay), osd_revealer);

        // Drop Overlay
        const drop_revealer = c.gtk_revealer_new();
        self.drop_revealer = drop_revealer;
        c.gtk_widget_set_valign(drop_revealer, c.GTK_ALIGN_CENTER);
        c.gtk_widget_set_halign(drop_revealer, c.GTK_ALIGN_CENTER);
        c.gtk_revealer_set_transition_type(@ptrCast(drop_revealer), c.GTK_REVEALER_TRANSITION_TYPE_CROSSFADE);
        c.gtk_widget_set_can_target(drop_revealer, 0); // Allow clicks through

        const drop_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
        c.gtk_widget_add_css_class(drop_box, "osd");
        c.gtk_widget_set_margin_top(drop_box, 20);
        c.gtk_widget_set_margin_bottom(drop_box, 20);
        c.gtk_widget_set_margin_start(drop_box, 20);
        c.gtk_widget_set_margin_end(drop_box, 20);
        c.gtk_revealer_set_child(@ptrCast(drop_revealer), drop_box);

        const drop_icon = c.gtk_image_new_from_icon_name("document-open-symbolic");
        c.gtk_image_set_pixel_size(@ptrCast(drop_icon), 64);
        c.gtk_box_append(@ptrCast(drop_box), drop_icon);

        const drop_label = c.gtk_label_new("Drop Image Here");
        self.drop_label = drop_label;
        c.gtk_widget_add_css_class(drop_label, "title-1");
        c.gtk_box_append(@ptrCast(drop_box), drop_label);

        c.gtk_overlay_add_overlay(@ptrCast(overlay), drop_revealer);

        // Transform Action Bar
        const t_action_bar = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 10);
        self.transform_action_bar = t_action_bar;
        c.gtk_widget_set_visible(t_action_bar, 0);
        c.gtk_widget_set_valign(t_action_bar, c.GTK_ALIGN_START);
        c.gtk_widget_set_halign(t_action_bar, c.GTK_ALIGN_CENTER);
        c.gtk_widget_set_margin_top(t_action_bar, 20);
        c.gtk_widget_add_css_class(t_action_bar, "osd");

        const t_apply = c.gtk_button_new_with_mnemonic("_Apply");
        c.gtk_widget_add_css_class(t_apply, "suggested-action");
        c.gtk_widget_set_tooltip_text(t_apply, "Apply Transformation");
        c.gtk_box_append(@ptrCast(t_action_bar), t_apply);
        _ = c.g_signal_connect_data(t_apply, "clicked", @ptrCast(&on_transform_apply), self, null, 0);

        const t_cancel = c.gtk_button_new_with_mnemonic("_Cancel");
        c.gtk_widget_set_tooltip_text(t_cancel, "Cancel Transformation");
        c.gtk_box_append(@ptrCast(t_action_bar), t_cancel);
        _ = c.g_signal_connect_data(t_cancel, "clicked", @ptrCast(&on_transform_cancel), self, null, 0);

        c.gtk_overlay_add_overlay(@ptrCast(overlay), t_action_bar);

        // Gestures
        const drag = c.gtk_gesture_drag_new();
        c.gtk_gesture_single_set_button(@ptrCast(drag), 0);
        c.gtk_widget_add_controller(area, @ptrCast(drag));

        _ = c.g_signal_connect_data(drag, "drag-begin", @ptrCast(&drag_begin), self, null, 0);
        _ = c.g_signal_connect_data(drag, "drag-update", @ptrCast(&drag_update), self, null, 0);
        _ = c.g_signal_connect_data(drag, "drag-end", @ptrCast(&drag_end), self, null, 0);

        const motion = c.gtk_event_controller_motion_new();
        c.gtk_widget_add_controller(area, @ptrCast(motion));
        _ = c.g_signal_connect_data(motion, "motion", @ptrCast(&motion_func), self, null, 0);

        const scroll_flags = c.GTK_EVENT_CONTROLLER_SCROLL_VERTICAL | c.GTK_EVENT_CONTROLLER_SCROLL_HORIZONTAL;
        const scroll = c.gtk_event_controller_scroll_new(scroll_flags);
        c.gtk_widget_add_controller(area, @ptrCast(scroll));
        _ = c.g_signal_connect_data(scroll, "scroll", @ptrCast(&scroll_func), self, null, 0);

        const zoom = c.gtk_gesture_zoom_new();
        c.gtk_widget_add_controller(area, @ptrCast(zoom));
        _ = c.g_signal_connect_data(zoom, "begin", @ptrCast(&zoom_begin), self, null, 0);
        _ = c.g_signal_connect_data(zoom, "update", @ptrCast(&zoom_update), self, null, 0);

        const key_controller = c.gtk_event_controller_key_new();
        c.gtk_widget_add_controller(area, @ptrCast(key_controller));
        _ = c.g_signal_connect_data(key_controller, "key-pressed", @ptrCast(&key_pressed_func), self, null, 0);

        return self;
    }

    pub fn queueDraw(self: *Canvas) void {
        c.gtk_widget_queue_draw(self.drawing_area);
        ThumbnailWindow.refresh();
    }

    pub fn setActiveTool(self: *Canvas, tool: ?ToolInterface) void {
        if (self.active_tool_interface) |iface| {
            iface.deactivate(self.engine);
            iface.destroy(std.heap.c_allocator);
        }
        self.active_tool_interface = tool;
        if (self.active_tool_interface) |iface| {
            iface.activate(self.engine);
        }
    }

    pub fn showOSD(self: *Canvas, text: []const u8) void {
        var buf: [128]u8 = undefined;
        const slice = std.fmt.bufPrintZ(&buf, "{s}", .{text}) catch return;
        c.gtk_label_set_text(@ptrCast(self.osd_label), slice.ptr);

        c.gtk_revealer_set_reveal_child(@ptrCast(self.osd_revealer), 1);

        if (self.osd_timeout_id != 0) {
            _ = c.g_source_remove(self.osd_timeout_id);
        }
        self.osd_timeout_id = c.g_timeout_add(1500, @ptrCast(&osd_hide_callback), self);
    }

    pub fn zoomIn(self: *Canvas) void {
        const w: f64 = @floatFromInt(c.gtk_widget_get_width(self.drawing_area));
        const h: f64 = @floatFromInt(c.gtk_widget_get_height(self.drawing_area));
        const center_x = w / 2.0;
        const center_y = h / 2.0;

        const res = CanvasUtils.calculateZoom(self.view_scale, self.view_x, self.view_y, center_x, center_y, 1.1);
        if (res.scale < 0.1 or res.scale > 50.0) return;

        self.view_scale = res.scale;
        self.view_x = res.view_x;
        self.view_y = res.view_y;
        self.canvas_dirty = true;

        var buf: [32]u8 = undefined;
        const pct: i32 = @intFromFloat(self.view_scale * 100.0);
        const txt = std.fmt.bufPrint(&buf, "Zoom: {d}%", .{pct}) catch "Zoom";
        self.showOSD(txt);

        self.queueDraw();
    }

    pub fn zoomOut(self: *Canvas) void {
        const w: f64 = @floatFromInt(c.gtk_widget_get_width(self.drawing_area));
        const h: f64 = @floatFromInt(c.gtk_widget_get_height(self.drawing_area));
        const center_x = w / 2.0;
        const center_y = h / 2.0;

        const res = CanvasUtils.calculateZoom(self.view_scale, self.view_x, self.view_y, center_x, center_y, 0.9);
        if (res.scale < 0.1 or res.scale > 50.0) return;

        self.view_scale = res.scale;
        self.view_x = res.view_x;
        self.view_y = res.view_y;
        self.canvas_dirty = true;

        var buf: [32]u8 = undefined;
        const pct: i32 = @intFromFloat(self.view_scale * 100.0);
        const txt = std.fmt.bufPrint(&buf, "Zoom: {d}%", .{pct}) catch "Zoom";
        self.showOSD(txt);

        self.queueDraw();
    }

    pub fn setSplitView(self: *Canvas, enabled: bool) void {
        self.engine.setSplitView(enabled);
        self.canvas_dirty = true;
        self.queueDraw();
    }

    pub fn setShowGrid(self: *Canvas, enabled: bool) void {
        self.show_pixel_grid = enabled;
        self.canvas_dirty = true;
        self.queueDraw();
    }

    pub fn updateTransformActionBar(self: *Canvas, is_transform_tool: bool) void {
        c.gtk_widget_set_visible(self.transform_action_bar, if (is_transform_tool) 1 else 0);
    }

    pub fn showDropOverlay(self: *Canvas, text: []const u8) void {
        var buf: [128]u8 = undefined;
        const slice = std.fmt.bufPrintZ(&buf, "{s}", .{text}) catch return;
        c.gtk_label_set_text(@ptrCast(self.drop_label), slice.ptr);
        c.gtk_revealer_set_reveal_child(@ptrCast(self.drop_revealer), 1);
    }

    pub fn hideDropOverlay(self: *Canvas) void {
        c.gtk_revealer_set_reveal_child(@ptrCast(self.drop_revealer), 0);
    }

    // Callbacks implementation
    fn on_transform_apply(_: *c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
        const self: *Canvas = @ptrCast(@alignCast(user_data));
        self.engine.applyTransform() catch |err| {
             std.debug.print("Apply transform failed: {}\n", .{err});
        };
        self.callbacks.reset_transform_ui();
        self.canvas_dirty = true;
        self.queueDraw();
        self.callbacks.refresh_undo_ui();
    }

    fn on_transform_cancel(_: *c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
        const self: *Canvas = @ptrCast(@alignCast(user_data));
        self.engine.cancelPreview();
        self.callbacks.reset_transform_ui();
        self.canvas_dirty = true;
        self.queueDraw();
    }

    fn osd_hide_callback(user_data: ?*anyopaque) callconv(.c) c.gboolean {
        const self: *Canvas = @ptrCast(@alignCast(user_data));
        c.gtk_revealer_set_reveal_child(@ptrCast(self.osd_revealer), 0);
        self.osd_timeout_id = 0;
        return 0; // G_SOURCE_REMOVE
    }

    fn ants_timer_callback(user_data: ?*anyopaque) callconv(.c) c.gboolean {
        const self: *Canvas = @ptrCast(@alignCast(user_data));
        self.ants_offset += 1.0;
        if (self.ants_offset >= 8.0) self.ants_offset -= 8.0;
        self.queueDraw();
        return 1;
    }

    fn drawDimensions(cr: *c.cairo_t, sx: f64, sy: f64, w: c_int, h: c_int) void {
        var buf: [64]u8 = undefined;
        const txt = std.fmt.bufPrintZ(&buf, "{d} x {d}", .{ @abs(w), @abs(h) }) catch return;

        c.cairo_save(cr);
        c.cairo_set_font_size(cr, 12.0);
        c.cairo_select_font_face(cr, "Sans", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);

        var extents: c.cairo_text_extents_t = undefined;
        c.cairo_text_extents(cr, txt.ptr, &extents);

        const pad = 6.0;
        const rect_w = extents.width + pad * 2.0;
        const rect_h = extents.height + pad * 2.0;

        const x = sx + 15.0;
        const y = sy + 15.0;

        // Draw background
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.7);

        // Simple rounded rect manual path
        const r = 4.0;
        const degrees = std.math.pi / 180.0;
        c.cairo_new_sub_path(cr);
        c.cairo_arc(cr, x + rect_w - r, y + r, r, -90.0 * degrees, 0.0 * degrees);
        c.cairo_arc(cr, x + rect_w - r, y + rect_h - r, r, 0.0 * degrees, 90.0 * degrees);
        c.cairo_arc(cr, x + r, y + rect_h - r, r, 90.0 * degrees, 180.0 * degrees);
        c.cairo_arc(cr, x + r, y + r, r, 180.0 * degrees, 270.0 * degrees);
        c.cairo_close_path(cr);
        c.cairo_fill(cr);

        // Draw text
        c.cairo_set_source_rgb(cr, 1.0, 1.0, 1.0);
        c.cairo_move_to(cr, x + pad, y + pad + extents.height);
        c.cairo_show_text(cr, txt.ptr);

        c.cairo_restore(cr);
    }

    fn draw_func(
        _: [*c]c.GtkDrawingArea,
        cr: ?*c.cairo_t,
        width: c_int,
        height: c_int,
        user_data: ?*anyopaque,
    ) callconv(.c) void {
        const self: *Canvas = @ptrCast(@alignCast(user_data));

        if (self.surface) |s| {
            const s_width = c.cairo_image_surface_get_width(s);
            const s_height = c.cairo_image_surface_get_height(s);
            if (s_width != width or s_height != height) {
                c.cairo_surface_destroy(s);
                self.surface = null;
                self.canvas_dirty = true;
            }
        }

        if (self.surface == null) {
            if (width > 0 and height > 0) {
                const s = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, width, height);
                if (c.cairo_surface_status(s) != c.CAIRO_STATUS_SUCCESS) {
                    std.debug.print("Failed to create surface: {}\n", .{c.cairo_surface_status(s)});
                    c.cairo_surface_destroy(s);
                    return;
                }
                self.surface = s;
                self.canvas_dirty = true;
            } else {
                return;
            }
        }

        // US-003: Render from GEGL
        if (self.surface) |s| {
            if (c.cairo_surface_status(s) != c.CAIRO_STATUS_SUCCESS) {
                c.cairo_surface_destroy(s);
                self.surface = null;
                return;
            }

            if (self.engine.layers.list.items.len > 0 and self.canvas_dirty) {
                c.cairo_surface_flush(s);
                const data = c.cairo_image_surface_get_data(s);
                if (data == null) {
                    std.debug.print("Surface data is null\n", .{});
                    return;
                }

                const stride = c.cairo_image_surface_get_stride(s);
                const s_width = c.cairo_image_surface_get_width(s);
                const s_height = c.cairo_image_surface_get_height(s);

                self.engine.blitView(s_width, s_height, data, stride, self.view_scale, self.view_x, self.view_y);

                c.cairo_surface_mark_dirty(s);
                self.canvas_dirty = false;
            }
        }

        if (self.surface) |s| {
            if (cr) |cr_ctx| {
                if (self.engine.layers.list.items.len > 0) {
                    c.cairo_set_source_surface(cr_ctx, s, 0, 0);
                    c.cairo_paint(cr_ctx);

                    if (self.show_pixel_grid) {
                        CanvasUtils.drawPixelGrid(cr_ctx, @floatFromInt(width), @floatFromInt(height), self.view_scale, self.view_x, self.view_y);
                    }
                } else {
                    c.cairo_set_source_rgb(cr_ctx, 0.15, 0.15, 0.15); // Dark Gray
                    c.cairo_paint(cr_ctx);

                    c.cairo_set_source_rgb(cr_ctx, 0.6, 0.6, 0.6); // Light Gray Text
                    c.cairo_select_font_face(cr_ctx, "Sans", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
                    c.cairo_set_font_size(cr_ctx, 20.0);

                    var extents: c.cairo_text_extents_t = undefined;
                    const msg = "No Active Image";
                    c.cairo_text_extents(cr_ctx, msg, &extents);
                    const x = (@as(f64, @floatFromInt(width)) / 2.0) - (extents.width / 2.0 + extents.x_bearing);
                    const y = (@as(f64, @floatFromInt(height)) / 2.0) - (extents.height / 2.0 + extents.y_bearing);

                    c.cairo_move_to(cr_ctx, x, y);
                    c.cairo_show_text(cr_ctx, msg);
                }

                if (self.active_tool_interface) |tool| {
                    tool.drawOverlay(cr_ctx, self.view_scale, self.view_x, self.view_y);
                }

                if (self.engine.selection.rect) |sel| {
                    const r: f64 = @floatFromInt(sel.x);
                    const g: f64 = @floatFromInt(sel.y);
                    const w: f64 = @floatFromInt(sel.width);
                    const h: f64 = @floatFromInt(sel.height);

                    const sx = r * self.view_scale - self.view_x;
                    const sy = g * self.view_scale - self.view_y;
                    const sw = w * self.view_scale;
                    const sh = h * self.view_scale;

                    c.cairo_save(cr_ctx);

                    if (self.engine.selection.mode == .ellipse) {
                        var matrix: c.cairo_matrix_t = undefined;
                        c.cairo_get_matrix(cr_ctx, &matrix);

                        c.cairo_translate(cr_ctx, sx + sw / 2.0, sy + sh / 2.0);
                        c.cairo_scale(cr_ctx, sw / 2.0, sh / 2.0);
                        c.cairo_arc(cr_ctx, 0.0, 0.0, 1.0, 0.0, 2.0 * std.math.pi);

                        c.cairo_set_matrix(cr_ctx, &matrix);
                    } else if (self.engine.selection.mode == .lasso) {
                        if (self.engine.selection.points.items.len > 0) {
                            const first = self.engine.selection.points.items[0];
                            const fx = first.x * self.view_scale - self.view_x;
                            const fy = first.y * self.view_scale - self.view_y;
                            c.cairo_move_to(cr_ctx, fx, fy);

                            for (self.engine.selection.points.items[1..]) |p| {
                                const px = p.x * self.view_scale - self.view_x;
                                const py = p.y * self.view_scale - self.view_y;
                                c.cairo_line_to(cr_ctx, px, py);
                            }
                            c.cairo_close_path(cr_ctx);
                        }
                    } else {
                        c.cairo_rectangle(cr_ctx, sx, sy, sw, sh);
                    }

                    if (self.is_dragging_interaction) {
                        drawDimensions(cr_ctx, sx + sw, sy + sh, sel.width, sel.height);
                    }

                    const dash: [2]f64 = .{ 4.0, 4.0 };
                    c.cairo_set_dash(cr_ctx, &dash, 2, self.ants_offset);
                    c.cairo_set_source_rgb(cr_ctx, 1.0, 1.0, 1.0); // White
                    c.cairo_set_line_width(cr_ctx, 1.0);
                    c.cairo_stroke_preserve(cr_ctx);

                    c.cairo_set_source_rgb(cr_ctx, 0.0, 0.0, 0.0); // Black contrast
                    c.cairo_set_dash(cr_ctx, &dash, 2, self.ants_offset + 4.0); // Offset
                    c.cairo_stroke(cr_ctx);
                    c.cairo_restore(cr_ctx);

                    if (self.ants_timer_id == 0) {
                        self.ants_timer_id = c.g_timeout_add(100, @ptrCast(&ants_timer_callback), self);
                    }
                } else {
                    if (self.ants_timer_id != 0) {
                        _ = c.g_source_remove(self.ants_timer_id);
                        self.ants_timer_id = 0;
                    }
                }

                if (self.active_tool_interface != null and self.engine.preview_mode == .transform) {
                    if (self.engine.preview_bbox) |bbox| {
                        const r: f64 = @floatFromInt(bbox.x);
                        const g: f64 = @floatFromInt(bbox.y);
                        const w: f64 = @floatFromInt(bbox.width);
                        const h: f64 = @floatFromInt(bbox.height);

                        const sx = r * self.view_scale - self.view_x;
                        const sy = g * self.view_scale - self.view_y;
                        const sw = w * self.view_scale;
                        const sh = h * self.view_scale;

                        c.cairo_save(cr_ctx);
                        c.cairo_rectangle(cr_ctx, sx, sy, sw, sh);

                        const dash = [_]f64{ 4.0, 4.0 };
                        c.cairo_set_dash(cr_ctx, &dash, 2, 0.0);
                        c.cairo_set_line_width(cr_ctx, 1.0);

                        c.cairo_set_source_rgb(cr_ctx, 1.0, 1.0, 1.0); // White
                        c.cairo_stroke_preserve(cr_ctx);

                        c.cairo_set_source_rgb(cr_ctx, 0.0, 0.0, 0.0); // Black
                        c.cairo_set_dash(cr_ctx, &dash, 2, 4.0); // Offset
                        c.cairo_stroke(cr_ctx);

                        c.cairo_restore(cr_ctx);

                        drawDimensions(cr_ctx, sx + sw, sy + sh, bbox.width, bbox.height);
                    }
                }

                if (self.engine.preview_shape) |shape| {
                    const sx = @as(f64, @floatFromInt(shape.x)) * self.view_scale - self.view_x;
                    const sy = @as(f64, @floatFromInt(shape.y)) * self.view_scale - self.view_y;
                    const sw = @as(f64, @floatFromInt(shape.width)) * self.view_scale;
                    const sh = @as(f64, @floatFromInt(shape.height)) * self.view_scale;

                    c.cairo_save(cr_ctx);
                    if (shape.type == .rectangle) {
                        c.cairo_rectangle(cr_ctx, sx, sy, sw, sh);
                    } else if (shape.type == .ellipse) {
                         c.cairo_save(cr_ctx);
                         c.cairo_translate(cr_ctx, sx + sw / 2.0, sy + sh / 2.0);
                         c.cairo_scale(cr_ctx, sw / 2.0, sh / 2.0);
                         c.cairo_arc(cr_ctx, 0.0, 0.0, 1.0, 0.0, 2.0 * std.math.pi);

                         const fg = self.engine.fg_color;
                         c.cairo_set_source_rgba(cr_ctx, @as(f64, @floatFromInt(fg[0])) / 255.0, @as(f64, @floatFromInt(fg[1])) / 255.0, @as(f64, @floatFromInt(fg[2])) / 255.0, @as(f64, @floatFromInt(fg[3])) / 255.0);

                         if (shape.filled) {
                             c.cairo_fill(cr_ctx);
                         } else {
                             c.cairo_restore(cr_ctx);
                             // const thickness = @as(f64, @floatFromInt(shape.thickness)) * self.view_scale;
                             c.cairo_set_line_width(cr_ctx, 2.0 / ((sw+sh)/2.0));
                             c.cairo_stroke(cr_ctx);
                         }
                         if (shape.filled) c.cairo_restore(cr_ctx);
                    } else if (shape.type == .rounded_rectangle) {
                        const radius: f64 = @floatFromInt(shape.radius);
                        const sr = radius * self.view_scale;
                        const degrees = std.math.pi / 180.0;
                        c.cairo_new_sub_path(cr_ctx);
                        c.cairo_arc(cr_ctx, sx + sw - sr, sy + sr, sr, -90.0 * degrees, 0.0 * degrees);
                        c.cairo_arc(cr_ctx, sx + sw - sr, sy + sh - sr, sr, 0.0 * degrees, 90.0 * degrees);
                        c.cairo_arc(cr_ctx, sx + sr, sy + sh - sr, sr, 90.0 * degrees, 180.0 * degrees);
                        c.cairo_arc(cr_ctx, sx + sr, sy + sr, sr, 180.0 * degrees, 270.0 * degrees);
                        c.cairo_close_path(cr_ctx);
                    } else if (shape.type == .line) {
                         const r2: f64 = @floatFromInt(shape.x2);
                         const g2: f64 = @floatFromInt(shape.y2);
                         const sx2 = r2 * self.view_scale - self.view_x;
                         const sy2 = g2 * self.view_scale - self.view_y;

                         c.cairo_move_to(cr_ctx, sx, sy);
                         c.cairo_line_to(cr_ctx, sx2, sy2);

                         c.cairo_set_source_rgb(cr_ctx, 0.0, 0.0, 0.0);
                         c.cairo_set_line_width(cr_ctx, 1.0);
                         c.cairo_stroke_preserve(cr_ctx);

                         c.cairo_set_source_rgb(cr_ctx, 1.0, 1.0, 1.0);
                         var dash_l: [2]f64 = .{ 4.0, 4.0 };
                         c.cairo_set_dash(cr_ctx, &dash_l, 2, 4.0);
                         c.cairo_stroke(cr_ctx);

                         c.cairo_arc(cr_ctx, sx, sy, 3.0, 0.0, 2.0 * std.math.pi);
                         c.cairo_fill(cr_ctx);
                         c.cairo_arc(cr_ctx, sx2, sy2, 3.0, 0.0, 2.0 * std.math.pi);
                         c.cairo_stroke(cr_ctx);
                    } else if (shape.type == .curve) {
                        const x1: f64 = @floatFromInt(shape.x);
                        const y1: f64 = @floatFromInt(shape.y);
                        const x2: f64 = @floatFromInt(shape.x2);
                        const y2: f64 = @floatFromInt(shape.y2);
                        const cx1: f64 = @floatFromInt(shape.cx1);
                        const cy1: f64 = @floatFromInt(shape.cy1);
                        const cx2: f64 = @floatFromInt(shape.cx2);
                        const cy2: f64 = @floatFromInt(shape.cy2);

                        const sx1 = x1 * self.view_scale - self.view_x;
                        const sy1 = y1 * self.view_scale - self.view_y;
                        const sx2 = x2 * self.view_scale - self.view_x;
                        const sy2 = y2 * self.view_scale - self.view_y;
                        const scx1 = cx1 * self.view_scale - self.view_x;
                        const scy1 = cy1 * self.view_scale - self.view_y;
                        const scx2 = cx2 * self.view_scale - self.view_x;
                        const scy2 = cy2 * self.view_scale - self.view_y;

                        c.cairo_move_to(cr_ctx, sx1, sy1);
                        c.cairo_curve_to(cr_ctx, scx1, scy1, scx2, scy2, sx2, sy2);

                        const fg = self.engine.fg_color;
                        c.cairo_set_source_rgba(cr_ctx, @as(f64, @floatFromInt(fg[0])) / 255.0, @as(f64, @floatFromInt(fg[1])) / 255.0, @as(f64, @floatFromInt(fg[2])) / 255.0, @as(f64, @floatFromInt(fg[3])) / 255.0);
                        c.cairo_set_line_width(cr_ctx, 1.0);
                        c.cairo_stroke(cr_ctx);

                        c.cairo_set_source_rgb(cr_ctx, 0.5, 0.5, 0.5);
                        c.cairo_set_line_width(cr_ctx, 0.5);
                        var dash_c: [2]f64 = .{ 2.0, 2.0 };
                        c.cairo_set_dash(cr_ctx, &dash_c, 2, 0.0);

                        c.cairo_move_to(cr_ctx, sx1, sy1);
                        c.cairo_line_to(cr_ctx, scx1, scy1);
                        c.cairo_stroke(cr_ctx);

                        c.cairo_move_to(cr_ctx, sx2, sy2);
                        c.cairo_line_to(cr_ctx, scx2, scy2);
                        c.cairo_stroke(cr_ctx);

                        c.cairo_set_dash(cr_ctx, &dash_c, 0, 0.0);
                        c.cairo_arc(cr_ctx, scx1, scy1, 3.0, 0.0, 2.0 * std.math.pi);
                        c.cairo_fill(cr_ctx);
                        c.cairo_arc(cr_ctx, scx2, scy2, 3.0, 0.0, 2.0 * std.math.pi);
                        c.cairo_fill(cr_ctx);
                    } else if (shape.type == .polygon) {
                        if (shape.points) |pts| {
                            if (pts.len > 0) {
                                const first = pts[0];
                                const fpx = first.x * self.view_scale - self.view_x;
                                const fpy = first.y * self.view_scale - self.view_y;
                                c.cairo_move_to(cr_ctx, fpx, fpy);

                                var i: usize = 1;
                                while (i < pts.len) : (i += 1) {
                                    const p = pts[i];
                                    const px = p.x * self.view_scale - self.view_x;
                                    const py = p.y * self.view_scale - self.view_y;
                                    c.cairo_line_to(cr_ctx, px, py);
                                }
                            }
                        }
                    }

                    if (shape.type == .rectangle or shape.type == .rounded_rectangle or shape.type == .polygon) {
                         const fg = self.engine.fg_color;
                         c.cairo_set_source_rgba(cr_ctx, @as(f64, @floatFromInt(fg[0])) / 255.0, @as(f64, @floatFromInt(fg[1])) / 255.0, @as(f64, @floatFromInt(fg[2])) / 255.0, @as(f64, @floatFromInt(fg[3])) / 255.0);

                         if (shape.filled) {
                             c.cairo_close_path(cr_ctx);
                             c.cairo_fill(cr_ctx);
                         } else {
                             const thickness = @as(f64, @floatFromInt(shape.thickness)) * self.view_scale;
                             c.cairo_set_line_width(cr_ctx, thickness);
                             c.cairo_stroke(cr_ctx);
                         }
                    }

                    if (self.is_dragging_interaction) {
                        drawDimensions(cr_ctx, sx + sw, sy + sh, shape.width, shape.height);
                    }

                    if (shape.type != .ellipse) c.cairo_restore(cr_ctx);
                }
            }
        }
    }

    fn motion_func(
        controller: *c.GtkEventControllerMotion,
        x: f64,
        y: f64,
        user_data: ?*anyopaque,
    ) callconv(.c) void {
        _ = controller;
        const self: *Canvas = @ptrCast(@alignCast(user_data));
        self.mouse_x = x;
        self.mouse_y = y;

        if (self.active_tool_interface) |tool| {
            const c_x = (self.view_x + x) / self.view_scale;
            const c_y = (self.view_y + y) / self.view_scale;
            tool.motion(self.engine, c_x, c_y);
            self.queueDraw();
        }
    }

    fn key_pressed_func(
        controller: *c.GtkEventControllerKey,
        keyval: c_uint,
        keycode: c_uint,
        state: c.GdkModifierType,
        user_data: ?*anyopaque,
    ) callconv(.c) c.gboolean {
        _ = controller;
        _ = keycode;
        _ = state;
        const self: *Canvas = @ptrCast(@alignCast(user_data));

        const step = 20.0;
        switch (keyval) {
            0xff51 => { // Left
                self.view_x -= step;
                self.canvas_dirty = true;
                self.queueDraw();
                return 1;
            },
            0xff52 => { // Up
                self.view_y -= step;
                self.canvas_dirty = true;
                self.queueDraw();
                return 1;
            },
            0xff53 => { // Right
                self.view_x += step;
                self.canvas_dirty = true;
                self.queueDraw();
                return 1;
            },
            0xff54 => { // Down
                self.view_y += step;
                self.canvas_dirty = true;
                self.queueDraw();
                return 1;
            },
            else => return 0,
        }
    }

    fn zoom_begin(
        controller: *c.GtkGestureZoom,
        sequence: ?*c.GdkEventSequence,
        user_data: ?*anyopaque,
    ) callconv(.c) void {
        _ = sequence;
        const self: *Canvas = @ptrCast(@alignCast(user_data));
        self.zoom_base_scale = self.view_scale;
        self.zoom_base_view_x = self.view_x;
        self.zoom_base_view_y = self.view_y;

        var cx: f64 = 0;
        var cy: f64 = 0;
        _ = c.gtk_gesture_get_bounding_box_center(@ptrCast(controller), &cx, &cy);
        self.zoom_base_cx = cx;
        self.zoom_base_cy = cy;
    }

    fn zoom_update(
        gesture: *c.GtkGesture,
        sequence: ?*c.GdkEventSequence,
        user_data: ?*anyopaque,
    ) callconv(.c) void {
        _ = sequence;
        const self: *Canvas = @ptrCast(@alignCast(user_data));
        const scale = c.gtk_gesture_zoom_get_scale_delta(@ptrCast(gesture));

        var cx: f64 = 0;
        var cy: f64 = 0;
        _ = c.gtk_gesture_get_bounding_box_center(gesture, &cx, &cy);

        const res = CanvasUtils.calculateZoom(self.zoom_base_scale, self.zoom_base_view_x, self.zoom_base_view_y, self.zoom_base_cx, self.zoom_base_cy, scale);

        if (res.scale < 0.1 or res.scale > 50.0) return;

        self.view_scale = res.scale;
        self.view_x = res.view_x - (cx - self.zoom_base_cx);
        self.view_y = res.view_y - (cy - self.zoom_base_cy);
        self.canvas_dirty = true;

        var buf: [32]u8 = undefined;
        const pct: i32 = @intFromFloat(self.view_scale * 100.0);
        const txt = std.fmt.bufPrint(&buf, "Zoom: {d}%", .{pct}) catch "Zoom";
        self.showOSD(txt);

        self.queueDraw();
    }

    fn scroll_func(
        controller: *c.GtkEventControllerScroll,
        dx: f64,
        dy: f64,
        user_data: ?*anyopaque,
    ) callconv(.c) c.gboolean {
        const self: *Canvas = @ptrCast(@alignCast(user_data));
        const state = c.gtk_event_controller_get_current_event_state(@ptrCast(controller));
        const is_ctrl = (state & c.GDK_CONTROL_MASK) != 0;

        if (is_ctrl) {
            const zoom_factor: f64 = if (dy > 0) 0.9 else 1.1;
            const res = CanvasUtils.calculateZoom(self.view_scale, self.view_x, self.view_y, self.mouse_x, self.mouse_y, zoom_factor);

            if (res.scale < 0.1 or res.scale > 50.0) return 0;

            self.view_scale = res.scale;
            self.view_x = res.view_x;
            self.view_y = res.view_y;
            self.canvas_dirty = true;

            var buf: [32]u8 = undefined;
            const pct: i32 = @intFromFloat(self.view_scale * 100.0);
            const txt = std.fmt.bufPrint(&buf, "Zoom: {d}%", .{pct}) catch "Zoom";
            self.showOSD(txt);
        } else {
            const unit = c.gtk_event_controller_scroll_get_unit(controller);
            const speed: f64 = if (unit == c.GDK_SCROLL_UNIT_WHEEL) 20.0 else 1.0;

            self.view_x += dx * speed;
            self.view_y += dy * speed;
            self.canvas_dirty = true;
        }

        self.queueDraw();
        return 1;
    }

    fn drag_begin(
        gesture: ?*c.GtkGestureDrag,
        x: f64,
        y: f64,
        user_data: ?*anyopaque,
    ) callconv(.c) void {
        const self: *Canvas = @ptrCast(@alignCast(user_data));
        self.prev_x = x;
        self.prev_y = y;
        self.is_dragging_interaction = true;

        _ = c.gtk_widget_grab_focus(self.drawing_area);

        var button: c_uint = 0;
        if (gesture) |g| {
            button = c.gtk_gesture_single_get_current_button(@ptrCast(g));
        }
        self.drag_button = button;

        if (self.active_tool_interface) |tool| {
            const state = c.gtk_event_controller_get_current_event_state(@ptrCast(gesture));
            const c_x = (self.view_x + x) / self.view_scale;
            const c_y = (self.view_y + y) / self.view_scale;
            tool.start(self.engine, c_x, c_y, button, state);
            self.canvas_dirty = true;
            self.queueDraw();
        }
    }

    fn drag_update(
        gesture: ?*c.GtkGestureDrag,
        offset_x: f64,
        offset_y: f64,
        user_data: ?*anyopaque,
    ) callconv(.c) void {
        const self: *Canvas = @ptrCast(@alignCast(user_data));

        const button = c.gtk_gesture_single_get_current_button(@ptrCast(gesture));

        var start_sx: f64 = 0;
        var start_sy: f64 = 0;
        _ = c.gtk_gesture_drag_get_start_point(gesture, &start_sx, &start_sy);

        const current_x = start_sx + offset_x;
        const current_y = start_sy + offset_y;

        if (button == 2) {
            const dx = current_x - self.prev_x;
            const dy = current_y - self.prev_y;

            self.view_x -= dx;
            self.view_y -= dy;
            self.canvas_dirty = true;
            self.queueDraw();
        } else if (self.active_tool_interface) |tool| {
            const state = c.gtk_event_controller_get_current_event_state(@ptrCast(gesture));
            const c_x = (self.view_x + current_x) / self.view_scale;
            const c_y = (self.view_y + current_y) / self.view_scale;
            tool.update(self.engine, c_x, c_y, state);
            self.canvas_dirty = true;
            self.queueDraw();
        }

        self.prev_x = current_x;
        self.prev_y = current_y;
    }

    fn drag_end(
        gesture: ?*c.GtkGestureDrag,
        offset_x: f64,
        offset_y: f64,
        user_data: ?*anyopaque,
    ) callconv(.c) void {
        const self: *Canvas = @ptrCast(@alignCast(user_data));
        self.is_dragging_interaction = false;

        if (self.active_tool_interface) |tool| {
            const state = c.gtk_event_controller_get_current_event_state(@ptrCast(gesture));
            var start_sx: f64 = 0;
            var start_sy: f64 = 0;
            _ = c.gtk_gesture_drag_get_start_point(gesture, &start_sx, &start_sy);
            const current_x = start_sx + offset_x;
            const current_y = start_sy + offset_y;
            const c_x = (self.view_x + current_x) / self.view_scale;
            const c_y = (self.view_y + current_y) / self.view_scale;

            tool.end(self.engine, c_x, c_y, state);
            self.callbacks.refresh_undo_ui();
            self.canvas_dirty = true;
            self.queueDraw();
        }
    }
};
