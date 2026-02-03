const std = @import("std");
const c = @import("../c.zig").c;

const Context = struct {
    callback: *const fn (c_int, c_int, ?*anyopaque) void,
    user_data: ?*anyopaque,
    width_spin: *c.GtkWidget,
    height_spin: *c.GtkWidget,
};

pub fn showCanvasSizeDialog(
    parent: ?*c.GtkWindow,
    current_width: c_int,
    current_height: c_int,
    callback: *const fn (width: c_int, height: c_int, user_data: ?*anyopaque) void,
    user_data: ?*anyopaque,
) void {
    const dialog = c.adw_message_dialog_new(
        parent,
        "Canvas Size",
        "Adjust the canvas dimensions. This will not scale the image content.",
    );

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "_Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "apply", "_Apply");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "apply");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    // Body
    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 10);
    c.gtk_widget_set_margin_end(box, 10);

    // Grid for inputs
    const grid = c.gtk_grid_new();
    c.gtk_grid_set_row_spacing(@ptrCast(grid), 10);
    c.gtk_grid_set_column_spacing(@ptrCast(grid), 10);
    c.gtk_widget_set_halign(grid, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(box), grid);

    // Width
    const w_label = c.gtk_label_new("_Width (px):");
    c.gtk_label_set_use_underline(@ptrCast(w_label), 1);
    c.gtk_widget_set_halign(w_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), w_label, 0, 0, 1, 1);
    const width_spin = c.gtk_spin_button_new_with_range(1.0, 10000.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(w_label), width_spin);
    c.gtk_spin_button_set_value(@ptrCast(width_spin), @floatFromInt(current_width));
    c.gtk_grid_attach(@ptrCast(grid), width_spin, 1, 0, 1, 1);

    // Height
    const h_label = c.gtk_label_new("_Height (px):");
    c.gtk_label_set_use_underline(@ptrCast(h_label), 1);
    c.gtk_widget_set_halign(h_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), h_label, 0, 1, 1, 1);
    const height_spin = c.gtk_spin_button_new_with_range(1.0, 10000.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(h_label), height_spin);
    c.gtk_spin_button_set_value(@ptrCast(height_spin), @floatFromInt(current_height));
    c.gtk_grid_attach(@ptrCast(grid), height_spin, 1, 1, 1, 1);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    const ctx = std.heap.c_allocator.create(Context) catch return;
    ctx.* = .{
        .callback = callback,
        .user_data = user_data,
        .width_spin = width_spin,
        .height_spin = height_spin,
    };

    const on_response = struct {
        fn func(d: *c.AdwMessageDialog, response: [*c]const u8, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
            const context: *Context = @ptrCast(@alignCast(data));
            defer std.heap.c_allocator.destroy(context);

            const resp_span = std.mem.span(response);
            if (std.mem.eql(u8, resp_span, "apply")) {
                const w = c.gtk_spin_button_get_value_as_int(@ptrCast(context.width_spin));
                const h = c.gtk_spin_button_get_value_as_int(@ptrCast(context.height_spin));
                context.callback(w, h, context.user_data);
            }
            c.gtk_window_destroy(@ptrCast(d));
        }
    }.func;

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&on_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}
