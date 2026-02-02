const std = @import("std");
const c = @import("../c.zig").c;

pub const TextDialogCallback = *const fn (user_data: ?*anyopaque, text: [:0]const u8, size: i32) void;
pub const DestroyCallback = *const fn (data: ?*anyopaque) void;

const TextDialogContext = struct {
    callback: TextDialogCallback,
    user_data: ?*anyopaque,
    destroy: ?DestroyCallback,
    entry: *c.GtkWidget,
    size_spin: *c.GtkWidget,
};

fn dialog_response(dialog: *c.AdwMessageDialog, response: [*c]const u8, user_data: ?*anyopaque) callconv(.c) void {
    const ctx: *TextDialogContext = @ptrCast(@alignCast(user_data));
    const resp_span = std.mem.span(response);

    if (std.mem.eql(u8, resp_span, "insert")) {
        const buffer = c.gtk_entry_get_buffer(@ptrCast(ctx.entry));
        const text = c.gtk_entry_buffer_get_text(buffer);
        const size = c.gtk_spin_button_get_value_as_int(@ptrCast(ctx.size_spin));

        // Construct sentinel-terminated slice
        const len = std.mem.len(text);
        const slice = text[0..len :0];

        ctx.callback(ctx.user_data, slice, @intCast(size));
    }

    if (ctx.destroy) |d| {
        d(ctx.user_data);
    }

    // Cleanup
    std.heap.c_allocator.destroy(ctx);
    c.gtk_window_destroy(@ptrCast(dialog));
}

pub fn showTextDialog(
    parent: ?*c.GtkWindow,
    initial_size: i32,
    callback: TextDialogCallback,
    user_data: ?*anyopaque,
    destroy: ?DestroyCallback,
) !void {
    const ctx = try std.heap.c_allocator.create(TextDialogContext);

    const dialog = c.adw_message_dialog_new(parent, "Insert Text", "Enter text and choose font size");

    // Content Box
    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 20);
    c.gtk_widget_set_margin_end(box, 20);

    // Text Entry
    const entry = c.gtk_entry_new();
    c.gtk_entry_set_placeholder_text(@ptrCast(entry), "Text");
    c.gtk_box_append(@ptrCast(box), entry);
    // Focus entry
    // c.gtk_widget_grab_focus(entry); // Not available in GTK4 directly? Use gtk_widget_grab_focus.

    // Size Row
    const size_row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 10);
    c.gtk_box_append(@ptrCast(size_row), c.gtk_label_new("Size (px):"));

    const size_spin = c.gtk_spin_button_new_with_range(8.0, 500.0, 1.0);
    c.gtk_spin_button_set_value(@ptrCast(size_spin), @as(f64, @floatFromInt(initial_size)));
    c.gtk_box_append(@ptrCast(size_row), size_spin);
    c.gtk_box_append(@ptrCast(box), size_row);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "insert", "Insert");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "insert");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    ctx.* = .{
        .callback = callback,
        .user_data = user_data,
        .destroy = destroy,
        .entry = entry,
        .size_spin = size_spin,
    };

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&dialog_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}
