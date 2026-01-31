const std = @import("std");
const c = @import("../c.zig").c;
const Engine = @import("../engine.zig").Engine;

// Callbacks
pub const PdfImportCallback = *const fn (user_data: ?*anyopaque, path: [:0]const u8, params: ?Engine.PdfImportParams) void;
pub const SvgImportCallback = *const fn (user_data: ?*anyopaque, path: [:0]const u8, params: ?Engine.SvgImportParams) void;

// Helper to create texture from GeglBuffer
fn createTextureFromBuffer(buf: *c.GeglBuffer) ?*c.GdkTexture {
    const extent = c.gegl_buffer_get_extent(buf);
    const w = extent.*.width;
    const h = extent.*.height;
    const stride = w * 4;
    const size: usize = @intCast(w * h * 4);

    const data = std.heap.c_allocator.alloc(u8, size) catch return null;

    const format = c.babl_format("R'G'B'A u8");
    c.gegl_buffer_get(buf, extent, 1.0, format, data.ptr, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);

    const bytes = c.g_bytes_new_take(data.ptr, size);
    defer c.g_bytes_unref(bytes);

    // Using GDK_MEMORY_R8G8B8A8 (Non-premultiplied sRGB with Alpha)
    const texture = c.gdk_memory_texture_new(w, h, c.GDK_MEMORY_R8G8B8A8, bytes, @intCast(stride));
    return texture;
}

const PdfDialogContext = struct {
    path: [:0]const u8,
    callback: PdfImportCallback,
    user_data: ?*anyopaque,
    ppi_spin: *c.GtkWidget,
    flowbox: *c.GtkFlowBox,
    split_pages_check: *c.GtkWidget,
};

const SvgDialogContext = struct {
    path: [:0]const u8,
    callback: SvgImportCallback,
    user_data: ?*anyopaque,
    width_spin: *c.GtkWidget,
    height_spin: *c.GtkWidget,
    paths_check: *c.GtkWidget,
};

// Response Handlers

