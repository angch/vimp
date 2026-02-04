const std = @import("std");

const c = @import("c.zig").c;
const Engine = @import("engine.zig").Engine;
const CanvasUtils = @import("canvas_utils.zig");
const RecentManager = @import("recent.zig").RecentManager;
const RecentColorsManager = @import("recent_colors.zig").RecentColorsManager;
const ImportDialogs = @import("widgets/import_dialogs.zig");
const TextDialog = @import("widgets/text_dialog.zig");
const FileChooser = @import("widgets/file_chooser.zig");
const OpenLocationDialog = @import("widgets/open_location_dialog.zig");
const CanvasDialog = @import("widgets/canvas_dialog.zig");
const FilterDialog = @import("widgets/filter_dialog.zig");
const FullscreenPreview = @import("widgets/fullscreen_preview.zig");
const ThumbnailWindow = @import("widgets/thumbnail_window.zig");
const CommandPalette = @import("widgets/command_palette.zig");
const ColorPalette = @import("widgets/color_palette.zig").ColorPalette;
const RawLoader = @import("raw_loader.zig").RawLoader;
const ToolOptionsPanel = @import("widgets/tool_options_panel.zig").ToolOptionsPanel;
const Tool = @import("tools.zig").Tool;
const Assets = @import("assets.zig");

const ToolEntry = struct {
    tool: Tool,
    icon_data: ?[]const u8 = null,
    icon_name: ?[:0]const u8 = null,
    tooltip: [:0]const u8,
};

// Tool Group Active States
var active_selection_tool: Tool = .rect_select;
var active_shape_tool: Tool = .rect_shape;
var active_paint_tool: Tool = .brush;
var active_line_tool: Tool = .line;

var engine: Engine = .{};
var recent_manager: RecentManager = undefined;
var recent_colors_manager: RecentColorsManager = undefined;
var surface: ?*c.cairo_surface_t = null;
var prev_x: f64 = 0;
var prev_y: f64 = 0;
var drag_button: c_uint = 0;
var mouse_x: f64 = 0;
var mouse_y: f64 = 0;
var current_tool: Tool = .brush;

var ants_offset: f64 = 0.0;
var ants_timer_id: c_uint = 0;
var autosave_timer_id: c_uint = 0;

var thumbnail_ctx: ThumbnailWindow.ThumbnailContext = undefined;

var layers_list_box: ?*c.GtkWidget = null;
var recent_list_box: ?*c.GtkWidget = null;
var undo_list_box: ?*c.GtkWidget = null;
var drawing_area: ?*c.GtkWidget = null;
var apply_preview_btn: ?*c.GtkWidget = null;
var discard_preview_btn: ?*c.GtkWidget = null;

var tool_options_panel: ?*ToolOptionsPanel = null;
var transform_action_bar: ?*c.GtkWidget = null;
var main_stack: ?*c.GtkWidget = null;
var toast_overlay: ?*c.AdwToastOverlay = null;
var color_btn: ?*c.GtkWidget = null;

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

fn populate_recent_colors(chooser: *c.GtkColorChooser) void {
    if (recent_colors_manager.colors.items.len > 0) {
        c.gtk_color_chooser_add_palette(
            chooser,
            c.GTK_ORIENTATION_HORIZONTAL,
            5, // colors per line
            @intCast(recent_colors_manager.colors.items.len),
            recent_colors_manager.colors.items.ptr,
        );
    }
}

fn create_color_button() *c.GtkWidget {
    const btn = c.gtk_color_button_new();
    c.gtk_widget_set_valign(btn, c.GTK_ALIGN_START);
    c.gtk_widget_set_halign(btn, c.GTK_ALIGN_CENTER);

    _ = c.g_signal_connect_data(btn, "color-set", @ptrCast(&color_changed), null, null, 0);

    populate_recent_colors(@ptrCast(btn));
    return btn;
}

fn rebuild_recent_colors_ui_callback(_: ?*anyopaque) callconv(std.builtin.CallingConvention.c) c.gboolean {
    if (color_btn == null or tool_options_panel == null) return 0;

    const parent = c.gtk_widget_get_parent(color_btn.?);
    if (parent == null) return 0;

    c.gtk_box_remove(@ptrCast(parent), color_btn.?);

    // Recreate button using helper.
    // Note: We rebuild the widget because GtkColorChooser doesn't support clearing/resetting the palette
    // once added. This ensures the "Recent" palette is always up-to-date with the latest selection.
    color_btn = create_color_button();

    // Restore color from engine
    const fg = engine.fg_color;
    const rgba = c.GdkRGBA{
        .red = @as(f32, @floatFromInt(fg[0])) / 255.0,
        .green = @as(f32, @floatFromInt(fg[1])) / 255.0,
        .blue = @as(f32, @floatFromInt(fg[2])) / 255.0,
        .alpha = @as(f32, @floatFromInt(fg[3])) / 255.0,
    };
    c.gtk_color_chooser_set_rgba(@ptrCast(color_btn.?), &rgba);

    c.gtk_box_prepend(@ptrCast(parent), color_btn.?);

    // Restore focus to the new button to maintain keyboard navigation
    _ = c.gtk_widget_grab_focus(color_btn.?);

    return 0; // G_SOURCE_REMOVE
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

    recent_colors_manager.add(rgba) catch {};

    _ = c.g_idle_add(@ptrCast(&rebuild_recent_colors_ui_callback), null);
}

fn on_edit_colors_response(
    dialog: *c.GtkDialog,
    response_id: c_int,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    _ = user_data;
    if (response_id == c.GTK_RESPONSE_OK) {
        var rgba: c.GdkRGBA = undefined;
        c.gtk_color_chooser_get_rgba(@ptrCast(dialog), &rgba);

        const r: u8 = @intFromFloat(rgba.red * 255.0);
        const g: u8 = @intFromFloat(rgba.green * 255.0);
        const b: u8 = @intFromFloat(rgba.blue * 255.0);
        const a: u8 = @intFromFloat(rgba.alpha * 255.0);

        engine.setFgColor(r, g, b, a);
        recent_colors_manager.add(rgba) catch {};
        _ = c.g_idle_add(@ptrCast(&rebuild_recent_colors_ui_callback), null);
    }
    c.gtk_window_destroy(@ptrCast(dialog));
}

fn on_edit_colors_clicked(
    _: *c.GtkButton,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    const parent: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    const dialog = c.gtk_color_chooser_dialog_new("Edit Colors", parent);
    populate_recent_colors(@ptrCast(dialog));
    c.gtk_color_chooser_set_use_alpha(@ptrCast(dialog), 1);

    const fg = engine.fg_color;
    const rgba = c.GdkRGBA{
        .red = @as(f32, @floatFromInt(fg[0])) / 255.0,
        .green = @as(f32, @floatFromInt(fg[1])) / 255.0,
        .blue = @as(f32, @floatFromInt(fg[2])) / 255.0,
        .alpha = @as(f32, @floatFromInt(fg[3])) / 255.0,
    };
    c.gtk_color_chooser_set_rgba(@ptrCast(dialog), &rgba);

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&on_edit_colors_response), null, null, 0);
    c.gtk_window_present(@ptrCast(dialog));
}


fn transform_apply_clicked(_: *c.GtkButton, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.applyTransform() catch |err| {
        show_toast("Apply transform failed: {}", .{err});
    };
    if (tool_options_panel) |p| p.resetTransformUI();

    canvas_dirty = true;
    queue_draw();
    refresh_undo_ui();
}

fn transform_cancel_clicked(_: *c.GtkButton, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.cancelPreview();
    if (tool_options_panel) |p| p.resetTransformUI();

    canvas_dirty = true;
    queue_draw();
}

fn update_color_btn_visual() void {
    if (color_btn) |btn| {
        const fg = engine.fg_color;
        const rgba = c.GdkRGBA{
            .red = @as(f32, @floatFromInt(fg[0])) / 255.0,
            .green = @as(f32, @floatFromInt(fg[1])) / 255.0,
            .blue = @as(f32, @floatFromInt(fg[2])) / 255.0,
            .alpha = @as(f32, @floatFromInt(fg[3])) / 255.0,
        };
        c.gtk_color_chooser_set_rgba(@ptrCast(btn), &rgba);
    }
}


fn tool_toggled(
    button: *c.GtkToggleButton,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    if (c.gtk_toggle_button_get_active(button) == 1) {
        const tool_ptr = @as(*Tool, @ptrCast(@alignCast(user_data)));
        current_tool = tool_ptr.*;
        std.debug.print("Tool switched to: {}\n", .{current_tool});

        const is_transform = (current_tool == .unified_transform);
        if (tool_options_panel) |p| p.update(current_tool);
        if (transform_action_bar) |b| c.gtk_widget_set_visible(b, if (is_transform) 1 else 0);

        switch (current_tool) {
            .brush => {
                engine.setMode(.paint);
                engine.setBrushType(.circle);
                osd_show("Brush");
            },
            .pencil => {
                engine.setMode(.paint);
                engine.setBrushType(.square);
                osd_show("Pencil");
            },
            .airbrush => {
                engine.setMode(.airbrush);
                engine.setBrushType(.circle);
                osd_show("Airbrush");
            },
            .eraser => {
                engine.setMode(.erase);
                // Eraser shape? Usually square or round. Let's default to circle for now or keep previous behavior.
                // Previous behavior was square (default).
                // Let's make eraser square for consistency with typical pixel erasers, or circle.
                // Let's stick to square for eraser for now as it was default.
                engine.setBrushType(.square);
                osd_show("Eraser");
            },
            .bucket_fill => {
                engine.setMode(.fill);
                osd_show("Bucket Fill");
            },
            .rect_select => {
                engine.setSelectionMode(.rectangle);
                osd_show("Rectangle Select");
            },
            .ellipse_select => {
                engine.setSelectionMode(.ellipse);
                osd_show("Ellipse Select");
            },
            .rect_shape => {
                osd_show("Rectangle Tool");
            },
            .ellipse_shape => {
                osd_show("Ellipse Tool");
            },
            .rounded_rect_shape => {
                osd_show("Rounded Rectangle Tool");
            },
            .unified_transform => {
                osd_show("Unified Transform");
            },
            .color_picker => {
                osd_show("Color Picker");
            },
            .gradient => {
                osd_show("Gradient Tool");
            },
            .line => {
                engine.setMode(.paint);
                engine.setBrushType(.circle);
                osd_show("Line Tool");
            },
            .curve => {
                engine.setMode(.paint);
                engine.setBrushType(.circle);
                osd_show("Curve Tool (Drag Line -> Bend 1 -> Bend 2)");
                curve_phase = 0;
            },
            .polygon => {
                engine.setMode(.paint);
                engine.setBrushType(.circle);
                osd_show("Polygon Tool (Click to add points, click start to close)");
                polygon_active = false;
                polygon_points.clearRetainingCapacity();
            },
            .lasso => {
                engine.setSelectionMode(.lasso);
                osd_show("Lasso Select");
                polygon_active = false;
                polygon_points.clearRetainingCapacity();
            },
            .text => {
                osd_show("Text Tool (Click to insert text)");
            },
        }
    }
}

fn show_toast(comptime fmt: []const u8, args: anytype) void {
    if (toast_overlay) |overlay| {
        const msg_z = std.fmt.allocPrintSentinel(std.heap.c_allocator, fmt, args, 0) catch return;
        defer std.heap.c_allocator.free(msg_z);

        const toast = c.adw_toast_new(msg_z.ptr);
        c.adw_toast_overlay_add_toast(overlay, toast);
    }
}

