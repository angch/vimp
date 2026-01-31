const std = @import("std");
const c = @import("../c.zig").c;
const Engine = @import("../engine.zig").Engine;

// Callbacks
pub const PdfImportCallback = *const fn (user_data: ?*anyopaque, path: [:0]const u8, params: ?Engine.PdfImportParams) void;
pub const SvgImportCallback = *const fn (user_data: ?*anyopaque, path: [:0]const u8, params: ?Engine.SvgImportParams) void;

// Context structs to hold state during dialog life
const PdfDialogContext = struct {
    path: [:0]const u8,
    callback: PdfImportCallback,
    user_data: ?*anyopaque,
    ppi_spin: *c.GtkWidget,
    page_spin: *c.GtkWidget,
    all_pages_switch: *c.GtkWidget,
};

const SvgDialogContext = struct {
    path: [:0]const u8,
    callback: SvgImportCallback,
    user_data: ?*anyopaque,
    width_spin: *c.GtkWidget,
    height_spin: *c.GtkWidget,
};

// Response Handlers

fn pdf_dialog_response(dialog: *c.AdwMessageDialog, response: [*c]const u8, user_data: ?*anyopaque) callconv(.c) void {
    const ctx: *PdfDialogContext = @ptrCast(@alignCast(user_data));
    const resp_span = std.mem.span(response);

    if (std.mem.eql(u8, resp_span, "import")) {
        const ppi = c.gtk_spin_button_get_value(@ptrCast(ctx.ppi_spin));
        const page_val = c.gtk_spin_button_get_value(@ptrCast(ctx.page_spin));
        const all_pages = c.gtk_switch_get_active(@ptrCast(ctx.all_pages_switch)) != 0;

        const params = Engine.PdfImportParams{
            .ppi = ppi,
            .page = @intFromFloat(page_val),
            .all_pages = all_pages,
        };

        ctx.callback(ctx.user_data, ctx.path, params);
    } else {
        // Cancelled
        ctx.callback(ctx.user_data, ctx.path, null);
    }

    // Cleanup
    std.heap.c_allocator.free(ctx.path);
    std.heap.c_allocator.destroy(ctx);
    c.gtk_window_destroy(@ptrCast(dialog));
}

fn svg_dialog_response(dialog: *c.AdwMessageDialog, response: [*c]const u8, user_data: ?*anyopaque) callconv(.c) void {
    const ctx: *SvgDialogContext = @ptrCast(@alignCast(user_data));
    const resp_span = std.mem.span(response);

    if (std.mem.eql(u8, resp_span, "import")) {
        const w_val = c.gtk_spin_button_get_value(@ptrCast(ctx.width_spin));
        const h_val = c.gtk_spin_button_get_value(@ptrCast(ctx.height_spin));

        const params = Engine.SvgImportParams{
            .width = @intFromFloat(w_val),
            .height = @intFromFloat(h_val),
        };

        ctx.callback(ctx.user_data, ctx.path, params);
    } else {
         // Cancelled
        ctx.callback(ctx.user_data, ctx.path, null);
    }

    // Cleanup
    std.heap.c_allocator.free(ctx.path);
    std.heap.c_allocator.destroy(ctx);
    c.gtk_window_destroy(@ptrCast(dialog));
}

pub fn showPdfImportDialog(
    parent: ?*c.GtkWindow,
    path: [:0]const u8,
    callback: PdfImportCallback,
    user_data: ?*anyopaque,
) !void {
    const path_dup = try std.heap.c_allocator.dupeZ(u8, path);
    const ctx = try std.heap.c_allocator.create(PdfDialogContext);

    const dialog = c.adw_message_dialog_new(parent, "Import PDF", "Select PDF import options");

    // Content Box
    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 20);
    c.gtk_widget_set_margin_end(box, 20);

    // PPI Row
    const ppi_row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 10);
    c.gtk_box_append(@ptrCast(ppi_row), c.gtk_label_new("Resolution (PPI):"));
    const ppi_spin = c.gtk_spin_button_new_with_range(72.0, 2400.0, 1.0);
    c.gtk_spin_button_set_value(@ptrCast(ppi_spin), 300.0);
    c.gtk_box_append(@ptrCast(ppi_row), ppi_spin);
    c.gtk_box_append(@ptrCast(box), ppi_row);

    // Page Row
    const page_row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 10);
    c.gtk_box_append(@ptrCast(page_row), c.gtk_label_new("Page:"));
    const page_spin = c.gtk_spin_button_new_with_range(1.0, 10000.0, 1.0);
    c.gtk_spin_button_set_value(@ptrCast(page_spin), 1.0);
    c.gtk_box_append(@ptrCast(page_row), page_spin);
    c.gtk_box_append(@ptrCast(box), page_row);

    // All Pages Switch
    const all_row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 10);
    c.gtk_box_append(@ptrCast(all_row), c.gtk_label_new("Open all pages as layers:"));
    const all_switch = c.gtk_switch_new();
    c.gtk_box_append(@ptrCast(all_row), all_switch);
    c.gtk_box_append(@ptrCast(box), all_row);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "import", "Import");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "import");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    // Populate Context
    ctx.* = .{
        .path = path_dup,
        .callback = callback,
        .user_data = user_data,
        .ppi_spin = ppi_spin,
        .page_spin = page_spin,
        .all_pages_switch = all_switch,
    };

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&pdf_dialog_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}

pub fn showSvgImportDialog(
    parent: ?*c.GtkWindow,
    path: [:0]const u8,
    callback: SvgImportCallback,
    user_data: ?*anyopaque,
) !void {
    const path_dup = try std.heap.c_allocator.dupeZ(u8, path);
    const ctx = try std.heap.c_allocator.create(SvgDialogContext);

    const dialog = c.adw_message_dialog_new(parent, "Import SVG", "Select rasterization dimensions (0 for native)");

    // Content Box
    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 20);
    c.gtk_widget_set_margin_end(box, 20);

    // Width Row
    const w_row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 10);
    c.gtk_box_append(@ptrCast(w_row), c.gtk_label_new("Width (px):"));
    const w_spin = c.gtk_spin_button_new_with_range(0.0, 10000.0, 1.0);
    c.gtk_spin_button_set_value(@ptrCast(w_spin), 0.0);
    c.gtk_box_append(@ptrCast(w_row), w_spin);
    c.gtk_box_append(@ptrCast(box), w_row);

    // Height Row
    const h_row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 10);
    c.gtk_box_append(@ptrCast(h_row), c.gtk_label_new("Height (px):"));
    const h_spin = c.gtk_spin_button_new_with_range(0.0, 10000.0, 1.0);
    c.gtk_spin_button_set_value(@ptrCast(h_spin), 0.0);
    c.gtk_box_append(@ptrCast(h_row), h_spin);
    c.gtk_box_append(@ptrCast(box), h_row);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "import", "Import");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "import");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    // Populate Context
    ctx.* = .{
        .path = path_dup,
        .callback = callback,
        .user_data = user_data,
        .width_spin = w_spin,
        .height_spin = h_spin,
    };

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&svg_dialog_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}