fn pdf_dialog_response(dialog: *c.AdwMessageDialog, response: [*c]const u8, user_data: ?*anyopaque) callconv(.c) void {
    const ctx: *PdfDialogContext = @ptrCast(@alignCast(user_data));
    const resp_span = std.mem.span(response);

    if (std.mem.eql(u8, resp_span, "import")) {
        const ppi = c.gtk_spin_button_get_value(@ptrCast(ctx.ppi_spin));
        const split_pages = c.gtk_check_button_get_active(@ptrCast(ctx.split_pages_check)) != 0;

        var pages = std.ArrayList(i32){};
        defer pages.deinit(std.heap.c_allocator);

        const selection = c.gtk_flow_box_get_selected_children(ctx.flowbox);
        if (selection) |list| {
             var l = list;
             while (l != null) {
                 const child: *c.GtkFlowBoxChild = @ptrCast(@alignCast(l.*.data));
                 const widget = c.gtk_flow_box_child_get_child(child);
                 const page_ptr = c.g_object_get_data(@ptrCast(widget), "page-num");
                 if (page_ptr) |p| {
                     const page_num: i32 = @intCast(@intFromPtr(p));
                     pages.append(std.heap.c_allocator, page_num) catch {};
                 }
                 l = l.*.next;
             }
             c.g_list_free(list);
        }

        if (pages.items.len == 0) {
             pages.append(std.heap.c_allocator, 1) catch {};
        }

        const params = Engine.PdfImportParams{
            .ppi = ppi,
            .pages = pages.items,
            .split_pages = split_pages,
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
        const import_paths = c.gtk_check_button_get_active(@ptrCast(ctx.paths_check)) != 0;

        const params = Engine.SvgImportParams{
            .width = @intFromFloat(w_val),
            .height = @intFromFloat(h_val),
            .import_paths = import_paths,
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

fn select_all_clicked(_: *c.GtkButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const flowbox: *c.GtkFlowBox = @ptrCast(@alignCast(user_data));
    c.gtk_flow_box_select_all(flowbox);
}

fn select_none_clicked(_: *c.GtkButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const flowbox: *c.GtkFlowBox = @ptrCast(@alignCast(user_data));
    c.gtk_flow_box_unselect_all(flowbox);
}

pub fn showPdfImportDialog(
    parent: ?*c.GtkWindow,
    engine: *Engine,
    path: [:0]const u8,
    callback: PdfImportCallback,
    user_data: ?*anyopaque,
) !void {
    const path_dup = try std.heap.c_allocator.dupeZ(u8, path);
    const ctx = try std.heap.c_allocator.create(PdfDialogContext);

    const dialog = c.adw_message_dialog_new(parent, "Import PDF", "Select pages to import");

    const total_pages = engine.getPdfPageCount(path) catch 0;

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

    // Split Pages Toggle
    const split_pages_check = c.gtk_check_button_new_with_label("Open pages as separate images");
    c.gtk_check_button_set_active(@ptrCast(split_pages_check), 0); // Default false
    c.gtk_box_append(@ptrCast(box), split_pages_check);

    // FlowBox for Thumbnails
    const flowbox = c.gtk_flow_box_new();
    c.gtk_flow_box_set_selection_mode(@ptrCast(flowbox), c.GTK_SELECTION_MULTIPLE);
    c.gtk_flow_box_set_min_children_per_line(@ptrCast(flowbox), 3);
    c.gtk_flow_box_set_max_children_per_line(@ptrCast(flowbox), 6);
    c.gtk_widget_set_valign(flowbox, c.GTK_ALIGN_START);

    const scrolled = c.gtk_scrolled_window_new();
    c.gtk_scrolled_window_set_child(@ptrCast(scrolled), flowbox);
    c.gtk_widget_set_vexpand(scrolled, 1);
    c.gtk_widget_set_size_request(scrolled, 500, 300);

    c.gtk_box_append(@ptrCast(box), scrolled);

    // Selection Buttons
    const btn_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 10);
    c.gtk_widget_set_halign(btn_box, c.GTK_ALIGN_CENTER);

    const select_all_btn = c.gtk_button_new_with_label("Select All");
    _ = c.g_signal_connect_data(select_all_btn, "clicked", @ptrCast(&select_all_clicked), flowbox, null, 0);
    c.gtk_box_append(@ptrCast(btn_box), select_all_btn);

    const select_none_btn = c.gtk_button_new_with_label("Clear Selection");
    _ = c.g_signal_connect_data(select_none_btn, "clicked", @ptrCast(&select_none_clicked), flowbox, null, 0);
    c.gtk_box_append(@ptrCast(btn_box), select_none_btn);

    c.gtk_box_append(@ptrCast(box), btn_box);

    // Populate Thumbnails
    var page: i32 = 1;
    // Limit total pages to prevent freeze if huge PDF?
    const max_preview_pages = 50;
    const loop_limit = if (total_pages > max_preview_pages) max_preview_pages else total_pages;

    while (page <= loop_limit) : (page += 1) {
        if (engine.getPdfThumbnail(path, page, 128)) |buf| {
            defer c.g_object_unref(buf);
            if (createTextureFromBuffer(buf)) |texture| {
                const item_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 5);
                c.gtk_widget_set_margin_top(item_box, 5);
                c.gtk_widget_set_margin_bottom(item_box, 5);
                c.gtk_widget_set_margin_start(item_box, 5);
                c.gtk_widget_set_margin_end(item_box, 5);

                const img = c.gtk_image_new_from_paintable(@ptrCast(texture));
                c.g_object_unref(texture);

                c.gtk_box_append(@ptrCast(item_box), img);

                var label_buf: [32]u8 = undefined;
                const label_txt = std.fmt.bufPrintZ(&label_buf, "Page {d}", .{page}) catch "Page";
                const label = c.gtk_label_new(label_txt.ptr);
                c.gtk_box_append(@ptrCast(item_box), label);

                c.gtk_flow_box_append(@ptrCast(flowbox), item_box);
                c.g_object_set_data(@ptrCast(item_box), "page-num", @ptrFromInt(@as(usize, @intCast(page))));
            }
        } else |_| {}
    }

    if (total_pages > max_preview_pages) {
        const info = c.gtk_label_new("Preview limited to 50 pages.");
        c.gtk_box_append(@ptrCast(box), info);
    }

    if (total_pages > 0) {
        const child = c.gtk_flow_box_get_child_at_index(@ptrCast(flowbox), 0);
        if (child != null) {
            c.gtk_flow_box_select_child(@ptrCast(flowbox), child);
        }
    }

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "import", "Import");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "import");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    ctx.* = .{
        .path = path_dup,
        .callback = callback,
        .user_data = user_data,
        .ppi_spin = ppi_spin,
        .flowbox = @ptrCast(flowbox),
        .split_pages_check = split_pages_check,
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

    // Import Paths Check
    const paths_check = c.gtk_check_button_new_with_label("Import paths");
    c.gtk_check_button_set_active(@ptrCast(paths_check), 0);
    c.gtk_box_append(@ptrCast(box), paths_check);

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
        .paths_check = paths_check,
    };

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&svg_dialog_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}