fn update_view_mode() void {
    if (main_stack) |stack| {
        if (engine.layers.items.len > 0) {
            c.gtk_stack_set_visible_child_name(@ptrCast(stack), "canvas");
        } else {
            c.gtk_stack_set_visible_child_name(@ptrCast(stack), "welcome");
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
var rect_shape_tool = Tool.rect_shape;
var ellipse_shape_tool = Tool.ellipse_shape;
var rounded_rect_shape_tool = Tool.rounded_rect_shape;
var unified_transform_tool = Tool.unified_transform;
var color_picker_tool = Tool.color_picker;
var gradient_tool = Tool.gradient;
var line_tool = Tool.line;
var curve_tool = Tool.curve;
var polygon_tool = Tool.polygon;
var lasso_tool = Tool.lasso;
var text_tool = Tool.text;

// Curve Tool State
const Point = struct { x: f64, y: f64 };
var curve_phase: c_int = 0;
var curve_p1: Point = .{ .x = 0, .y = 0 };
var curve_p2: Point = .{ .x = 0, .y = 0 };
var curve_p3: Point = .{ .x = 0, .y = 0 };
var curve_p4: Point = .{ .x = 0, .y = 0 };

// Polygon Tool State
var polygon_points: std.ArrayList(Engine.Point) = undefined;
var polygon_active: bool = false;

// Drag State
var is_dragging_interaction: bool = false;
var is_moving_selection: bool = false;

// View State
var view_scale: f64 = 1.0;
var view_x: f64 = 0.0;
var view_y: f64 = 0.0;

// Zoom Gesture State
var zoom_base_scale: f64 = 1.0;
var zoom_base_view_x: f64 = 0.0;
var zoom_base_view_y: f64 = 0.0;
var zoom_base_cx: f64 = 0.0;
var zoom_base_cy: f64 = 0.0;

const OsdState = struct {
    label: ?*c.GtkWidget = null,
    revealer: ?*c.GtkWidget = null,
    timeout_id: c_uint = 0,
};

var osd_state: OsdState = .{};
var canvas_dirty: bool = true;

fn ants_timer_callback(user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) c.gboolean {
    _ = user_data;
    ants_offset += 1.0;
    if (ants_offset >= 8.0) ants_offset -= 8.0;
    queue_draw();
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
    // Center text in box
    // Box center: x + rect_w/2, y + rect_h/2.
    // Text center: width/2, height/2? No, bearing.
    // Let's rely on simple padding from top-left of box.
    // Text origin is baseline.
    // y + pad + height of font? extents.height is tight bounds.
    // Let's use extents.height + pad.
    c.cairo_move_to(cr, x + pad, y + pad + extents.height);
    c.cairo_show_text(cr, txt.ptr);

    c.cairo_restore(cr);
}

fn draw_func(
    widget: [*c]c.GtkDrawingArea,
    cr: ?*c.cairo_t,
    width: c_int,
    height: c_int,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    _ = user_data;
    _ = widget;

    if (surface) |s| {
        const s_width = c.cairo_image_surface_get_width(s);
        const s_height = c.cairo_image_surface_get_height(s);
        if (s_width != width or s_height != height) {
            c.cairo_surface_destroy(s);
            surface = null;
            canvas_dirty = true;
        }
    }

    if (surface == null) {
        if (width > 0 and height > 0) {
            const s = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, width, height);
            if (c.cairo_surface_status(s) != c.CAIRO_STATUS_SUCCESS) {
                std.debug.print("Failed to create surface: {}\n", .{c.cairo_surface_status(s)});
                c.cairo_surface_destroy(s);
                return;
            }
            surface = s;
            canvas_dirty = true;
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

        if (engine.layers.items.len > 0 and canvas_dirty) {
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
            canvas_dirty = false;
        }
    }

    if (surface) |s| {
        if (cr) |cr_ctx| {
            if (engine.layers.items.len > 0) {
                c.cairo_set_source_surface(cr_ctx, s, 0, 0);
                c.cairo_paint(cr_ctx);

                // Draw Pixel Grid
                CanvasUtils.drawPixelGrid(cr_ctx, @floatFromInt(width), @floatFromInt(height), view_scale, view_x, view_y);
            } else {
                // Empty State
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
                } else if (engine.selection_mode == .lasso) {
                    if (engine.selection_points.items.len > 0) {
                        const first = engine.selection_points.items[0];
                        const fx = first.x * view_scale - view_x;
                        const fy = first.y * view_scale - view_y;
                        c.cairo_move_to(cr_ctx, fx, fy);

                        for (engine.selection_points.items[1..]) |p| {
                            const px = p.x * view_scale - view_x;
                            const py = p.y * view_scale - view_y;
                            c.cairo_line_to(cr_ctx, px, py);
                        }
                        c.cairo_close_path(cr_ctx);
                    }
                } else {
                    c.cairo_rectangle(cr_ctx, sx, sy, sw, sh);
                }

                if (is_dragging_interaction) {
                    drawDimensions(cr_ctx, sx + sw, sy + sh, sel.width, sel.height);
                }

                // Marching ants
                const dash: [2]f64 = .{ 4.0, 4.0 };
                c.cairo_set_dash(cr_ctx, &dash, 2, ants_offset);
                c.cairo_set_source_rgb(cr_ctx, 1.0, 1.0, 1.0); // White
                c.cairo_set_line_width(cr_ctx, 1.0);
                c.cairo_stroke_preserve(cr_ctx);

                c.cairo_set_source_rgb(cr_ctx, 0.0, 0.0, 0.0); // Black contrast
                c.cairo_set_dash(cr_ctx, &dash, 2, ants_offset + 4.0); // Offset
                c.cairo_stroke(cr_ctx);
                c.cairo_restore(cr_ctx);

                // Start animation if not running
                if (ants_timer_id == 0) {
                    ants_timer_id = c.g_timeout_add(100, @ptrCast(&ants_timer_callback), null);
                }
            } else {
                // Stop animation if running
                if (ants_timer_id != 0) {
                    _ = c.g_source_remove(ants_timer_id);
                    ants_timer_id = 0;
                }
            }

            // Draw Transform Preview HUD
            if (current_tool == .unified_transform and engine.preview_mode == .transform) {
                if (engine.preview_bbox) |bbox| {
                    const r: f64 = @floatFromInt(bbox.x);
                    const g: f64 = @floatFromInt(bbox.y);
                    const w: f64 = @floatFromInt(bbox.width);
                    const h: f64 = @floatFromInt(bbox.height);

                    const sx = r * view_scale - view_x;
                    const sy = g * view_scale - view_y;
                    const sw = w * view_scale;
                    const sh = h * view_scale;

                    c.cairo_save(cr_ctx);
                    c.cairo_rectangle(cr_ctx, sx, sy, sw, sh);

                    const dash = [_]f64{ 4.0, 4.0 };
                    c.cairo_set_dash(cr_ctx, &dash, 2, 0.0);
                    c.cairo_set_line_width(cr_ctx, 1.0);

                    // Contrast stroke (Black on White)
                    c.cairo_set_source_rgb(cr_ctx, 1.0, 1.0, 1.0); // White
                    c.cairo_stroke_preserve(cr_ctx);

                    c.cairo_set_source_rgb(cr_ctx, 0.0, 0.0, 0.0); // Black
                    c.cairo_set_dash(cr_ctx, &dash, 2, 4.0); // Offset
                    c.cairo_stroke(cr_ctx);

                    c.cairo_restore(cr_ctx);

                    drawDimensions(cr_ctx, sx + sw, sy + sh, bbox.width, bbox.height);
                }
            }

            // Draw Shape Preview
            if (engine.preview_shape) |shape| {
                if (shape.type == .rectangle) {
                    const r: f64 = @floatFromInt(shape.x);
                    const g: f64 = @floatFromInt(shape.y);
                    const w: f64 = @floatFromInt(shape.width);
                    const h: f64 = @floatFromInt(shape.height);

                    const sx = r * view_scale - view_x;
                    const sy = g * view_scale - view_y;
                    const sw = w * view_scale;
                    const sh = h * view_scale;

                    c.cairo_save(cr_ctx);
                    c.cairo_rectangle(cr_ctx, sx, sy, sw, sh);

                    const fg = engine.fg_color;
                    c.cairo_set_source_rgba(cr_ctx, @as(f64, @floatFromInt(fg[0])) / 255.0, @as(f64, @floatFromInt(fg[1])) / 255.0, @as(f64, @floatFromInt(fg[2])) / 255.0, @as(f64, @floatFromInt(fg[3])) / 255.0);

                    if (shape.filled) {
                        c.cairo_fill(cr_ctx);
                    } else {
                        const thickness = @as(f64, @floatFromInt(shape.thickness)) * view_scale;
                        c.cairo_set_line_width(cr_ctx, thickness);
                        c.cairo_stroke(cr_ctx);
                    }

                    if (is_dragging_interaction) {
                        drawDimensions(cr_ctx, sx + sw, sy + sh, shape.width, shape.height);
                    }

                    c.cairo_restore(cr_ctx);
                } else if (shape.type == .ellipse) {
                    const r: f64 = @floatFromInt(shape.x);
                    const g: f64 = @floatFromInt(shape.y);
                    const w: f64 = @floatFromInt(shape.width);
                    const h: f64 = @floatFromInt(shape.height);

                    const sx = r * view_scale - view_x;
                    const sy = g * view_scale - view_y;
                    const sw = w * view_scale;
                    const sh = h * view_scale;

                    c.cairo_save(cr_ctx);
                    c.cairo_translate(cr_ctx, sx + sw / 2.0, sy + sh / 2.0);
                    c.cairo_scale(cr_ctx, sw / 2.0, sh / 2.0);
                    c.cairo_arc(cr_ctx, 0.0, 0.0, 1.0, 0.0, 2.0 * std.math.pi);
                    c.cairo_restore(cr_ctx);

                    c.cairo_save(cr_ctx);
                    const fg = engine.fg_color;
                    c.cairo_set_source_rgba(cr_ctx, @as(f64, @floatFromInt(fg[0])) / 255.0, @as(f64, @floatFromInt(fg[1])) / 255.0, @as(f64, @floatFromInt(fg[2])) / 255.0, @as(f64, @floatFromInt(fg[3])) / 255.0);

                    if (shape.filled) {
                        c.cairo_fill(cr_ctx);
                    } else {
                        const thickness = @as(f64, @floatFromInt(shape.thickness)) * view_scale;
                        c.cairo_set_line_width(cr_ctx, thickness);
                        c.cairo_stroke(cr_ctx);
                    }

                    if (is_dragging_interaction) {
                        drawDimensions(cr_ctx, sx + sw, sy + sh, shape.width, shape.height);
                    }

                    c.cairo_restore(cr_ctx);
                } else if (shape.type == .rounded_rectangle) {
                    const r: f64 = @floatFromInt(shape.x);
                    const g: f64 = @floatFromInt(shape.y);
                    const w: f64 = @floatFromInt(shape.width);
                    const h: f64 = @floatFromInt(shape.height);
                    const radius: f64 = @floatFromInt(shape.radius);

                    const sx = r * view_scale - view_x;
                    const sy = g * view_scale - view_y;
                    const sw = w * view_scale;
                    const sh = h * view_scale;
                    const sr = radius * view_scale;

                    c.cairo_save(cr_ctx);

                    // Rounded rect path
                    const degrees = std.math.pi / 180.0;
                    c.cairo_new_sub_path(cr_ctx);
                    c.cairo_arc(cr_ctx, sx + sw - sr, sy + sr, sr, -90.0 * degrees, 0.0 * degrees);
                    c.cairo_arc(cr_ctx, sx + sw - sr, sy + sh - sr, sr, 0.0 * degrees, 90.0 * degrees);
                    c.cairo_arc(cr_ctx, sx + sr, sy + sh - sr, sr, 90.0 * degrees, 180.0 * degrees);
                    c.cairo_arc(cr_ctx, sx + sr, sy + sr, sr, 180.0 * degrees, 270.0 * degrees);
                    c.cairo_close_path(cr_ctx);

                    const fg = engine.fg_color;
                    c.cairo_set_source_rgba(cr_ctx, @as(f64, @floatFromInt(fg[0])) / 255.0, @as(f64, @floatFromInt(fg[1])) / 255.0, @as(f64, @floatFromInt(fg[2])) / 255.0, @as(f64, @floatFromInt(fg[3])) / 255.0);

                    if (shape.filled) {
                        c.cairo_fill(cr_ctx);
                    } else {
                        const thickness = @as(f64, @floatFromInt(shape.thickness)) * view_scale;
                        c.cairo_set_line_width(cr_ctx, thickness);
                        c.cairo_stroke(cr_ctx);
                    }

                    if (is_dragging_interaction) {
                        drawDimensions(cr_ctx, sx + sw, sy + sh, shape.width, shape.height);
                    }

                    c.cairo_restore(cr_ctx);
                } else if (shape.type == .line) {
                    const r: f64 = @floatFromInt(shape.x);
                    const g: f64 = @floatFromInt(shape.y);
                    const r2: f64 = @floatFromInt(shape.x2);
                    const g2: f64 = @floatFromInt(shape.y2);

                    const sx = r * view_scale - view_x;
                    const sy = g * view_scale - view_y;
                    const sx2 = r2 * view_scale - view_x;
                    const sy2 = g2 * view_scale - view_y;

                    c.cairo_save(cr_ctx);
                    c.cairo_move_to(cr_ctx, sx, sy);
                    c.cairo_line_to(cr_ctx, sx2, sy2);

                    c.cairo_set_source_rgb(cr_ctx, 0.0, 0.0, 0.0);
                    c.cairo_set_line_width(cr_ctx, 1.0);
                    c.cairo_stroke_preserve(cr_ctx);

                    c.cairo_set_source_rgb(cr_ctx, 1.0, 1.0, 1.0);
                    var dash: [2]f64 = .{ 4.0, 4.0 };
                    c.cairo_set_dash(cr_ctx, &dash, 2, 4.0);
                    c.cairo_stroke(cr_ctx);

                    // Endpoints
                    c.cairo_arc(cr_ctx, sx, sy, 3.0, 0.0, 2.0 * std.math.pi);
                    c.cairo_fill(cr_ctx);
                    c.cairo_arc(cr_ctx, sx2, sy2, 3.0, 0.0, 2.0 * std.math.pi);
                    c.cairo_stroke(cr_ctx);

                    c.cairo_restore(cr_ctx);
                } else if (shape.type == .curve) {
                    const x1: f64 = @floatFromInt(shape.x);
                    const y1: f64 = @floatFromInt(shape.y);
                    const x2: f64 = @floatFromInt(shape.x2);
                    const y2: f64 = @floatFromInt(shape.y2);
                    const cx1: f64 = @floatFromInt(shape.cx1);
                    const cy1: f64 = @floatFromInt(shape.cy1);
                    const cx2: f64 = @floatFromInt(shape.cx2);
                    const cy2: f64 = @floatFromInt(shape.cy2);

                    const sx1 = x1 * view_scale - view_x;
                    const sy1 = y1 * view_scale - view_y;
                    const sx2 = x2 * view_scale - view_x;
                    const sy2 = y2 * view_scale - view_y;
                    const scx1 = cx1 * view_scale - view_x;
                    const scy1 = cy1 * view_scale - view_y;
                    const scx2 = cx2 * view_scale - view_x;
                    const scy2 = cy2 * view_scale - view_y;

                    c.cairo_save(cr_ctx);

                    // Draw Curve
                    c.cairo_move_to(cr_ctx, sx1, sy1);
                    c.cairo_curve_to(cr_ctx, scx1, scy1, scx2, scy2, sx2, sy2);

                    const fg = engine.fg_color;
                    c.cairo_set_source_rgba(cr_ctx, @as(f64, @floatFromInt(fg[0])) / 255.0, @as(f64, @floatFromInt(fg[1])) / 255.0, @as(f64, @floatFromInt(fg[2])) / 255.0, @as(f64, @floatFromInt(fg[3])) / 255.0);
                    c.cairo_set_line_width(cr_ctx, 1.0);
                    c.cairo_stroke(cr_ctx);

                    // Draw Control Handles
                    c.cairo_set_source_rgb(cr_ctx, 0.5, 0.5, 0.5);
                    c.cairo_set_line_width(cr_ctx, 0.5);
                    var dash: [2]f64 = .{ 2.0, 2.0 };
                    c.cairo_set_dash(cr_ctx, &dash, 2, 0.0);

                    // P1 -> CP1
                    c.cairo_move_to(cr_ctx, sx1, sy1);
                    c.cairo_line_to(cr_ctx, scx1, scy1);
                    c.cairo_stroke(cr_ctx);

                    // P4 -> CP2
                    c.cairo_move_to(cr_ctx, sx2, sy2);
                    c.cairo_line_to(cr_ctx, scx2, scy2);
                    c.cairo_stroke(cr_ctx);

                    // Draw Control Points
                    c.cairo_set_dash(cr_ctx, &dash, 0, 0.0); // Reset dash
                    c.cairo_arc(cr_ctx, scx1, scy1, 3.0, 0.0, 2.0 * std.math.pi);
                    c.cairo_fill(cr_ctx);
                    c.cairo_arc(cr_ctx, scx2, scy2, 3.0, 0.0, 2.0 * std.math.pi);
                    c.cairo_fill(cr_ctx);

                    c.cairo_restore(cr_ctx);
                } else if (shape.type == .polygon) {
                    if (shape.points) |pts| {
                        if (pts.len > 0) {
                            c.cairo_save(cr_ctx);

                            const first = pts[0];
                            const sx = first.x * view_scale - view_x;
                            const sy = first.y * view_scale - view_y;
                            c.cairo_move_to(cr_ctx, sx, sy);

                            var i: usize = 1;
                            while (i < pts.len) : (i += 1) {
                                const p = pts[i];
                                const px = p.x * view_scale - view_x;
                                const py = p.y * view_scale - view_y;
                                c.cairo_line_to(cr_ctx, px, py);
                            }

                            const fg = engine.fg_color;
                            c.cairo_set_source_rgba(cr_ctx, @as(f64, @floatFromInt(fg[0])) / 255.0, @as(f64, @floatFromInt(fg[1])) / 255.0, @as(f64, @floatFromInt(fg[2])) / 255.0, @as(f64, @floatFromInt(fg[3])) / 255.0);

                            if (shape.filled) {
                                c.cairo_close_path(cr_ctx);
                                c.cairo_fill(cr_ctx);
                            } else {
                                const thickness = @as(f64, @floatFromInt(shape.thickness)) * view_scale;
                                c.cairo_set_line_width(cr_ctx, thickness);
                                c.cairo_stroke(cr_ctx);
                            }
                            c.cairo_restore(cr_ctx);
                        }
                    }
                }
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

    if (current_tool == .polygon and polygon_active) {
        // Update preview line from last point to cursor
        const wx = (view_x + x) / view_scale;
        const wy = (view_y + y) / view_scale;

        // We need to pass points + current cursor
        // But allocating a new list every motion is expensive?
        // ShapePreview needs a list.
        // I can temporarily append, set preview, remove.
        polygon_points.append(std.heap.c_allocator, Engine.Point{ .x = wx, .y = wy }) catch return;
        engine.setShapePreviewPolygon(polygon_points.items, engine.brush_size, false);
        _ = polygon_points.pop();

        queue_draw();
    }
}

fn zoom_begin(
    controller: *c.GtkGestureZoom,
    sequence: ?*c.GdkEventSequence,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    _ = sequence;
    _ = user_data;
    zoom_base_scale = view_scale;
    zoom_base_view_x = view_x;
    zoom_base_view_y = view_y;

    var cx: f64 = 0;
    var cy: f64 = 0;
    _ = c.gtk_gesture_get_bounding_box_center(@ptrCast(controller), &cx, &cy);
    zoom_base_cx = cx;
    zoom_base_cy = cy;
}

fn zoom_update(
    gesture: *c.GtkGesture,
    sequence: ?*c.GdkEventSequence,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    _ = sequence;
    _ = user_data;
    // Get current scale delta
    const scale = c.gtk_gesture_zoom_get_scale_delta(@ptrCast(gesture));

    // Get current bounding box center
    var cx: f64 = 0;
    var cy: f64 = 0;
    _ = c.gtk_gesture_get_bounding_box_center(gesture, &cx, &cy);

    // Calculate Zoom relative to INITIAL center (zoom_base_cx/cy)
    const res = CanvasUtils.calculateZoom(zoom_base_scale, zoom_base_view_x, zoom_base_view_y, zoom_base_cx, zoom_base_cy, scale);

    // Limit scale
    if (res.scale < 0.1 or res.scale > 50.0) return;

    // Apply Pan Delta: (curr_cx - start_cx)
    // view_x = calculated_view_x - pan_delta_x
    view_scale = res.scale;
    view_x = res.view_x - (cx - zoom_base_cx);
    view_y = res.view_y - (cy - zoom_base_cy);
    canvas_dirty = true;

    // OSD
    var buf: [32]u8 = undefined;
    const pct: i32 = @intFromFloat(view_scale * 100.0);
    const txt = std.fmt.bufPrint(&buf, "Zoom: {d}%", .{pct}) catch "Zoom";
    osd_show(txt);

    queue_draw();
}

fn scroll_func(
    controller: *c.GtkEventControllerScroll,
    dx: f64,
    dy: f64,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) c.gboolean {
    _ = user_data;
    // Check modifiers (Ctrl for Zoom)
    const state = c.gtk_event_controller_get_current_event_state(@ptrCast(controller));
    const is_ctrl = (state & c.GDK_CONTROL_MASK) != 0;

    if (is_ctrl) {
        // Zoom at mouse cursor
        // Zoom factor
        const zoom_factor: f64 = if (dy > 0) 0.9 else 1.1; // Scroll down = Zoom out

        const res = CanvasUtils.calculateZoom(view_scale, view_x, view_y, mouse_x, mouse_y, zoom_factor);

        // Limit scale
        if (res.scale < 0.1 or res.scale > 50.0) return 0;

        view_scale = res.scale;
        view_x = res.view_x;
        view_y = res.view_y;
        canvas_dirty = true;

        var buf: [32]u8 = undefined;
        const pct: i32 = @intFromFloat(view_scale * 100.0);
        const txt = std.fmt.bufPrint(&buf, "Zoom: {d}%", .{pct}) catch "Zoom";
        osd_show(txt);
    } else {
        // Pan
        // Scroll down (positive dy) -> Move View Down (increase ViewY) -> Content moves Up?
        // Standard Web/Doc: Scroll Down -> Content moves Up.
        // ViewY increases.
        // Speed factor
        const speed = 20.0;
        view_x += dx * speed;
        view_y += dy * speed;
        canvas_dirty = true;
    }

    queue_draw();

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
    is_dragging_interaction = true;

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
        drag_button = button;

        if (button == 1 or button == 3) {
            if (current_tool == .bucket_fill) {
                engine.beginTransaction();
                const c_x = (view_x + x) / view_scale;
                const c_y = (view_y + y) / view_scale;
                if (button == 3) {
                    engine.bucketFillWithColor(c_x, c_y, engine.bg_color) catch |err| {
                        show_toast("Bucket fill failed: {}", .{err});
                    };
                } else {
                    engine.bucketFill(c_x, c_y) catch |err| {
                        show_toast("Bucket fill failed: {}", .{err});
                    };
                }
                engine.commitTransaction();
                canvas_dirty = true;
                c.gtk_widget_queue_draw(widget);
            } else if (current_tool == .rect_select or current_tool == .ellipse_select) {
                if (button != 1) return;
                const c_x = (view_x + x) / view_scale;
                const c_y = (view_y + y) / view_scale;
                const ix: i32 = @intFromFloat(c_x);
                const iy: i32 = @intFromFloat(c_y);

                if (engine.selection != null and engine.isPointInSelection(ix, iy)) {
                    engine.beginMoveSelection(c_x, c_y) catch |err| {
                        show_toast("Failed to move selection: {}", .{err});
                        return;
                    };
                    is_moving_selection = true;
                } else {
                    engine.beginSelection();
                    engine.clearSelection();
                }
                c.gtk_widget_queue_draw(widget);
            } else if (current_tool == .lasso) {
                if (button != 1) return;
                const c_x = (view_x + x) / view_scale;
                const c_y = (view_y + y) / view_scale;
                const ix: i32 = @intFromFloat(c_x);
                const iy: i32 = @intFromFloat(c_y);

                if (engine.selection != null and engine.isPointInSelection(ix, iy)) {
                    engine.beginMoveSelection(c_x, c_y) catch |err| {
                        show_toast("Failed to move selection: {}", .{err});
                        return;
                    };
                    is_moving_selection = true;
                } else {
                    engine.beginSelection();
                    engine.clearSelection(); // Clear previous selection immediately
                    polygon_points.clearRetainingCapacity();
                    const wx = (view_x + x) / view_scale;
                    const wy = (view_y + y) / view_scale;
                    polygon_points.append(std.heap.c_allocator, Engine.Point{ .x = wx, .y = wy }) catch {};
                }
                c.gtk_widget_queue_draw(widget);
            } else if (current_tool == .color_picker) {
                if (button != 1) return;
                const c_x: i32 = @intFromFloat((view_x + x) / view_scale);
                const c_y: i32 = @intFromFloat((view_y + y) / view_scale);
                if (engine.pickColor(c_x, c_y)) |color| {
                    engine.setFgColor(color[0], color[1], color[2], color[3]);
                    if (color_btn) |btn| {
                        const rgba = c.GdkRGBA{
                            .red = @as(f32, @floatFromInt(color[0])) / 255.0,
                            .green = @as(f32, @floatFromInt(color[1])) / 255.0,
                            .blue = @as(f32, @floatFromInt(color[2])) / 255.0,
                            .alpha = @as(f32, @floatFromInt(color[3])) / 255.0,
                        };
                        c.gtk_color_chooser_set_rgba(@ptrCast(btn), &rgba);
                    }
                } else |_| {}
            } else if (current_tool == .rect_shape or current_tool == .ellipse_shape or current_tool == .rounded_rect_shape) {
                if (button != 1) return;
                // Do nothing at start, render preview during drag
            } else if (current_tool == .gradient) {
                if (button != 1) return;
                engine.beginTransaction();
            } else if (current_tool == .line) {
                // Do nothing at start, render preview during drag
            } else if (current_tool == .curve) {
                if (curve_phase == 0) {
                    curve_p1.x = (view_x + x) / view_scale;
                    curve_p1.y = (view_y + y) / view_scale;
                }
            } else if (current_tool == .polygon) {
                if (button != 1) return;
                const wx = (view_x + x) / view_scale;
                const wy = (view_y + y) / view_scale;

                if (!polygon_active) {
                    polygon_points.clearRetainingCapacity();
                    polygon_points.append(std.heap.c_allocator, Engine.Point{ .x = wx, .y = wy }) catch {};
                    polygon_active = true;
                } else {
                    // Check closure (screen distance < 10px)
                    if (polygon_points.items.len > 0) {
                        const first = polygon_points.items[0];
                        const sx = first.x * view_scale - view_x;
                        const sy = first.y * view_scale - view_y;
                        const dx = x - sx;
                        const dy = y - sy;
                        if (dx * dx + dy * dy < 100.0) {
                            // Close polygon
                            engine.beginTransaction();
                            // Default to outline for now, maybe add toggle later
                            engine.drawPolygon(polygon_points.items, engine.brush_size, false) catch |err| {
                                show_toast("Failed to draw polygon: {}", .{err});
                            };
                            engine.commitTransaction();
                            engine.clearShapePreview();
                            polygon_active = false;
                            polygon_points.clearRetainingCapacity();
                            refresh_undo_ui();
                            canvas_dirty = true;
                            c.gtk_widget_queue_draw(widget);
                            return;
                        }
                    }
                    polygon_points.append(std.heap.c_allocator, Engine.Point{ .x = wx, .y = wy }) catch {};
                }
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
        canvas_dirty = true;

        queue_draw();
    } else if (button == 1 or button == 3) {
        // Paint (Left or Right Mouse)
        if (current_tool == .bucket_fill) {
            // Bucket fill handled in drag_begin, do nothing on drag
            return;
        }

        const c_prev_x = (view_x + prev_x) / view_scale;
        const c_prev_y = (view_y + prev_y) / view_scale;
        const c_curr_x = (view_x + current_x) / view_scale;
        const c_curr_y = (view_y + current_y) / view_scale;

        if (current_tool == .color_picker) {
            const c_x: i32 = @intFromFloat(c_curr_x);
            const c_y: i32 = @intFromFloat(c_curr_y);
            if (engine.pickColor(c_x, c_y)) |color| {
                engine.setFgColor(color[0], color[1], color[2], color[3]);
                if (color_btn) |btn| {
                    const rgba = c.GdkRGBA{
                        .red = @as(f32, @floatFromInt(color[0])) / 255.0,
                        .green = @as(f32, @floatFromInt(color[1])) / 255.0,
                        .blue = @as(f32, @floatFromInt(color[2])) / 255.0,
                        .alpha = @as(f32, @floatFromInt(color[3])) / 255.0,
                    };
                    c.gtk_color_chooser_set_rgba(@ptrCast(btn), &rgba);
                }
            } else |_| {}
            prev_x = current_x;
            prev_y = current_y;
            return;
        }

        if (current_tool == .lasso) {
            if (is_moving_selection) {
                const dx = offset_x / view_scale;
                const dy = offset_y / view_scale;
                engine.updateMoveSelection(dx, dy);
                canvas_dirty = true;
            } else {
                polygon_points.append(std.heap.c_allocator, Engine.Point{ .x = c_curr_x, .y = c_curr_y }) catch {};
                engine.setShapePreviewPolygon(polygon_points.items, 1, false);
            }
            c.gtk_widget_queue_draw(widget);
            prev_x = current_x;
            prev_y = current_y;
            return;
        }

        if (current_tool == .curve) {
            if (curve_phase == 0) {
                // Dragging line endpoint
                curve_p4.x = c_curr_x;
                curve_p4.y = c_curr_y;
                // CP1, CP2 follow line for now
                curve_p2 = curve_p1;
                curve_p3 = curve_p4;
            } else if (curve_phase == 1) {
                // Dragging CP1
                curve_p2.x = c_curr_x;
                curve_p2.y = c_curr_y;
            } else if (curve_phase == 2) {
                // Dragging CP2
                curve_p3.x = c_curr_x;
                curve_p3.y = c_curr_y;
            }

            const sx: c_int = @intFromFloat(curve_p1.x);
            const sy: c_int = @intFromFloat(curve_p1.y);
            const ex: c_int = @intFromFloat(curve_p4.x);
            const ey: c_int = @intFromFloat(curve_p4.y);
            const cx1: c_int = @intFromFloat(curve_p2.x);
            const cy1: c_int = @intFromFloat(curve_p2.y);
            const cx2: c_int = @intFromFloat(curve_p3.x);
            const cy2: c_int = @intFromFloat(curve_p3.y);

            engine.setShapePreview(sx, sy, 0, 0, 1, false);
            if (engine.preview_shape) |*s| {
                s.type = .curve;
                s.x2 = ex;
                s.y2 = ey;
                s.cx1 = cx1;
                s.cy1 = cy1;
                s.cx2 = cx2;
                s.cy2 = cy2;
            }
            c.gtk_widget_queue_draw(widget);
            return;
        }

        if (current_tool == .line) {
            const start_world_x = (view_x + start_sx) / view_scale;
            const start_world_y = (view_y + start_sy) / view_scale;

            var end_x = c_curr_x;
            var end_y = c_curr_y;

            const state = c.gtk_event_controller_get_current_event_state(@ptrCast(gesture));
            if ((state & c.GDK_SHIFT_MASK) != 0) {
                const snapped = CanvasUtils.snapAngle(start_world_x, start_world_y, c_curr_x, c_curr_y, 45.0);
                end_x = snapped.x;
                end_y = snapped.y;
            }

            const sx: c_int = @intFromFloat(start_world_x);
            const sy: c_int = @intFromFloat(start_world_y);
            const ex: c_int = @intFromFloat(end_x);
            const ey: c_int = @intFromFloat(end_y);

            engine.setShapePreview(sx, sy, 0, 0, 1, false);
            if (engine.preview_shape) |*s| {
                s.type = .line;
                s.x2 = ex;
                s.y2 = ey;
            }

            c.gtk_widget_queue_draw(widget);

            prev_x = current_x;
            prev_y = current_y;
            return;
        }

        if (current_tool == .rect_shape or current_tool == .ellipse_shape or current_tool == .rounded_rect_shape) {
            // Dragging shape
            const start_world_x = (view_x + start_sx) / view_scale;
            const start_world_y = (view_y + start_sy) / view_scale;

            const min_x: c_int = @intFromFloat(@min(start_world_x, c_curr_x));
            const min_y: c_int = @intFromFloat(@min(start_world_y, c_curr_y));
            const w: c_int = @intFromFloat(@abs(c_curr_x - start_world_x));
            const h: c_int = @intFromFloat(@abs(c_curr_y - start_world_y));

            engine.setShapePreview(min_x, min_y, w, h, engine.brush_size, engine.brush_filled);
            if (current_tool == .ellipse_shape) {
                // Update type
                if (engine.preview_shape) |*s| s.type = .ellipse;
            } else if (current_tool == .rounded_rect_shape) {
                if (engine.preview_shape) |*s| {
                    s.type = .rounded_rectangle;
                    s.radius = 20;
                }
            }

            c.gtk_widget_queue_draw(widget);

            prev_x = current_x;
            prev_y = current_y;
            return;
        }

        if (current_tool == .gradient) {
            const start_world_x = (view_x + start_sx) / view_scale;
            const start_world_y = (view_y + start_sy) / view_scale;

            const sx: c_int = @intFromFloat(start_world_x);
            const sy: c_int = @intFromFloat(start_world_y);
            const ex: c_int = @intFromFloat(c_curr_x);
            const ey: c_int = @intFromFloat(c_curr_y);

            engine.setShapePreview(sx, sy, 0, 0, 1, false);
            if (engine.preview_shape) |*s| {
                s.type = .line;
                s.x2 = ex;
                s.y2 = ey;
            }

            c.gtk_widget_queue_draw(widget);

            prev_x = current_x;
            prev_y = current_y;
            return;
        }

        if (current_tool == .rect_select or current_tool == .ellipse_select) {
            if (is_moving_selection) {
                const dx = offset_x / view_scale;
                const dy = offset_y / view_scale;
                engine.updateMoveSelection(dx, dy);
                canvas_dirty = true;
            } else {
                // Dragging selection
                const start_world_x = (view_x + start_sx) / view_scale;
                const start_world_y = (view_y + start_sy) / view_scale;

                // Calculate min/max
                const min_x: c_int = @intFromFloat(@min(start_world_x, c_curr_x));
                const min_y: c_int = @intFromFloat(@min(start_world_y, c_curr_y));
                const max_x: c_int = @intFromFloat(@max(start_world_x, c_curr_x));
                const max_y: c_int = @intFromFloat(@max(start_world_y, c_curr_y));

                engine.setSelection(min_x, min_y, max_x - min_x, max_y - min_y);
            }
            c.gtk_widget_queue_draw(widget);

            prev_x = current_x;
            prev_y = current_y;
            return;
        }

        // Default pressure 1.0 for now
        if (button == 3) {
            // Check tools allowed for right click
            if (current_tool == .brush or current_tool == .pencil or current_tool == .airbrush or current_tool == .line or current_tool == .curve or current_tool == .eraser) {
                engine.paintStrokeWithColor(c_prev_x, c_prev_y, c_curr_x, c_curr_y, 1.0, engine.bg_color);
            }
        } else {
            engine.paintStroke(c_prev_x, c_prev_y, c_curr_x, c_curr_y, 1.0);
        }
        canvas_dirty = true;
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
    is_dragging_interaction = false;

    if (is_moving_selection) {
        engine.commitMoveSelection() catch |err| {
            show_toast("Failed to commit move: {}", .{err});
        };
        is_moving_selection = false;
        refresh_undo_ui();
        canvas_dirty = true;
        if (user_data) |ud| {
            const widget: *c.GtkWidget = @ptrCast(@alignCast(ud));
            c.gtk_widget_queue_draw(widget);
        }
        return;
    }

    if (current_tool == .text) {
        var start_sx: f64 = 0;
        var start_sy: f64 = 0;
        _ = c.gtk_gesture_drag_get_start_point(gesture, &start_sx, &start_sy);

        const dist = offset_x * offset_x + offset_y * offset_y;
        if (dist < 25.0) {
            const start_world_x = (view_x + start_sx) / view_scale;
            const start_world_y = (view_y + start_sy) / view_scale;

            const x: i32 = @intFromFloat(start_world_x);
            const y: i32 = @intFromFloat(start_world_y);

            if (std.heap.c_allocator.create(TextContext)) |ctx| {
                ctx.* = .{ .x = x, .y = y };

                var parent_window: ?*c.GtkWindow = null;
                if (user_data) |ud| {
                    const widget: *c.GtkWidget = @ptrCast(@alignCast(ud));
                    if (c.gtk_widget_get_root(widget)) |root| {
                        parent_window = @ptrCast(@alignCast(root));
                    }
                }

                TextDialog.showTextDialog(parent_window, engine.font_size, &on_text_insert, ctx, &destroy_text_context) catch |err| {
                    show_toast("Failed to show text dialog: {}", .{err});
                    std.heap.c_allocator.destroy(ctx);
                };
            } else |_| {}
        }
        return;
    }

    if (current_tool == .rect_shape or current_tool == .ellipse_shape or current_tool == .rounded_rect_shape) {
        var start_sx: f64 = 0;
        var start_sy: f64 = 0;
        _ = c.gtk_gesture_drag_get_start_point(gesture, &start_sx, &start_sy);
        const current_x = start_sx + offset_x;
        const current_y = start_sy + offset_y;

        const start_world_x = (view_x + start_sx) / view_scale;
        const start_world_y = (view_y + start_sy) / view_scale;
        const c_curr_x = (view_x + current_x) / view_scale;
        const c_curr_y = (view_y + current_y) / view_scale;

        const min_x: c_int = @intFromFloat(@min(start_world_x, c_curr_x));
        const min_y: c_int = @intFromFloat(@min(start_world_y, c_curr_y));
        const w: c_int = @intFromFloat(@abs(c_curr_x - start_world_x));
        const h: c_int = @intFromFloat(@abs(c_curr_y - start_world_y));

        engine.beginTransaction();
        if (current_tool == .rect_shape) {
            engine.drawRectangle(min_x, min_y, w, h, engine.brush_size, engine.brush_filled) catch |err| {
                show_toast("Failed to draw rect: {}", .{err});
            };
        } else if (current_tool == .rounded_rect_shape) {
            engine.drawRoundedRectangle(min_x, min_y, w, h, 20, engine.brush_size, engine.brush_filled) catch |err| {
                show_toast("Failed to draw rounded rect: {}", .{err});
            };
        } else {
            engine.drawEllipse(min_x, min_y, w, h, engine.brush_size, engine.brush_filled) catch |err| {
                show_toast("Failed to draw ellipse: {}", .{err});
            };
        }
        engine.commitTransaction();
        engine.clearShapePreview();
        refresh_undo_ui();
        canvas_dirty = true;

        if (user_data) |ud| {
            const widget: *c.GtkWidget = @ptrCast(@alignCast(ud));
            c.gtk_widget_queue_draw(widget);
        }
        return;
    }

    if (current_tool == .lasso) {
        engine.setSelectionLasso(polygon_points.items);
        engine.commitTransaction();
        engine.clearShapePreview();
        polygon_points.clearRetainingCapacity();
        refresh_undo_ui();
        canvas_dirty = true;
        if (user_data) |ud| {
            const widget: *c.GtkWidget = @ptrCast(@alignCast(ud));
            c.gtk_widget_queue_draw(widget);
        }
        return;
    }

    if (current_tool == .curve) {
        if (curve_phase == 0) {
            curve_phase = 1;
            // Keep preview, do nothing else
        } else if (curve_phase == 1) {
            curve_phase = 2;
            // Keep preview
        } else if (curve_phase == 2) {
            // Commit
            const sx: c_int = @intFromFloat(curve_p1.x);
            const sy: c_int = @intFromFloat(curve_p1.y);
            const ex: c_int = @intFromFloat(curve_p4.x);
            const ey: c_int = @intFromFloat(curve_p4.y);
            const cx1: c_int = @intFromFloat(curve_p2.x);
            const cy1: c_int = @intFromFloat(curve_p2.y);
            const cx2: c_int = @intFromFloat(curve_p3.x);
            const cy2: c_int = @intFromFloat(curve_p3.y);

            engine.beginTransaction();
            const original_fg = engine.fg_color;
            if (drag_button == 3) engine.setFgColor(engine.bg_color[0], engine.bg_color[1], engine.bg_color[2], engine.bg_color[3]);

            engine.drawCurve(sx, sy, ex, ey, cx1, cy1, cx2, cy2) catch |err| {
                show_toast("Failed to draw curve: {}", .{err});
            };

            if (drag_button == 3) engine.setFgColor(original_fg[0], original_fg[1], original_fg[2], original_fg[3]);
            engine.commitTransaction();
            engine.clearShapePreview();
            curve_phase = 0;
            refresh_undo_ui();
            canvas_dirty = true;

            if (user_data) |ud| {
                const widget: *c.GtkWidget = @ptrCast(@alignCast(ud));
                c.gtk_widget_queue_draw(widget);
            }
        }
        return;
    }

    if (current_tool == .line) {
        var start_sx: f64 = 0;
        var start_sy: f64 = 0;
        _ = c.gtk_gesture_drag_get_start_point(gesture, &start_sx, &start_sy);
        const current_x = start_sx + offset_x;
        const current_y = start_sy + offset_y;

        const start_world_x = (view_x + start_sx) / view_scale;
        const start_world_y = (view_y + start_sy) / view_scale;
        const c_curr_x = (view_x + current_x) / view_scale;
        const c_curr_y = (view_y + current_y) / view_scale;

        var end_x = c_curr_x;
        var end_y = c_curr_y;

        const state = c.gtk_event_controller_get_current_event_state(@ptrCast(gesture));
        if ((state & c.GDK_SHIFT_MASK) != 0) {
            const snapped = CanvasUtils.snapAngle(start_world_x, start_world_y, c_curr_x, c_curr_y, 45.0);
            end_x = snapped.x;
            end_y = snapped.y;
        }

        const sx: c_int = @intFromFloat(start_world_x);
        const sy: c_int = @intFromFloat(start_world_y);
        const ex: c_int = @intFromFloat(end_x);
        const ey: c_int = @intFromFloat(end_y);

        engine.beginTransaction();
        const original_fg = engine.fg_color;
        if (drag_button == 3) engine.setFgColor(engine.bg_color[0], engine.bg_color[1], engine.bg_color[2], engine.bg_color[3]);

        engine.drawLine(sx, sy, ex, ey) catch |err| {
            show_toast("Failed to draw line: {}", .{err});
        };

        if (drag_button == 3) engine.setFgColor(original_fg[0], original_fg[1], original_fg[2], original_fg[3]);
        engine.commitTransaction();
        engine.clearShapePreview();
        refresh_undo_ui();
        canvas_dirty = true;

        if (user_data) |ud| {
            const widget: *c.GtkWidget = @ptrCast(@alignCast(ud));
            c.gtk_widget_queue_draw(widget);
        }
        return;
    }

    if (current_tool == .gradient) {
        var start_sx: f64 = 0;
        var start_sy: f64 = 0;
        _ = c.gtk_gesture_drag_get_start_point(gesture, &start_sx, &start_sy);
        const current_x = start_sx + offset_x;
        const current_y = start_sy + offset_y;

        const start_world_x = (view_x + start_sx) / view_scale;
        const start_world_y = (view_y + start_sy) / view_scale;
        const c_curr_x = (view_x + current_x) / view_scale;
        const c_curr_y = (view_y + current_y) / view_scale;

        const sx: c_int = @intFromFloat(start_world_x);
        const sy: c_int = @intFromFloat(start_world_y);
        const ex: c_int = @intFromFloat(c_curr_x);
        const ey: c_int = @intFromFloat(c_curr_y);

        engine.drawGradient(sx, sy, ex, ey) catch |err| {
            show_toast("Failed to draw gradient: {}", .{err});
        };
        engine.commitTransaction();
        engine.clearShapePreview();
        refresh_undo_ui();
        canvas_dirty = true;

        if (user_data) |ud| {
            const widget: *c.GtkWidget = @ptrCast(@alignCast(ud));
            c.gtk_widget_queue_draw(widget);
        }
        return;
    }

    // Commit transaction if any (e.g. from paint tools)
    engine.commitTransaction();
    refresh_undo_ui();
}

fn new_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.addLayer("Background") catch |err| {
        show_toast("Failed to add layer: {}", .{err});
        return;
    };
    refresh_layers_ui();
    refresh_undo_ui();
    update_view_mode();
    canvas_dirty = true;
    queue_draw();
}

const OpenContext = struct {
    window: ?*c.GtkWindow,
    as_layers: bool,
};

const ImportContext = struct {
    as_layers: bool,
};

fn generate_thumbnail(path: [:0]const u8) void {
    recent_manager.ensureThumbnailDir() catch |e| {
        std.debug.print("Failed to ensure thumbnail dir: {}\n", .{e});
        return;
    };

    const thumb_path = recent_manager.getThumbnailPath(path) catch |e| {
        std.debug.print("Failed to get thumbnail path: {}\n", .{e});
        return;
    };
    defer std.heap.c_allocator.free(thumb_path);

    engine.saveThumbnail(thumb_path, 96, 96) catch |e| {
        std.debug.print("Failed to save thumbnail: {}\n", .{e});
    };
}

fn download_callback(source: ?*c.GObject, result: ?*c.GAsyncResult, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    // user_data is path (allocated)
    const path_ptr: [*c]u8 = @ptrCast(@alignCast(user_data));
    const path = std.mem.span(path_ptr);
    defer std.heap.c_allocator.free(path);

    // Check process status?
    // Actually we just check if file exists and has size
    if (std.fs.openFileAbsolute(path, .{})) |file| {
        const stat = file.stat() catch {
            show_toast("Download failed (stat error)", .{});
            file.close();
            return;
        };
        file.close();

        if (stat.size > 0) {
            // Open it (don't add to recent as it's a temp file)
            // But usually we want to "import" it.
            // If we treat it as "Open Location", maybe we DO want it in recent if we supported URI in recent.
            // But RecentManager expects paths.
            // For now: add_to_recent = false.
            // Also as_layers = false for standard open.
            // Convert path to sentinel-terminated for openFileFromPath
            const path_z = std.fmt.allocPrintSentinel(std.heap.c_allocator, "{s}", .{path}, 0) catch return;
            defer std.heap.c_allocator.free(path_z);
            openFileFromPath(path_z, false, false);
        } else {
            show_toast("Download failed (empty file)", .{});
        }
    } else |_| {
        var err: ?*c.GError = null;
        if (c.g_subprocess_wait_check_finish(@ptrCast(source), result, &err) == 0) {
            if (err) |e| {
                show_toast("Download failed: {s}", .{e.*.message});
                c.g_error_free(e);
            } else {
                show_toast("Download failed", .{});
            }
        } else {
            show_toast("Download failed (file missing)", .{});
        }
    }
}

fn downloadAndOpen(uri: [:0]const u8, _: ?*anyopaque) void {
    // 1. Get Cache Dir
    const cache_dir = c.g_get_user_cache_dir();
    if (cache_dir == null) {
        show_toast("Cannot get cache directory", .{});
        return;
    }
    const cache_span = std.mem.span(cache_dir);
    const vimp_cache = std.fs.path.join(std.heap.c_allocator, &[_][]const u8{ cache_span, "vimp", "downloads" }) catch return;
    defer std.heap.c_allocator.free(vimp_cache);

    std.fs.cwd().makePath(vimp_cache) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => {
            show_toast("Failed to create cache dir", .{});
            return;
        },
    };

    // 2. Generate Filename (MD5 of URI + Extension)
    var hash: [16]u8 = undefined;
    std.crypto.hash.Md5.hash(uri, &hash, .{});
    const hash_hex = std.fmt.bytesToHex(hash, .lower);

    // Guess extension
    var ext: []const u8 = ".dat";
    if (std.mem.lastIndexOf(u8, uri, ".")) |idx| {
        if (idx < uri.len - 1) {
            const possible_ext = uri[idx..];
            if (possible_ext.len <= 5) {
                ext = possible_ext;
            }
        }
    }

    const filename = std.fmt.allocPrint(std.heap.c_allocator, "{s}{s}", .{ hash_hex, ext }) catch return;
    defer std.heap.c_allocator.free(filename);

    const dest_path = std.fs.path.joinZ(std.heap.c_allocator, &[_][]const u8{ vimp_cache, filename }) catch return;
    // Pass ownership of dest_path to callback

    // 3. Start Subprocess (curl)
    const proc = c.g_subprocess_new(c.G_SUBPROCESS_FLAGS_NONE, null, "curl", "-L", "-f", "-o", dest_path.ptr, uri.ptr, @as(?*anyopaque, null));

    if (proc == null) {
        show_toast("Failed to start curl", .{});
        std.heap.c_allocator.free(dest_path);
        return;
    }

    show_toast("Downloading...", .{});
    c.g_subprocess_wait_check_async(proc, null, @ptrCast(&download_callback), @ptrCast(dest_path));
    c.g_object_unref(proc);
}

const RawContext = struct {
    original_path: [:0]const u8,
    temp_path: [:0]const u8,
    as_layers: bool,
    add_to_recent: bool,
};

fn raw_conversion_callback(source: ?*c.GObject, result: ?*c.GAsyncResult, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *RawContext = @ptrCast(@alignCast(user_data));
    defer {
        std.heap.c_allocator.free(ctx.original_path);
        std.heap.c_allocator.free(ctx.temp_path);
        std.heap.c_allocator.destroy(ctx);
    }

    var err: ?*c.GError = null;
    if (c.g_subprocess_wait_check_finish(@ptrCast(source), result, &err) != 0) {
        // Success
        // Open the temp file
        openFileFromPath(ctx.temp_path, ctx.as_layers, false);

        // Clean up temp file
        std.fs.deleteFileAbsolute(ctx.temp_path) catch |e| {
            std.debug.print("Failed to delete temp file: {}\n", .{e});
        };

        // Add ORIGINAL path to recent, if needed
        if (ctx.add_to_recent) {
            recent_manager.add(ctx.original_path) catch {};
            // Generate thumbnail for original path using current engine state
            generate_thumbnail(ctx.original_path);
            refresh_recent_ui();
        }
    } else {
        if (err) |e| {
            show_toast("Raw conversion failed: {s}", .{e.*.message});
            c.g_error_free(e);
        } else {
            show_toast("Raw conversion failed", .{});
        }
    }
}

fn convertRawAndOpen(path: [:0]const u8, as_layers: bool, add_to_recent: bool) void {
    const tool = RawLoader.findRawTool();
    if (tool == .none) {
        show_toast("No RAW developer found (install Darktable or RawTherapee)", .{});
        return;
    }

    const allocator = std.heap.c_allocator;

    // Generate temp output path
    const stem = std.fs.path.stem(path);
    const rnd = std.time.nanoTimestamp();
    const out_name = std.fmt.allocPrint(allocator, "{s}_{d}.png", .{ stem, rnd }) catch return;
    defer allocator.free(out_name);

    const tmp_dir_c = c.g_get_tmp_dir();
    const tmp_dir = std.mem.span(tmp_dir_c);

    const out_path = std.fs.path.joinZ(allocator, &[_][]const u8{ tmp_dir, out_name }) catch return;

    const path_dup = allocator.dupeZ(u8, path) catch {
        allocator.free(out_path);
        return;
    };

    const ctx = allocator.create(RawContext) catch {
        allocator.free(out_path);
        allocator.free(path_dup);
        return;
    };
    ctx.* = .{
        .original_path = path_dup,
        .temp_path = out_path,
        .as_layers = as_layers,
        .add_to_recent = add_to_recent,
    };

    var proc: ?*c.GSubprocess = null;

    if (tool == .darktable) {
        proc = c.g_subprocess_new(c.G_SUBPROCESS_FLAGS_NONE, null, "darktable-cli", path.ptr, out_path.ptr, @as(?*anyopaque, null));
    } else if (tool == .rawtherapee) {
        proc = c.g_subprocess_new(c.G_SUBPROCESS_FLAGS_NONE, null, "rawtherapee-cli", "-o", out_path.ptr, "-c", path.ptr, @as(?*anyopaque, null));
    }

    if (proc) |p| {
        show_toast("Developing RAW image...", .{});
        c.g_subprocess_wait_check_async(p, null, @ptrCast(&raw_conversion_callback), ctx);
        c.g_object_unref(p);
    } else {
        show_toast("Failed to start RAW conversion process", .{});
        allocator.free(out_path);
        allocator.free(path_dup);
        allocator.destroy(ctx);
    }
}

const TextContext = struct {
    x: i32,
    y: i32,
};

fn destroy_text_context(data: ?*anyopaque) void {
    const ctx: *TextContext = @ptrCast(@alignCast(data));
    std.heap.c_allocator.destroy(ctx);
}

fn on_text_insert(user_data: ?*anyopaque, text: [:0]const u8, size: i32) void {
    const ctx: *TextContext = @ptrCast(@alignCast(user_data));

    engine.drawText(text, ctx.x, ctx.y, size) catch |err| {
        show_toast("Failed to draw text: {}", .{err});
    };

    refresh_layers_ui();
    refresh_undo_ui();
    update_view_mode();
    canvas_dirty = true;
    queue_draw();
}

fn finish_file_open(path: [:0]const u8, as_layers: bool, success: bool, add_to_recent: bool) void {
    if (success and add_to_recent) {
        recent_manager.add(path) catch |e| {
            std.debug.print("Failed to add to recent: {}\n", .{e});
        };
        generate_thumbnail(path);
        refresh_recent_ui();
    }

    if (success and !as_layers) {
        // If replacing content, set canvas size to first layer
        if (engine.layers.items.len > 0) {
            const layer = &engine.layers.items[0];
            const extent = c.gegl_buffer_get_extent(layer.buffer);
            engine.setCanvasSize(extent.*.width, extent.*.height);
        }
    }

    // Refresh UI
    refresh_layers_ui();
    refresh_undo_ui();
    update_view_mode();
    canvas_dirty = true;
    queue_draw();
}

fn on_pdf_import(user_data: ?*anyopaque, path: [:0]const u8, params: ?Engine.PdfImportParams) void {
    const ctx: *ImportContext = @ptrCast(@alignCast(user_data));
    defer std.heap.c_allocator.destroy(ctx);

    if (params) |p| {
        var perform_reset = !ctx.as_layers;

        if (p.split_pages) {
            if (p.pages.len > 1) {
                show_toast("Opening multiple pages as separate images is not yet supported. Opening as layers.", .{});
            }
            // "Separate Images" implies opening as a new image (since we lack tabs), replacing current.
            perform_reset = true;
        }

        if (perform_reset) {
            engine.reset();
        }

        var success = true;
        engine.loadPdf(path, p) catch |e| {
            show_toast("Failed to load PDF: {}", .{e});
            success = false;
        };
        finish_file_open(path, !perform_reset, success, true);
    }
    // Else cancelled, do nothing (context is freed by defer)
}

fn on_svg_import(user_data: ?*anyopaque, path: [:0]const u8, params: ?Engine.SvgImportParams) void {
    const ctx: *ImportContext = @ptrCast(@alignCast(user_data));
    defer std.heap.c_allocator.destroy(ctx);

    if (params) |p| {
        if (!ctx.as_layers) {
            engine.reset();
        }

        var success = true;
        engine.loadSvg(path, p) catch |e| {
            show_toast("Failed to load SVG: {}", .{e});
            success = false;
        };
        finish_file_open(path, ctx.as_layers, success, true);
    }
}

fn openFileFromPath(path: [:0]const u8, as_layers: bool, add_to_recent: bool) void {
    const ext = std.fs.path.extension(path);
    const is_pdf = std.ascii.eqlIgnoreCase(ext, ".pdf");
    const is_svg = std.ascii.eqlIgnoreCase(ext, ".svg");
    const is_ora = std.ascii.eqlIgnoreCase(ext, ".ora");

    if (is_ora) {
        var success = true;
        engine.loadOra(path, !as_layers) catch |e| {
            show_toast("Failed to load ORA: {}", .{e});
            success = false;
        };
        finish_file_open(path, as_layers, success, add_to_recent);
        return;
    }

    if (RawLoader.isRawFile(path)) {
        convertRawAndOpen(path, as_layers, add_to_recent);
        return;
    }

    if (is_pdf) {
        const ctx = std.heap.c_allocator.create(ImportContext) catch return;
        ctx.* = .{ .as_layers = as_layers };

        var parent_window: ?*c.GtkWindow = null;
        if (main_stack) |s| {
            const root = c.gtk_widget_get_root(@ptrCast(s));
            if (root) |r| parent_window = @ptrCast(@alignCast(r));
        }

        ImportDialogs.showPdfImportDialog(parent_window, &engine, path, &on_pdf_import, ctx) catch |e| {
            show_toast("Failed to show import dialog: {}", .{e});
            std.heap.c_allocator.destroy(ctx);
        };
        return;
    }

    if (is_svg) {
        const ctx = std.heap.c_allocator.create(ImportContext) catch return;
        ctx.* = .{ .as_layers = as_layers };

        var parent_window: ?*c.GtkWindow = null;
        if (main_stack) |s| {
            const root = c.gtk_widget_get_root(@ptrCast(s));
            if (root) |r| parent_window = @ptrCast(@alignCast(r));
        }

        ImportDialogs.showSvgImportDialog(parent_window, path, &on_svg_import, ctx) catch |e| {
            show_toast("Failed to show import dialog: {}", .{e});
            std.heap.c_allocator.destroy(ctx);
        };
        return;
    }

    if (!as_layers) {
        engine.reset();
    }

    var load_success = true;
    // Call engine load
    engine.loadFromFile(path) catch |e| {
        show_toast("Failed to load file: {}", .{e});
        load_success = false;
    };
    finish_file_open(path, as_layers, load_success, add_to_recent);
}

fn on_file_chosen(user_data: ?*anyopaque, path: ?[:0]const u8) void {
    const ctx: *OpenContext = @ptrCast(@alignCast(user_data));
    defer std.heap.c_allocator.destroy(ctx);

    if (path) |p| {
        openFileFromPath(p, ctx.as_layers, true);
    }
}

fn open_common(window: ?*c.GtkWindow, as_layers: bool) void {
    const ctx = std.heap.c_allocator.create(OpenContext) catch return;
    ctx.* = .{ .window = window, .as_layers = as_layers };

    const title: [:0]const u8 = if (as_layers) "Open as Layers" else "Open Image";

    FileChooser.showOpenDialog(
        window,
        title,
        as_layers,
        &on_file_chosen,
        ctx,
    ) catch |e| {
        show_toast("Failed to open dialog: {}", .{e});
        std.heap.c_allocator.destroy(ctx);
    };
}

fn open_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    open_common(window, false);
}

fn open_as_layers_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    open_common(window, true);
}

fn open_location_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    OpenLocationDialog.showOpenLocationDialog(window, @ptrCast(&downloadAndOpen), null);
}

fn save_surface_to_file(s: *c.cairo_surface_t, filename: [*c]const u8) void {
    const result = c.cairo_surface_write_to_png(s, filename);
    if (result == c.CAIRO_STATUS_SUCCESS) {
        show_toast("File saved to: {s}", .{filename});
    } else {
        show_toast("Error saving file: {d}", .{result});
    }
}

fn save_file(filename_c: [*c]const u8) void {
    const filename = std.mem.span(filename_c);
    const ext = std.fs.path.extension(filename);
    if (std.ascii.eqlIgnoreCase(ext, ".ora")) {
        engine.saveOra(filename) catch |err| {
            show_toast("Error saving ORA: {}", .{err});
        };
        show_toast("File saved to: {s}", .{filename});
        return;
    }

    if (surface) |s| {
        if (c.cairo_surface_status(s) == c.CAIRO_STATUS_SUCCESS) {
            save_surface_to_file(s, filename_c);
        } else {
            show_toast("Surface invalid, cannot save.", .{});
        }
    } else {
        show_toast("No surface to save.", .{});
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
            show_toast("Error saving: {s}", .{e.*.message});
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

    const filter_ora = c.gtk_file_filter_new();
    c.gtk_file_filter_set_name(filter_ora, "OpenRaster Image");
    c.gtk_file_filter_add_pattern(filter_ora, "*.ora");
    c.g_list_store_append(filters, filter_ora);
    c.g_object_unref(filter_ora);

    // GtkFileDialog takes ownership of filters? No, it uses the model.
    // gtk_file_dialog_set_filters (GtkFileDialog *self, GListModel *filters)
    c.gtk_file_dialog_set_filters(dialog, @ptrCast(filters));
    c.g_object_unref(filters);

    c.gtk_file_dialog_save(dialog, window, null, @ptrCast(&save_finish), null);
    c.g_object_unref(dialog);
}

test "save surface" {
    const s = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, 10, 10) orelse return error.CairoFailed;
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

test "openFileFromPath integration" {
    // Setup Engine manually since main() is not called
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // Create a dummy PNG file
    const s = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, 100, 100) orelse return error.CairoFailed;
    defer c.cairo_surface_destroy(s);
    // Fill with something to ensure it's not empty/transparent if that matters
    const cr = c.cairo_create(s);
    c.cairo_set_source_rgb(cr, 1.0, 0.0, 0.0);
    c.cairo_paint(cr);
    c.cairo_destroy(cr);

    const test_file = "test_drop.png";
    save_surface_to_file(s, test_file);
    defer std.fs.cwd().deleteFile(test_file) catch {};

    // 1. Open New
    openFileFromPath(test_file, false);
    try std.testing.expectEqual(@as(usize, 1), engine.layers.items.len);
    try std.testing.expectEqualStrings("test_drop.png", std.mem.span(@as([*:0]const u8, @ptrCast(&engine.layers.items[0].name))));

    // 2. Add as Layer
    openFileFromPath(test_file, true);
    try std.testing.expectEqual(@as(usize, 2), engine.layers.items.len);
    // The second layer name might be "test_drop.png" or similar
    // Note: layers are appended. Items[0] is bottom (first loaded), items[1] is top (second loaded).
    try std.testing.expectEqualStrings("test_drop.png", std.mem.span(@as([*:0]const u8, @ptrCast(&engine.layers.items[1].name))));
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
    refresh_layers_ui(); // Layers might change
    update_view_mode();
    canvas_dirty = true;
    queue_draw();
    refresh_undo_ui();
}

fn redo_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.redo();
    refresh_layers_ui(); // Layers might change
    update_view_mode();
    canvas_dirty = true;
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
    canvas_dirty = true;
    queue_draw();
}

fn blur_medium_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.setPreviewBlur(10.0);
    refresh_header_ui();
    canvas_dirty = true;
    queue_draw();
}

