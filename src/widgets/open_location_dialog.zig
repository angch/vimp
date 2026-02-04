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

fn getValidUrl(text: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, text, &std.ascii.whitespace);
    if (is_valid_protocol(trimmed)) {
        return trimmed;
    }
    return null;
}

fn on_clipboard_text(source: ?*c.GObject, result: ?*c.GAsyncResult, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *ClipboardCtx = @ptrCast(@alignCast(user_data));
    defer std.heap.c_allocator.destroy(ctx);
    defer c.g_object_unref(ctx.entry);

    var err: ?*c.GError = null;
    const text_ptr = c.gdk_clipboard_read_text_finish(@ptrCast(source), result, &err);

    if (text_ptr) |t| {
        const text = std.mem.span(t);
        // Check protocol and trim
        if (getValidUrl(text)) |trimmed| {
            // Even if widget is destroyed (but alive via ref), set_text is safe-ish.
            // We need a null-terminated string for gtk_editable_set_text
            // Note: trimmed is a slice of text (which points to t), but t is null-terminated.
            // If we trimmed only leading whitespace, we could use trimmed.ptr.
            // But if we trimmed trailing, trimmed.ptr is not null-terminated at the end of trimmed.
            // So we must allocate.
            if (std.fmt.allocPrintSentinel(std.heap.c_allocator, "{s}", .{trimmed}, 0)) |z_text| {
                defer std.heap.c_allocator.free(z_text);
                c.gtk_editable_set_text(@ptrCast(ctx.entry), z_text.ptr);
            } else |_| {}
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

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "_Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "open", "_Open");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "open");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    // Body
    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 10);
    c.gtk_widget_set_margin_end(box, 10);

    const label = c.gtk_label_new_with_mnemonic("_Location:");
    c.gtk_widget_set_halign(label, c.GTK_ALIGN_START);
    c.gtk_box_append(@ptrCast(box), label);

    // Entry
    const entry = c.gtk_entry_new();
    c.gtk_editable_set_text(@ptrCast(entry), "https://");
    c.gtk_entry_set_placeholder_text(@ptrCast(entry), "https://example.com/image.png");

    c.gtk_label_set_mnemonic_widget(@ptrCast(label), entry);
    c.gtk_box_append(@ptrCast(box), entry);

    // Activate "open" response on Enter
    c.gtk_entry_set_activates_default(@ptrCast(entry), 1);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    // Clipboard detection
    const display = c.gdk_display_get_default();
    if (display) |d| {
        const clipboard = c.gdk_display_get_clipboard(d);
        // Create context
        if (std.heap.c_allocator.create(ClipboardCtx)) |cp_ctx| {
            cp_ctx.* = .{ .entry = @ptrCast(entry) };
            _ = c.g_object_ref(entry);
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

test "getValidUrl" {
    // Valid
    try std.testing.expectEqualStrings("https://example.com", getValidUrl("https://example.com").?);
    try std.testing.expectEqualStrings("http://example.com", getValidUrl("http://example.com").?);

    // Trim
    try std.testing.expectEqualStrings("https://example.com", getValidUrl("  https://example.com  ").?);
    try std.testing.expectEqualStrings("ftp://server", getValidUrl("\tftp://server\n").?);

    // Invalid
    try std.testing.expect(getValidUrl("example.com") == null); // Missing protocol
    try std.testing.expect(getValidUrl("file:///tmp") == null);
    try std.testing.expect(getValidUrl("") == null);
    try std.testing.expect(getValidUrl("   ") == null);
}
