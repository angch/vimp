const std = @import("std");
const c = @import("../c.zig").c;

const ClipboardCtx = struct {
    entry: *c.GtkEntry,
};

fn is_valid_protocol(text: []const u8) bool {
    if (text.len >= 7 and std.ascii.eqlIgnoreCase(text[0..7], "http://")) return true;
    if (text.len >= 8 and std.ascii.eqlIgnoreCase(text[0..8], "https://")) return true;
    if (text.len >= 6 and std.ascii.eqlIgnoreCase(text[0..6], "ftp://")) return true;
    if (text.len >= 6 and std.ascii.eqlIgnoreCase(text[0..6], "smb://")) return true;
    return false;
}

fn on_clipboard_text(source: ?*c.GObject, result: ?*c.GAsyncResult, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *ClipboardCtx = @ptrCast(@alignCast(user_data));
    defer std.heap.c_allocator.destroy(ctx);
    defer c.g_object_unref(ctx.entry);

    var err: ?*c.GError = null;
    const text_ptr = c.gdk_clipboard_read_text_finish(@ptrCast(source), result, &err);

    if (text_ptr) |t| {
        const text = std.mem.span(t);
        // Check protocol
        if (is_valid_protocol(text)) {
            // Even if widget is destroyed (but alive via ref), set_text is safe-ish.
            // Ideally we check gtk_widget_in_destruction(entry) but this is usually fine.
            c.gtk_editable_set_text(@ptrCast(ctx.entry), t);
        }
        c.g_free(t);
    } else {
        if (err) |e| {
            c.g_error_free(e);
        }
    }
}

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

    // Clipboard detection
    const display = c.gdk_display_get_default();
    if (display) |d| {
        const clipboard = c.gdk_display_get_clipboard(d);
        // Create context
        if (std.heap.c_allocator.create(ClipboardCtx)) |cp_ctx| {
            cp_ctx.* = .{ .entry = @ptrCast(entry) };
            c.g_object_ref(entry);
            c.gdk_clipboard_read_text_async(clipboard, null, @ptrCast(&on_clipboard_text), cp_ctx);
        } else |_| {}
    }

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

test "is_valid_protocol" {
    try std.testing.expect(is_valid_protocol("https://example.com"));
    try std.testing.expect(is_valid_protocol("HTTP://EXAMPLE.COM"));
    try std.testing.expect(is_valid_protocol("ftp://server"));
    try std.testing.expect(is_valid_protocol("Smb://Server/Share"));
    try std.testing.expect(!is_valid_protocol("file:///local"));
    try std.testing.expect(!is_valid_protocol("random text"));
}