fn blur_large_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.setPreviewBlur(20.0);
    refresh_header_ui();
    canvas_dirty = true;
    queue_draw();
}

fn refresh_ui_callback() void {
    refresh_header_ui();
    refresh_undo_ui();
    canvas_dirty = true;
    queue_draw();
}

fn pixelize_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showPixelizeDialog(window, &engine, &refresh_ui_callback);
}

fn motion_blur_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showMotionBlurDialog(window, &engine, &refresh_ui_callback);
}

fn unsharp_mask_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showUnsharpMaskDialog(window, &engine, &refresh_ui_callback);
}

fn noise_reduction_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showNoiseReductionDialog(window, &engine, &refresh_ui_callback);
}

fn oilify_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showOilifyDialog(window, &engine, &refresh_ui_callback);
}

fn drop_shadow_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showDropShadowDialog(window, &engine, &refresh_ui_callback);
}

fn red_eye_removal_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showRedEyeRemovalDialog(window, &engine, &refresh_ui_callback);
}

fn waves_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showWavesDialog(window, &engine, &refresh_ui_callback);
}

fn supernova_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showSupernovaDialog(window, &engine, &refresh_ui_callback);
}

fn lighting_effects_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showLightingDialog(window, &engine, &refresh_ui_callback);
}

fn stretch_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showStretchDialog(window, &engine, &refresh_ui_callback);
}

