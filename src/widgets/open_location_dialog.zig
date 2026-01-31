const std = @import("std");
const c = @import("../c.zig").c;

pub fn showOpenLocationDialog(
    parent: ?*c.GtkWindow,
    callback: *const fn (uri: [:0]const u8, user_data: ?*anyopaque) void,
    user_data: ?*anyopaque,
) void {
    const dialog = c.adw_message_dialog_new(
        parent,
        "Open Location",
        "Enter the URI of the image to open:",
    );

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "open", "Open");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "open");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    // Entry
    const entry = c.gtk_entry_new();
    c.gtk_editable_set_text(@ptrCast(entry), "https://");
    c.gtk_entry_set_placeholder_text(@ptrCast(entry), "https://example.com/image.png");
    c.gtk_widget_set_margin_top(entry, 10);
    c.gtk_widget_set_margin_bottom(entry, 10);
    c.gtk_widget_set_margin_start(entry, 10);
    c.gtk_widget_set_margin_end(entry, 10);

    // Activate "open" response on Enter
    c.gtk_entry_set_activates_default(@ptrCast(entry), 1);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), entry);

    const Ctx = struct {
        cb: *const fn ([:0]const u8, ?*anyopaque) void,
        ud: ?*anyopaque,
        entry: *c.GtkEntry,
    };

    const ctx = std.heap.c_allocator.create(Ctx) catch return;
    ctx.* = .{ .cb = callback, .ud = user_data, .entry = @ptrCast(entry) };

    const on_response = struct {
        fn func(d: *c.AdwMessageDialog, response: [*c]const u8, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
            const context: *Ctx = @ptrCast(@alignCast(data));
            defer std.heap.c_allocator.destroy(context);

            const resp_span = std.mem.span(response);
            if (std.mem.eql(u8, resp_span, "open")) {
                const text = c.gtk_editable_get_text(@ptrCast(context.entry));
                if (text) |t| {
                    const len = std.mem.len(t);
                    const slice = t[0..len :0];
                    context.cb(slice, context.ud);
                }
            }
            c.gtk_window_destroy(@ptrCast(d));
        }
    }.func;

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&on_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}