fn apply_preview_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.commitPreview() catch |err| {
        show_toast("Commit preview failed: {}", .{err});
    };
    refresh_header_ui();
    canvas_dirty = true;
    queue_draw();
    refresh_undo_ui();
}

fn discard_preview_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.cancelPreview();
    refresh_header_ui();
    canvas_dirty = true;
    queue_draw();
}

fn invert_colors_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.invertColors() catch |err| {
        show_toast("Invert colors failed: {}", .{err});
        return;
    };
    refresh_undo_ui();
    canvas_dirty = true;
    queue_draw();
}

fn clear_image_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.clearActiveLayer() catch |err| {
        show_toast("Clear image failed: {}", .{err});
        return;
    };
    refresh_undo_ui();
    canvas_dirty = true;
    queue_draw();
}

fn flip_horizontal_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.flipHorizontal() catch |err| {
        show_toast("Flip horizontal failed: {}", .{err});
        return;
    };
    refresh_undo_ui();
    canvas_dirty = true;
    queue_draw();
}

fn flip_vertical_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.flipVertical() catch |err| {
        show_toast("Flip vertical failed: {}", .{err});
        return;
    };
    refresh_undo_ui();
    canvas_dirty = true;
    queue_draw();
}

fn rotate_90_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.rotate90() catch |err| {
        show_toast("Rotate 90 failed: {}", .{err});
        return;
    };
    refresh_undo_ui();
    canvas_dirty = true;
    queue_draw();
}

fn rotate_180_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.rotate180() catch |err| {
        show_toast("Rotate 180 failed: {}", .{err});
        return;
    };
    refresh_undo_ui();
    canvas_dirty = true;
    queue_draw();
}

fn rotate_270_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.rotate270() catch |err| {
        show_toast("Rotate 270 failed: {}", .{err});
        return;
    };
    refresh_undo_ui();
    canvas_dirty = true;
    queue_draw();
}

fn canvas_size_callback(width: c_int, height: c_int, user_data: ?*anyopaque) void {
    _ = user_data;
    engine.setCanvasSize(width, height);
    refresh_undo_ui();
    canvas_dirty = true;
    queue_draw();
}

fn canvas_size_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    CanvasDialog.showCanvasSizeDialog(window, engine.canvas_width, engine.canvas_height, @ptrCast(&canvas_size_callback), null);
}

fn view_bitmap_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    if (window) |w| {
        FullscreenPreview.showFullscreenPreview(w, &engine);
    }
}

fn view_thumbnail_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    if (window) |w| {
        ThumbnailWindow.show(w, &thumbnail_ctx);
    }
}

fn command_palette_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    // We need the app pointer, which we can get from the window or pass it?
    // user_data is currently the window.
    if (window) |w| {
        const app = c.gtk_window_get_application(w);
        if (app) |a| {
            CommandPalette.showCommandPalette(w, a);
        }
    }
}

fn split_view_change_state(action: *c.GSimpleAction, value: *c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const enabled = c.g_variant_get_boolean(value) != 0;
    engine.setSplitView(enabled);
    c.g_simple_action_set_state(action, value);
    canvas_dirty = true;
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
    ThumbnailWindow.refresh();
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
    canvas_dirty = true;
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
    canvas_dirty = true;
    queue_draw();
}

fn layer_remove_clicked(_: *c.GtkButton, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.removeLayer(engine.active_layer_idx);
    refresh_layers_ui();
    refresh_undo_ui();
    update_view_mode();
    canvas_dirty = true;
    queue_draw();
}

fn layer_up_clicked(_: *c.GtkButton, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const idx = engine.active_layer_idx;
    if (idx + 1 < engine.layers.items.len) {
        engine.reorderLayer(idx, idx + 1);
        refresh_layers_ui();
        refresh_undo_ui();
        canvas_dirty = true;
        queue_draw();
    }
}

fn layer_down_clicked(_: *c.GtkButton, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const idx = engine.active_layer_idx;
    if (idx > 0) {
        engine.reorderLayer(idx, idx - 1);
        refresh_layers_ui();
        refresh_undo_ui();
        canvas_dirty = true;
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

fn osd_hide_callback(user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) c.gboolean {
    _ = user_data;
    if (osd_state.revealer) |rev| {
        c.gtk_revealer_set_reveal_child(@ptrCast(rev), 0);
    }
    osd_state.timeout_id = 0;
    return 0; // G_SOURCE_REMOVE
}

fn osd_show(text: []const u8) void {
    if (osd_state.label == null or osd_state.revealer == null) return;

    var buf: [128]u8 = undefined;
    const slice = std.fmt.bufPrintZ(&buf, "{s}", .{text}) catch return;
    c.gtk_label_set_text(@ptrCast(osd_state.label), slice.ptr);

    c.gtk_revealer_set_reveal_child(@ptrCast(osd_state.revealer), 1);

    if (osd_state.timeout_id != 0) {
        _ = c.g_source_remove(osd_state.timeout_id);
    }
    osd_state.timeout_id = c.g_timeout_add(1500, @ptrCast(&osd_hide_callback), null);
}

const DropConfirmContext = struct {
    path: [:0]u8,
};

fn drop_response(
    dialog: *c.AdwMessageDialog,
    response: [*c]const u8,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *DropConfirmContext = @ptrCast(@alignCast(user_data));
    // We must clean up context and path regardless of choice
    const allocator = std.heap.c_allocator;
    defer allocator.destroy(ctx);
    defer allocator.free(ctx.path);

    const resp_span = std.mem.span(response);

    if (std.mem.eql(u8, resp_span, "new")) {
        openFileFromPath(ctx.path, false, true);
    } else if (std.mem.eql(u8, resp_span, "layer")) {
        openFileFromPath(ctx.path, true, true);
    }
    // "cancel" or others do nothing but cleanup

    // Destroy the dialog
    c.gtk_window_destroy(@ptrCast(dialog));
}

fn drop_func(
    target: *c.GtkDropTarget,
    value: *const c.GValue,
    x: f64,
    y: f64,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) c.gboolean {
    _ = target;
    _ = x;
    _ = y;

    // Check if we have a window handle
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;

    const file_obj = c.g_value_get_object(value);
    if (file_obj) |obj| {
        // Safe cast as we requested G_TYPE_FILE
        const file: *c.GFile = @ptrCast(obj);
        const path = c.g_file_get_path(file);
        if (path) |p| {
            const span = std.mem.span(@as([*:0]const u8, @ptrCast(p)));

            // Logic: If layers exist AND we have a window to show dialog on -> Ask User
            if (engine.layers.items.len > 0 and window != null) {
                const allocator = std.heap.c_allocator;
                // Copy path
                const path_copy = allocator.dupeZ(u8, span) catch {
                    c.g_free(p);
                    return 0;
                };

                const ctx = allocator.create(DropConfirmContext) catch {
                    allocator.free(path_copy);
                    c.g_free(p);
                    return 0;
                };
                ctx.* = .{ .path = path_copy };

                const dialog = c.adw_message_dialog_new(
                    window.?,
                    "Import Image",
                    "How would you like to open this image?",
                );

                c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "_Cancel");
                c.adw_message_dialog_add_response(@ptrCast(dialog), "new", "_Open as New Image");
                c.adw_message_dialog_add_response(@ptrCast(dialog), "layer", "_Add as Layer");

                c.adw_message_dialog_set_default_response(@ptrCast(dialog), "layer");
                c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

                _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&drop_response), ctx, null, 0);

                c.gtk_window_present(@ptrCast(dialog));
            } else {
                const as_layers = (engine.layers.items.len > 0);
                openFileFromPath(span, as_layers, true);
            }

            c.g_free(p);
            return 1;
        }
    }

    return 0;
}

fn on_recent_row_activated(_: *c.GtkListBox, row: *c.GtkListBoxRow, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const data = c.g_object_get_data(@ptrCast(row), "file-path");
    if (data) |p| {
        const path: [*c]const u8 = @ptrCast(p);
        const span = std.mem.span(path);
        // Ensure we don't block if open takes time, but openFileFromPath is synchronous currently except for dialogs
        openFileFromPath(span, false, true);
    }
}

fn refresh_recent_ui() void {
    if (recent_list_box) |box| {
        // Clear
        var child = c.gtk_widget_get_first_child(@ptrCast(box));
        while (child != null) {
            const next = c.gtk_widget_get_next_sibling(child);
            c.gtk_list_box_remove(@ptrCast(box), child);
            child = next;
        }

        // Add recent files
        if (recent_manager.paths.items.len == 0) {
            const label = c.gtk_label_new("(No recent files)");
            c.gtk_widget_add_css_class(label, "dim-label");
            c.gtk_widget_set_margin_top(label, 10);
            c.gtk_widget_set_margin_bottom(label, 10);
            // Insert as a non-activatable row or just a child?
            // ListBox expects rows.
            const row = c.gtk_list_box_row_new();
            c.gtk_list_box_row_set_child(@ptrCast(row), label);
            c.gtk_list_box_row_set_activatable(@ptrCast(row), 0);
            c.gtk_list_box_append(@ptrCast(box), row);
        } else {
            for (recent_manager.paths.items) |path| {
                const row = c.gtk_list_box_row_new();

                const row_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 12);
                c.gtk_widget_set_margin_top(row_box, 8);
                c.gtk_widget_set_margin_bottom(row_box, 8);
                c.gtk_widget_set_margin_start(row_box, 12);
                c.gtk_widget_set_margin_end(row_box, 12);

                var icon_widget: *c.GtkWidget = undefined;
                var has_thumb = false;

                if (recent_manager.getThumbnailPath(path)) |tp| {
                    if (std.fs.openFileAbsolute(tp, .{})) |f| {
                        f.close();
                        const tp_z = std.fmt.allocPrintSentinel(std.heap.c_allocator, "{s}", .{tp}, 0) catch null;
                        if (tp_z) |z| {
                            icon_widget = c.gtk_image_new_from_file(z);
                            c.gtk_image_set_pixel_size(@ptrCast(icon_widget), 64);
                            std.heap.c_allocator.free(z);
                            has_thumb = true;
                        }
                    } else |_| {}
                    std.heap.c_allocator.free(tp);
                } else |_| {}

                if (!has_thumb) {
                    icon_widget = c.gtk_image_new_from_icon_name("image-x-generic-symbolic");
                    c.gtk_image_set_pixel_size(@ptrCast(icon_widget), 32);
                }
                c.gtk_box_append(@ptrCast(row_box), icon_widget);

                const basename = std.fs.path.basename(path);
                var buf: [256]u8 = undefined;
                const label_text = std.fmt.bufPrintZ(&buf, "{s}", .{basename}) catch "File";

                const label = c.gtk_label_new(label_text.ptr);
                c.gtk_widget_set_hexpand(label, 1);
                c.gtk_widget_set_halign(label, c.GTK_ALIGN_START);
                c.gtk_box_append(@ptrCast(row_box), label);

                // Show full path as tooltip
                var path_buf: [1024]u8 = undefined;
                const path_z = std.fmt.bufPrintZ(&path_buf, "{s}", .{path}) catch "File";
                c.gtk_widget_set_tooltip_text(row, path_z.ptr);

                c.gtk_list_box_row_set_child(@ptrCast(row), row_box);
                c.gtk_list_box_append(@ptrCast(box), row);

                // Attach data
                const path_dup = std.fmt.allocPrintSentinel(std.heap.c_allocator, "{s}", .{path}, 0) catch continue;
                c.g_object_set_data_full(@ptrCast(row), "file-path", @ptrCast(path_dup), @ptrCast(&c.g_free));
            }
        }
    }
}

const ToolGroupItemContext = struct {
    main_btn: *c.GtkWidget,
    active_tool_ref: *Tool,
    tool: Tool,
    icon_data: ?[]const u8,
    icon_name: ?[:0]const u8,
    tooltip: [:0]const u8,
    popover: *c.GtkPopover,
};

fn destroy_tool_group_item_context(data: ?*anyopaque, _: ?*c.GClosure) callconv(std.builtin.CallingConvention.c) void {
    if (data) |d| {
        const ctx: *ToolGroupItemContext = @ptrCast(@alignCast(d));
        std.heap.c_allocator.destroy(ctx);
    }
}

fn on_group_item_clicked(_: *c.GtkButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *ToolGroupItemContext = @ptrCast(@alignCast(user_data));

    // 1. Update active tool ref
    ctx.active_tool_ref.* = ctx.tool;

    // 2. Update Main Button Icon/Tooltip
    var img: *c.GtkWidget = undefined;
    if (ctx.icon_data) |data| {
        img = Assets.getIconWidget(data, 24);
    } else if (ctx.icon_name) |name| {
        img = c.gtk_image_new_from_icon_name(name);
        c.gtk_widget_set_size_request(img, 24, 24);
    } else {
        img = c.gtk_image_new_from_icon_name("image-missing-symbolic");
        c.gtk_widget_set_size_request(img, 24, 24);
    }

    c.gtk_button_set_child(@ptrCast(ctx.main_btn), img);
    c.gtk_widget_set_tooltip_text(ctx.main_btn, ctx.tooltip);

    // 3. Activate Main Button
    const is_active = c.gtk_toggle_button_get_active(@ptrCast(ctx.main_btn)) != 0;
    if (!is_active) {
        c.gtk_toggle_button_set_active(@ptrCast(ctx.main_btn), 1);
    } else {
        // Force update
        tool_toggled(@ptrCast(ctx.main_btn), ctx.active_tool_ref);
    }

    // 4. Hide Popover
    c.gtk_popover_popdown(ctx.popover);
}

fn on_group_right_click(
    gesture: *c.GtkGestureClick,
    _: c_int,
    _: f64,
    _: f64,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    const popover: *c.GtkPopover = @ptrCast(@alignCast(user_data));
    const widget = c.gtk_event_controller_get_widget(@ptrCast(gesture));
    c.gtk_widget_set_parent(@ptrCast(popover), widget);
    c.gtk_popover_popup(popover);
}

fn on_group_long_press(
    gesture: *c.GtkGestureLongPress,
    _: f64,
    _: f64,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    const popover: *c.GtkPopover = @ptrCast(@alignCast(user_data));
    const widget = c.gtk_event_controller_get_widget(@ptrCast(gesture));
    c.gtk_widget_set_parent(@ptrCast(popover), widget);
    c.gtk_popover_popup(popover);
}

fn autosave_callback(user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) c.gboolean {
    _ = user_data;
    if (engine.layers.items.len == 0) return 1; // Keep running but don't save empty

    const cache_dir_c = c.g_get_user_cache_dir();
    if (cache_dir_c == null) return 1;
    const cache_dir = std.mem.span(cache_dir_c);

    const path = std.fs.path.join(std.heap.c_allocator, &[_][]const u8{ cache_dir, "vimp", "autosave" }) catch return 1;
    defer std.heap.c_allocator.free(path);

    engine.saveProject(path) catch |err| {
        std.debug.print("Autosave failed: {}\n", .{err});
    };

    return 1; // Continue
}

const RecoveryContext = struct {
    path: [:0]u8,
};

fn recovery_response(
    dialog: *c.AdwMessageDialog,
    response: [*c]const u8,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *RecoveryContext = @ptrCast(@alignCast(user_data));
    defer std.heap.c_allocator.destroy(ctx);
    defer std.heap.c_allocator.free(ctx.path);

    const resp_span = std.mem.span(response);

    if (std.mem.eql(u8, resp_span, "recover")) {
        engine.loadProject(ctx.path) catch |err| {
             show_toast("Failed to recover project: {}", .{err});
        };
        refresh_layers_ui();
        refresh_undo_ui();
        update_view_mode();
        canvas_dirty = true;
        queue_draw();
    } else if (std.mem.eql(u8, resp_span, "discard")) {
        std.fs.cwd().deleteTree(ctx.path) catch {};
    }

    c.gtk_window_destroy(@ptrCast(dialog));
}

fn check_autosave(window: *c.GtkWindow) void {
     const cache_dir_c = c.g_get_user_cache_dir();
     if (cache_dir_c == null) return;
     const cache_dir = std.mem.span(cache_dir_c);

     const path = std.fs.path.joinZ(std.heap.c_allocator, &[_][]const u8{ cache_dir, "vimp", "autosave" }) catch return;
     // Don't free path yet, pass to ctx

     // Check if exists
     var dir = std.fs.cwd().openDir(path, .{}) catch {
         std.heap.c_allocator.free(path);
         return;
     };
     dir.close();

     // Check project.json
     const json_path = std.fs.path.joinZ(std.heap.c_allocator, &[_][]const u8{ path, "project.json" }) catch {
         std.heap.c_allocator.free(path);
         return;
     };
     defer std.heap.c_allocator.free(json_path);

     if (std.fs.cwd().access(json_path, .{})) |_| {
         // Found! Show dialog.
         const ctx = std.heap.c_allocator.create(RecoveryContext) catch {
             std.heap.c_allocator.free(path);
             return;
         };
         ctx.* = .{ .path = path };

         const dialog = c.adw_message_dialog_new(
             window,
             "Unsaved Work Found",
             "A previous session was not closed properly. Do you want to recover your work?",
         );

         c.adw_message_dialog_add_response(@ptrCast(dialog), "discard", "_Discard");
         c.adw_message_dialog_add_response(@ptrCast(dialog), "recover", "_Recover");

         c.adw_message_dialog_set_default_response(@ptrCast(dialog), "recover");
         c.adw_message_dialog_set_close_response(@ptrCast(dialog), "discard");

         _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&recovery_response), ctx, null, 0);

         c.gtk_window_present(@ptrCast(dialog));
     } else |_| {
         std.heap.c_allocator.free(path);
     }
}

fn activate(app: *c.GtkApplication, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    _ = user_data;

    // Init recent manager
    recent_manager = RecentManager.init(std.heap.c_allocator);
    recent_manager.load() catch |err| {
        std.debug.print("Failed to load recent files: {}\n", .{err});
    };

    // Init recent colors
    recent_colors_manager = RecentColorsManager.init(std.heap.c_allocator);
    recent_colors_manager.load() catch |err| {
        std.debug.print("Failed to load recent colors: {}\n", .{err});
    };

    // Init polygon points
    polygon_points = .{};

    // Start Autosave Timer (every 30 seconds)
    if (autosave_timer_id == 0) {
        autosave_timer_id = c.g_timeout_add_seconds(30, @ptrCast(&autosave_callback), null);
    }

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
    add_action(app, "open", @ptrCast(&open_activated), window);
    add_action(app, "open-as-layers", @ptrCast(&open_as_layers_activated), window);
    add_action(app, "open-location", @ptrCast(&open_location_activated), window);
    add_action(app, "save", @ptrCast(&save_activated), window);
    add_action(app, "about", @ptrCast(&about_activated), null);
    add_action(app, "quit", @ptrCast(&quit_activated), app);
    add_action(app, "undo", @ptrCast(&undo_activated), null);
    add_action(app, "redo", @ptrCast(&redo_activated), null);
    add_action(app, "blur-small", @ptrCast(&blur_small_activated), null);
    add_action(app, "blur-medium", @ptrCast(&blur_medium_activated), null);
    add_action(app, "blur-large", @ptrCast(&blur_large_activated), null);
    add_action(app, "pixelize", @ptrCast(&pixelize_activated), window);
    add_action(app, "motion-blur", @ptrCast(&motion_blur_activated), window);
    add_action(app, "unsharp-mask", @ptrCast(&unsharp_mask_activated), window);
    add_action(app, "noise-reduction", @ptrCast(&noise_reduction_activated), window);
    add_action(app, "oilify", @ptrCast(&oilify_activated), window);
    add_action(app, "drop-shadow", @ptrCast(&drop_shadow_activated), window);
    add_action(app, "red-eye-removal", @ptrCast(&red_eye_removal_activated), window);
    add_action(app, "waves", @ptrCast(&waves_activated), window);
    add_action(app, "supernova", @ptrCast(&supernova_activated), window);
    add_action(app, "lighting-effects", @ptrCast(&lighting_effects_activated), window);
    add_action(app, "stretch", @ptrCast(&stretch_activated), window);
    add_action(app, "apply-preview", @ptrCast(&apply_preview_activated), null);
    add_action(app, "discard-preview", @ptrCast(&discard_preview_activated), null);
    add_action(app, "invert-colors", @ptrCast(&invert_colors_activated), null);
    add_action(app, "clear-image", @ptrCast(&clear_image_activated), null);
    add_action(app, "flip-horizontal", @ptrCast(&flip_horizontal_activated), null);
    add_action(app, "flip-vertical", @ptrCast(&flip_vertical_activated), null);
    add_action(app, "rotate-90", @ptrCast(&rotate_90_activated), null);
    add_action(app, "rotate-180", @ptrCast(&rotate_180_activated), null);
    add_action(app, "rotate-270", @ptrCast(&rotate_270_activated), null);
    add_action(app, "canvas-size", @ptrCast(&canvas_size_activated), window);
    add_action(app, "view-bitmap", @ptrCast(&view_bitmap_activated), window);
    add_action(app, "view-thumbnail", @ptrCast(&view_thumbnail_activated), window);
    add_action(app, "command-palette", @ptrCast(&command_palette_activated), window);

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
    set_accel(app, "app.open-as-layers", "<Ctrl><Alt>o");
    set_accel(app, "app.open-location", "<Ctrl>l");
    set_accel(app, "app.save", "<Ctrl>s");
    set_accel(app, "app.undo", "<Ctrl>z");
    set_accel(app, "app.redo", "<Ctrl>y");
    set_accel(app, "app.invert-colors", "<Ctrl>i");
    set_accel(app, "app.clear-image", "<Ctrl><Shift>n");
    set_accel(app, "app.rotate-90", "<Ctrl>r");
    set_accel(app, "app.command-palette", "<Ctrl>k");

    const toolbar_view = c.adw_toolbar_view_new();
    c.adw_application_window_set_content(@ptrCast(window), toolbar_view);

    // AdwToastOverlay
    const t_overlay = c.adw_toast_overlay_new();
    toast_overlay = @ptrCast(t_overlay);
    c.adw_toolbar_view_set_content(@ptrCast(toolbar_view), t_overlay);

    // AdwOverlaySplitView
    const split_view = c.adw_overlay_split_view_new();
    c.adw_toast_overlay_set_child(@ptrCast(t_overlay), split_view);

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
    // Updated tooltips to include keyboard shortcuts for better UX (Ctrl+N, Ctrl+O, etc.)
    const new_btn = c.gtk_button_new_from_icon_name("document-new-symbolic");
    c.gtk_actionable_set_action_name(@ptrCast(new_btn), "app.new");
    c.gtk_widget_set_tooltip_text(new_btn, "New Image (Ctrl+N)");
    c.adw_header_bar_pack_start(@ptrCast(header_bar), new_btn);

    const open_btn = c.gtk_button_new_from_icon_name("document-open-symbolic");
    c.gtk_actionable_set_action_name(@ptrCast(open_btn), "app.open");
    c.gtk_widget_set_tooltip_text(open_btn, "Open Image (Ctrl+O)");
    c.adw_header_bar_pack_start(@ptrCast(header_bar), open_btn);

    const save_btn = c.gtk_button_new_from_icon_name("document-save-symbolic");
    c.gtk_actionable_set_action_name(@ptrCast(save_btn), "app.save");
    c.gtk_widget_set_tooltip_text(save_btn, "Save Image (Ctrl+S)");
    c.adw_header_bar_pack_start(@ptrCast(header_bar), save_btn);

    // Undo/Redo
    const undo_btn = c.gtk_button_new_from_icon_name("edit-undo-symbolic");
    c.gtk_actionable_set_action_name(@ptrCast(undo_btn), "app.undo");
    c.gtk_widget_set_tooltip_text(undo_btn, "Undo (Ctrl+Z)");
    c.adw_header_bar_pack_start(@ptrCast(header_bar), undo_btn);

    const redo_btn = c.gtk_button_new_from_icon_name("edit-redo-symbolic");
    c.gtk_actionable_set_action_name(@ptrCast(redo_btn), "app.redo");
    c.gtk_widget_set_tooltip_text(redo_btn, "Redo (Ctrl+Y)");
    c.adw_header_bar_pack_start(@ptrCast(header_bar), redo_btn);

    // Image Menu
    const image_menu = c.g_menu_new();
    c.g_menu_append(image_menu, "_Canvas Size...", "app.canvas-size");
    c.g_menu_append(image_menu, "_Invert Colors", "app.invert-colors");
    c.g_menu_append(image_menu, "Cl_ear Image", "app.clear-image");
    c.g_menu_append(image_menu, "Flip _Horizontal", "app.flip-horizontal");
    c.g_menu_append(image_menu, "Flip _Vertical", "app.flip-vertical");
    c.g_menu_append(image_menu, "Rotate _90° CW", "app.rotate-90");
    c.g_menu_append(image_menu, "Rotate _180°", "app.rotate-180");
    c.g_menu_append(image_menu, "Rotate _270° CW", "app.rotate-270");
    c.g_menu_append(image_menu, "_Stretch...", "app.stretch");

    const image_btn = c.gtk_menu_button_new();
    c.gtk_menu_button_set_label(@ptrCast(image_btn), "_Image");
    c.gtk_menu_button_set_use_underline(@ptrCast(image_btn), 1);
    c.gtk_menu_button_set_menu_model(@ptrCast(image_btn), @ptrCast(@alignCast(image_menu)));
    c.gtk_widget_set_tooltip_text(image_btn, "Image Operations");
    c.adw_header_bar_pack_start(@ptrCast(header_bar), image_btn);

    // Filters Menu
    const filters_menu = c.g_menu_new();
    c.g_menu_append(filters_menu, "Blur (_5px)", "app.blur-small");
    c.g_menu_append(filters_menu, "Blur (1_0px)", "app.blur-medium");
    c.g_menu_append(filters_menu, "Blur (_20px)", "app.blur-large");
    c.g_menu_append(filters_menu, "_Pixelize...", "app.pixelize");
    c.g_menu_append(filters_menu, "_Motion Blur...", "app.motion-blur");
    c.g_menu_append(filters_menu, "_Unsharp Mask...", "app.unsharp-mask");
    c.g_menu_append(filters_menu, "_Noise Reduction...", "app.noise-reduction");
    c.g_menu_append(filters_menu, "_Oilify...", "app.oilify");
    c.g_menu_append(filters_menu, "_Drop Shadow...", "app.drop-shadow");
    c.g_menu_append(filters_menu, "_Red Eye Removal...", "app.red-eye-removal");
    c.g_menu_append(filters_menu, "_Waves...", "app.waves");
    c.g_menu_append(filters_menu, "_Supernova...", "app.supernova");
    c.g_menu_append(filters_menu, "_Lighting Effects...", "app.lighting-effects");
    c.g_menu_append(filters_menu, "Split _View", "app.split-view");

    const filters_btn = c.gtk_menu_button_new();
    c.gtk_menu_button_set_label(@ptrCast(filters_btn), "_Filters");
    c.gtk_menu_button_set_use_underline(@ptrCast(filters_btn), 1);
    c.gtk_menu_button_set_menu_model(@ptrCast(filters_btn), @ptrCast(@alignCast(filters_menu)));
    c.gtk_widget_set_tooltip_text(filters_btn, "Image Filters");
    c.adw_header_bar_pack_start(@ptrCast(header_bar), filters_btn);

    // View Menu
    const view_menu = c.g_menu_new();
    c.g_menu_append(view_menu, "View _Bitmap", "app.view-bitmap");
    c.g_menu_append(view_menu, "_Overview (Thumbnail)", "app.view-thumbnail");

    const view_btn = c.gtk_menu_button_new();
    c.gtk_menu_button_set_label(@ptrCast(view_btn), "_View");
    c.gtk_menu_button_set_use_underline(@ptrCast(view_btn), 1);
    c.gtk_menu_button_set_menu_model(@ptrCast(view_btn), @ptrCast(@alignCast(view_menu)));
    c.gtk_widget_set_tooltip_text(view_btn, "View Options");
    c.adw_header_bar_pack_start(@ptrCast(header_bar), view_btn);

    // Apply Preview Button (Hidden by default, shown when preview_mode != none)
    const apply_btn = c.gtk_button_new_from_icon_name("object-select-symbolic");
    c.gtk_actionable_set_action_name(@ptrCast(apply_btn), "app.apply-preview");
    c.gtk_widget_set_tooltip_text(apply_btn, "Apply Filter");
    c.gtk_widget_set_visible(apply_btn, 0); // Hidden initially
    apply_preview_btn = apply_btn;
    c.adw_header_bar_pack_start(@ptrCast(header_bar), apply_btn);

    // Discard Preview Button
    const discard_btn = c.gtk_button_new_from_icon_name("process-stop-symbolic");
    c.gtk_actionable_set_action_name(@ptrCast(discard_btn), "app.discard-preview");
    c.gtk_widget_set_tooltip_text(discard_btn, "Discard Filter");
    c.gtk_widget_set_visible(discard_btn, 0); // Hidden initially
    discard_preview_btn = discard_btn;
    c.adw_header_bar_pack_start(@ptrCast(header_bar), discard_btn);

    // Hamburger Menu (End)
    const menu = c.g_menu_new();
    c.g_menu_append(menu, "_Command Palette...", "app.command-palette");
    c.g_menu_append(menu, "_Open Location...", "app.open-location");
    c.g_menu_append(menu, "_About Vimp", "app.about");
    c.g_menu_append(menu, "_Quit", "app.quit");

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

    // Tools Container (Vertical to hold rows)
    const tools_container = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 5);
    c.gtk_widget_set_halign(tools_container, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(sidebar), tools_container);

    var tools_row_box: ?*c.GtkWidget = null;
    var tools_in_row: usize = 0;

    const appendTool = struct {
        fn func(container: *c.GtkWidget, btn: *c.GtkWidget, row_ref: *?*c.GtkWidget, count_ref: *usize) void {
            if (row_ref.* == null or count_ref.* >= 6) {
                const row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 5);
                c.gtk_widget_set_halign(row, c.GTK_ALIGN_CENTER);
                c.gtk_box_append(@ptrCast(container), row);
                row_ref.* = row;
                count_ref.* = 0;
            }
            c.gtk_box_append(@ptrCast(row_ref.*.?), btn);
            count_ref.* += 1;
        }
    }.func;

    const createToolButton = struct {
        fn func(tool_val: *Tool, icon_data: ?[]const u8, icon_name: ?[:0]const u8, tooltip: [:0]const u8, group: ?*c.GtkToggleButton) *c.GtkWidget {
            const btn = if (group) |_| c.gtk_toggle_button_new() else c.gtk_toggle_button_new();
            if (group) |g| c.gtk_toggle_button_set_group(@ptrCast(btn), g);

            var img: *c.GtkWidget = undefined;
            if (icon_data) |data| {
                img = Assets.getIconWidget(data, 24);
            } else if (icon_name) |name| {
                img = c.gtk_image_new_from_icon_name(name);
                c.gtk_widget_set_size_request(img, 24, 24);
            } else {
                img = c.gtk_image_new_from_icon_name("image-missing-symbolic");
                c.gtk_widget_set_size_request(img, 24, 24);
            }

            c.gtk_button_set_child(@ptrCast(btn), img);
            c.gtk_widget_set_tooltip_text(btn, tooltip);

            _ = c.g_signal_connect_data(btn, "toggled", @ptrCast(&tool_toggled), tool_val, null, 0);
            return btn;
        }
    }.func;

    const createToolGroup = struct {
        fn func(
            active_tool_ref: *Tool,
            entries: []const ToolEntry,
            group: ?*c.GtkToggleButton,
        ) *c.GtkWidget {
            const btn = if (group) |_| c.gtk_toggle_button_new() else c.gtk_toggle_button_new();
            if (group) |g| c.gtk_toggle_button_set_group(@ptrCast(btn), g);

            // Set initial state
            var current_entry: ?ToolEntry = null;
            for (entries) |e| {
                if (e.tool == active_tool_ref.*) {
                    current_entry = e;
                    break;
                }
            }
            if (current_entry == null) current_entry = entries[0];

            var img: *c.GtkWidget = undefined;
            if (current_entry.?.icon_data) |data| {
                img = Assets.getIconWidget(data, 24);
            } else if (current_entry.?.icon_name) |name| {
                img = c.gtk_image_new_from_icon_name(name);
                c.gtk_widget_set_size_request(img, 24, 24);
            } else {
                img = c.gtk_image_new_from_icon_name("image-missing-symbolic");
                c.gtk_widget_set_size_request(img, 24, 24);
            }

            c.gtk_button_set_child(@ptrCast(btn), img);
            c.gtk_widget_set_tooltip_text(btn, current_entry.?.tooltip);

            _ = c.g_signal_connect_data(btn, "toggled", @ptrCast(&tool_toggled), active_tool_ref, null, 0);

            // Popover
            const popover = c.gtk_popover_new();
            const grid = c.gtk_grid_new();
            c.gtk_grid_set_row_spacing(@ptrCast(grid), 5);
            c.gtk_grid_set_column_spacing(@ptrCast(grid), 5);
            c.gtk_widget_set_margin_top(grid, 5);
            c.gtk_widget_set_margin_bottom(grid, 5);
            c.gtk_widget_set_margin_start(grid, 5);
            c.gtk_widget_set_margin_end(grid, 5);
            c.gtk_popover_set_child(@ptrCast(popover), grid);

            for (entries, 0..) |entry, i| {
                const item_btn = c.gtk_button_new();
                var item_img: *c.GtkWidget = undefined;
                if (entry.icon_data) |data| {
                    item_img = Assets.getIconWidget(data, 24);
                } else if (entry.icon_name) |name| {
                    item_img = c.gtk_image_new_from_icon_name(name);
                    c.gtk_widget_set_size_request(item_img, 24, 24);
                } else {
                    item_img = c.gtk_image_new_from_icon_name("image-missing-symbolic");
                    c.gtk_widget_set_size_request(item_img, 24, 24);
                }

                c.gtk_button_set_child(@ptrCast(item_btn), item_img);
                c.gtk_widget_set_tooltip_text(item_btn, entry.tooltip);

                const col = @as(c_int, @intCast(i % 3));
                const row = @as(c_int, @intCast(i / 3));
                c.gtk_grid_attach(@ptrCast(grid), item_btn, col, row, 1, 1);

                const ctx = std.heap.c_allocator.create(ToolGroupItemContext) catch continue;
                ctx.* = .{
                    .main_btn = btn,
                    .active_tool_ref = active_tool_ref,
                    .tool = entry.tool,
                    .icon_data = entry.icon_data,
                    .icon_name = entry.icon_name,
                    .tooltip = entry.tooltip,
                    .popover = @ptrCast(popover),
                };

                _ = c.g_signal_connect_data(item_btn, "clicked", @ptrCast(&on_group_item_clicked), ctx, @ptrCast(&destroy_tool_group_item_context), 0);
            }

            const click = c.gtk_gesture_click_new();
            c.gtk_gesture_single_set_button(@ptrCast(click), 3);
            _ = c.g_signal_connect_data(click, "pressed", @ptrCast(&on_group_right_click), popover, null, 0);
            c.gtk_widget_add_controller(btn, @ptrCast(click));

            const long_press = c.gtk_gesture_long_press_new();
            _ = c.g_signal_connect_data(long_press, "pressed", @ptrCast(&on_group_long_press), popover, null, 0);
            c.gtk_widget_add_controller(btn, @ptrCast(long_press));

            return btn;
        }
    }.func;

    // Paint Group (Brush, Pencil, Airbrush)
    const paint_entries = [_]ToolEntry{
        .{ .tool = .brush, .icon_data = Assets.brush_png, .tooltip = "Brush" },
        .{ .tool = .pencil, .icon_data = Assets.pencil_png, .tooltip = "Pencil" },
        .{ .tool = .airbrush, .icon_data = Assets.airbrush_png, .tooltip = "Airbrush" },
    };
    const paint_group_btn = createToolGroup(&active_paint_tool, &paint_entries, null);
    appendTool(tools_container, paint_group_btn, &tools_row_box, &tools_in_row);
    c.gtk_toggle_button_set_active(@ptrCast(paint_group_btn), 1);

    // Eraser
    const eraser_btn = createToolButton(&eraser_tool, Assets.eraser_png, null, "Eraser", @ptrCast(paint_group_btn));
    appendTool(tools_container, eraser_btn, &tools_row_box, &tools_in_row);

    // Bucket Fill
    const fill_btn = createToolButton(&bucket_fill_tool, Assets.bucket_png, null, "Bucket Fill", @ptrCast(paint_group_btn));
    appendTool(tools_container, fill_btn, &tools_row_box, &tools_in_row);

    // Selection Group
    const select_entries = [_]ToolEntry{
        .{ .tool = .rect_select, .icon_data = Assets.rect_select_svg, .tooltip = "Rectangle Select" },
        .{ .tool = .ellipse_select, .icon_data = Assets.ellipse_select_svg, .tooltip = "Ellipse Select" },
        .{ .tool = .lasso, .icon_data = Assets.lasso_select_svg, .tooltip = "Lasso Select" },
    };
    const select_group_btn = createToolGroup(&active_selection_tool, &select_entries, @ptrCast(paint_group_btn));
    appendTool(tools_container, select_group_btn, &tools_row_box, &tools_in_row);

    // Text Tool
    const text_btn = createToolButton(&text_tool, Assets.text_svg, null, "Text Tool", @ptrCast(paint_group_btn));
    appendTool(tools_container, text_btn, &tools_row_box, &tools_in_row);

    // Shapes Group
    const shape_entries = [_]ToolEntry{
        .{ .tool = .rect_shape, .icon_data = Assets.rect_shape_svg, .tooltip = "Rectangle Tool" },
        .{ .tool = .ellipse_shape, .icon_data = Assets.ellipse_shape_svg, .tooltip = "Ellipse Tool" },
        .{ .tool = .rounded_rect_shape, .icon_data = Assets.rounded_rect_shape_svg, .tooltip = "Rounded Rectangle Tool" },
        .{ .tool = .polygon, .icon_data = Assets.polygon_svg, .tooltip = "Polygon Tool" },
    };
    const shape_group_btn = createToolGroup(&active_shape_tool, &shape_entries, @ptrCast(paint_group_btn));
    appendTool(tools_container, shape_group_btn, &tools_row_box, &tools_in_row);

    // Unified Transform
    const transform_btn = createToolButton(&unified_transform_tool, Assets.transform_svg, null, "Unified Transform", @ptrCast(paint_group_btn));
    appendTool(tools_container, transform_btn, &tools_row_box, &tools_in_row);

    // Color Picker
    const picker_btn = createToolButton(&color_picker_tool, Assets.color_picker_svg, null, "Color Picker", @ptrCast(paint_group_btn));
    appendTool(tools_container, picker_btn, &tools_row_box, &tools_in_row);

    // Gradient Tool
    const gradient_btn = createToolButton(&gradient_tool, Assets.gradient_svg, null, "Gradient Tool", @ptrCast(paint_group_btn));
    appendTool(tools_container, gradient_btn, &tools_row_box, &tools_in_row);

    // Lines Group
    const line_entries = [_]ToolEntry{
        .{ .tool = .line, .icon_data = Assets.line_svg, .tooltip = "Line Tool (Shift to snap)" },
        .{ .tool = .curve, .icon_data = Assets.curve_svg, .tooltip = "Curve Tool (Drag Line -> Bend 1 -> Bend 2)" },
    };
    const line_group_btn = createToolGroup(&active_line_tool, &line_entries, @ptrCast(paint_group_btn));
    appendTool(tools_container, line_group_btn, &tools_row_box, &tools_in_row);

    // Separator
    c.gtk_box_append(@ptrCast(sidebar), c.gtk_separator_new(c.GTK_ORIENTATION_HORIZONTAL));

    // Color Palette (Default 28 Colors)
    const palette = ColorPalette.create(&engine, &update_color_btn_visual);
    c.gtk_box_append(@ptrCast(sidebar), palette);

    // Color Selection & Edit
    const color_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 5);
    c.gtk_widget_set_halign(color_box, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(sidebar), color_box);

    color_btn = create_color_button();
    c.gtk_box_append(@ptrCast(color_box), color_btn);

    const edit_colors_btn = c.gtk_button_new_with_mnemonic("_Edit Colors");
    _ = c.g_signal_connect_data(edit_colors_btn, "clicked", @ptrCast(&on_edit_colors_clicked), window, null, 0);
    c.gtk_box_append(@ptrCast(color_box), edit_colors_btn);

    // Tool Options Panel
    tool_options_panel = ToolOptionsPanel.create(&engine, &queue_draw);
    if (tool_options_panel) |p| {
        c.gtk_box_append(@ptrCast(sidebar), p.widget());
        p.update(current_tool);
    }

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

    // Stack
    const stack = c.gtk_stack_new();
    main_stack = stack;
    c.gtk_widget_set_vexpand(stack, 1);
    c.gtk_widget_set_hexpand(stack, 1);
    c.gtk_box_append(@ptrCast(content), stack);

    // Welcome Page
    const welcome_page = c.adw_status_page_new();
    c.adw_status_page_set_icon_name(@ptrCast(welcome_page), "camera-photo-symbolic");
    c.adw_status_page_set_title(@ptrCast(welcome_page), "Welcome to Vimp");
    c.adw_status_page_set_description(@ptrCast(welcome_page), "Create a new image or open an existing one to get started.");

    const welcome_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_halign(welcome_box, c.GTK_ALIGN_CENTER);

    const welcome_new_btn = c.gtk_button_new_with_mnemonic("_New Image");
    c.gtk_widget_add_css_class(welcome_new_btn, "pill");
    c.gtk_widget_add_css_class(welcome_new_btn, "suggested-action");
    c.gtk_actionable_set_action_name(@ptrCast(welcome_new_btn), "app.new");
    c.gtk_box_append(@ptrCast(welcome_box), welcome_new_btn);

    const welcome_open_btn = c.gtk_button_new_with_mnemonic("_Open Image");
    c.gtk_widget_add_css_class(welcome_open_btn, "pill");
    c.gtk_actionable_set_action_name(@ptrCast(welcome_open_btn), "app.open");
    c.gtk_box_append(@ptrCast(welcome_box), welcome_open_btn);

    const welcome_open_loc_btn = c.gtk_button_new_with_mnemonic("Open _Location");
    c.gtk_widget_add_css_class(welcome_open_loc_btn, "pill");
    c.gtk_actionable_set_action_name(@ptrCast(welcome_open_loc_btn), "app.open-location");
    c.gtk_box_append(@ptrCast(welcome_box), welcome_open_loc_btn);

    // Recent Label
    const recent_label = c.gtk_label_new("Recent Files");
    c.gtk_widget_set_margin_top(recent_label, 20);
    c.gtk_widget_add_css_class(recent_label, "dim-label");
    c.gtk_box_append(@ptrCast(welcome_box), recent_label);

    // Recent List
    const recent_scrolled = c.gtk_scrolled_window_new();
    c.gtk_widget_set_vexpand(recent_scrolled, 1);
    c.gtk_widget_set_size_request(recent_scrolled, 400, 250);

    const recent_list = c.gtk_list_box_new();
    c.gtk_list_box_set_selection_mode(@ptrCast(recent_list), c.GTK_SELECTION_NONE);
    c.gtk_widget_add_css_class(recent_list, "boxed-list");

    c.gtk_scrolled_window_set_child(@ptrCast(recent_scrolled), recent_list);
    c.gtk_box_append(@ptrCast(welcome_box), recent_scrolled);

    recent_list_box = recent_list;
    _ = c.g_signal_connect_data(recent_list, "row-activated", @ptrCast(&on_recent_row_activated), null, null, 0);

    refresh_recent_ui();

    c.adw_status_page_set_child(@ptrCast(welcome_page), welcome_box);
    _ = c.gtk_stack_add_named(@ptrCast(stack), welcome_page, "welcome");

    // Overlay (Canvas)
    const overlay = c.gtk_overlay_new();
    _ = c.gtk_stack_add_named(@ptrCast(stack), overlay, "canvas");

    // Drawing Area
    const area = c.gtk_drawing_area_new();
    drawing_area = area;
    c.gtk_widget_set_hexpand(area, 1);
    c.gtk_widget_set_vexpand(area, 1);
    c.gtk_drawing_area_set_draw_func(@ptrCast(area), draw_func, null, null);
    c.gtk_overlay_set_child(@ptrCast(overlay), area);

    // Init Thumbnail Context
    thumbnail_ctx = .{
        .engine = &engine,
        .view_x = &view_x,
        .view_y = &view_y,
        .view_scale = &view_scale,
        .main_drawing_area = area,
        .queue_draw_main = &queue_draw,
    };

    // OSD Widget
    const osd_revealer = c.gtk_revealer_new();
    c.gtk_widget_set_valign(osd_revealer, c.GTK_ALIGN_END);
    c.gtk_widget_set_halign(osd_revealer, c.GTK_ALIGN_CENTER);
    c.gtk_widget_set_margin_bottom(osd_revealer, 40);
    c.gtk_revealer_set_transition_type(@ptrCast(osd_revealer), c.GTK_REVEALER_TRANSITION_TYPE_CROSSFADE);

    const osd_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 0);
    c.gtk_widget_add_css_class(osd_box, "osd-box");
    c.gtk_revealer_set_child(@ptrCast(osd_revealer), osd_box);

    const osd_label = c.gtk_label_new("");
    c.gtk_box_append(@ptrCast(osd_box), osd_label);

    c.gtk_overlay_add_overlay(@ptrCast(overlay), osd_revealer);

    // Transform Action Bar
    const t_action_bar = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 10);
    transform_action_bar = t_action_bar;
    c.gtk_widget_set_visible(t_action_bar, 0);
    c.gtk_widget_set_valign(t_action_bar, c.GTK_ALIGN_START);
    c.gtk_widget_set_halign(t_action_bar, c.GTK_ALIGN_CENTER);
    c.gtk_widget_set_margin_top(t_action_bar, 20);
    c.gtk_widget_add_css_class(t_action_bar, "osd-box");

    const t_apply = c.gtk_button_new_with_mnemonic("_Apply");
    c.gtk_widget_add_css_class(t_apply, "suggested-action");
    c.gtk_widget_set_tooltip_text(t_apply, "Apply Transformation");
    c.gtk_box_append(@ptrCast(t_action_bar), t_apply);
    _ = c.g_signal_connect_data(t_apply, "clicked", @ptrCast(&transform_apply_clicked), null, null, 0);

    const t_cancel = c.gtk_button_new_with_mnemonic("_Cancel");
    c.gtk_widget_set_tooltip_text(t_cancel, "Cancel Transformation");
    c.gtk_box_append(@ptrCast(t_action_bar), t_cancel);
    _ = c.g_signal_connect_data(t_cancel, "clicked", @ptrCast(&transform_cancel_clicked), null, null, 0);

    c.gtk_overlay_add_overlay(@ptrCast(overlay), t_action_bar);

    // Store in global state
    osd_state.label = osd_label;
    osd_state.revealer = osd_revealer;

    // Drop Target
    const drop_target = c.gtk_drop_target_new(c.g_file_get_type(), c.GDK_ACTION_COPY);
    _ = c.g_signal_connect_data(drop_target, "drop", @ptrCast(&drop_func), window, null, 0);
    c.gtk_widget_add_controller(area, @ptrCast(drop_target));

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

    // Zoom Gesture
    const zoom = c.gtk_gesture_zoom_new();
    c.gtk_widget_add_controller(area, @ptrCast(zoom));
    _ = c.g_signal_connect_data(zoom, "begin", @ptrCast(&zoom_begin), null, null, 0);
    _ = c.g_signal_connect_data(zoom, "update", @ptrCast(&zoom_update), null, null, 0);

    // Refresh Layers UI initially
    refresh_layers_ui();
    refresh_undo_ui();
    update_view_mode();

    // CSS Styling
    const css_provider = c.gtk_css_provider_new();
    const css =
        \\.sidebar { background-color: shade(@theme_bg_color, 0.95); border-right: 1px solid alpha(currentColor, 0.15); padding: 10px; }
        \\.content { background-color: @theme_bg_color; }
        \\.osd-box { background-color: rgba(0, 0, 0, 0.7); color: white; border-radius: 12px; padding: 8px 16px; font-weight: bold; }
    ;
    // Note: Adwaita handles colors better, using shared variables
    c.gtk_css_provider_load_from_data(css_provider, css, -1);

    const display = c.gtk_widget_get_display(@ptrCast(window));
    c.gtk_style_context_add_provider_for_display(display, @ptrCast(css_provider), c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    c.g_object_unref(css_provider);

    c.gtk_window_present(@ptrCast(window));

    check_autosave(@ptrCast(window));
}
