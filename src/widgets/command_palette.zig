const std = @import("std");
const c = @import("../c.zig").c;

const CommandEntry = struct {
    name: [:0]const u8,
    action: [:0]const u8,
};

const commands = [_]CommandEntry{
    .{ .name = "New Image", .action = "app.new" },
    .{ .name = "Open Image", .action = "app.open" },
    .{ .name = "Open as Layers", .action = "app.open-as-layers" },
    .{ .name = "Open Location", .action = "app.open-location" },
    .{ .name = "Save Image", .action = "app.save" },
    .{ .name = "Undo", .action = "app.undo" },
    .{ .name = "Redo", .action = "app.redo" },
    .{ .name = "Invert Colors", .action = "app.invert-colors" },
    .{ .name = "Clear Image", .action = "app.clear-image" },
    .{ .name = "Flip Horizontal", .action = "app.flip-horizontal" },
    .{ .name = "Flip Vertical", .action = "app.flip-vertical" },
    .{ .name = "Rotate 90° CW", .action = "app.rotate-90" },
    .{ .name = "Rotate 180°", .action = "app.rotate-180" },
    .{ .name = "Rotate 270° CW", .action = "app.rotate-270" },
    .{ .name = "Canvas Size...", .action = "app.canvas-size" },
    .{ .name = "View Bitmap (Fullscreen)", .action = "app.view-bitmap" },
    .{ .name = "Blur (5px)", .action = "app.blur-small" },
    .{ .name = "Blur (10px)", .action = "app.blur-medium" },
    .{ .name = "Blur (20px)", .action = "app.blur-large" },
    .{ .name = "Motion Blur...", .action = "app.motion-blur" },
    .{ .name = "Toggle Split View", .action = "app.split-view" }, // Note: Toggle actions usually take a parameter, but stateful actions can be toggled by activating with no param or handling it.
    // However, split-view is stateful. Activating it might not toggle it automatically if not handled.
    // In main.zig: c.g_signal_connect_data(split_action, "change-state", ...)
    // Usually activating a stateful action without parameter requests a state change?
    // Let's assume activation toggles or we might need special handling.
    // Actually standard simple actions toggle.
    // Let's keep it.
    .{ .name = "About Vimp", .action = "app.about" },
    .{ .name = "Quit", .action = "app.quit" },
};

const Context = struct {
    app: *c.GtkApplication,
    window: *c.GtkWindow,
};

fn filter_func(row: [*c]c.GtkListBoxRow, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) c.gboolean {
    if (row == null) return 0;
    const entry: *c.GtkSearchEntry = @ptrCast(@alignCast(user_data));
    const text_c = c.gtk_editable_get_text(@ptrCast(entry));
    if (text_c == null or text_c[0] == 0) return 1; // Empty search matches all

    // Get row label
    // We packed a GtkBox with GtkLabel
    const child = c.gtk_list_box_row_get_child(row);
    if (child == null) return 0;

    // We assume the structure we built: Box -> Label is second child? Or first?
    // Let's look at build: row_box with label as child.
    // Actually we can set data on the row for easier access or iterate children.
    // Let's set the name as data on the row.
    const name_ptr = c.g_object_get_data(@ptrCast(row), "command-name");
    if (name_ptr == null) return 0;

    const name: [*c]const u8 = @ptrCast(name_ptr);

    // Case insensitive search
    // Using glib functions or Zig's. Zig's is safer.
    const name_span = std.mem.span(name);
    const text_span = std.mem.span(text_c);

    // Simple substring check (case insensitive)
    // We allocate lowercase versions
    const allocator = std.heap.c_allocator;
    const name_lower = allocator.alloc(u8, name_span.len) catch return 0;
    defer allocator.free(name_lower);
    const text_lower = allocator.alloc(u8, text_span.len) catch return 0;
    defer allocator.free(text_lower);

    for (name_span, 0..) |char, i| name_lower[i] = std.ascii.toLower(char);
    for (text_span, 0..) |char, i| text_lower[i] = std.ascii.toLower(char);

    if (std.mem.indexOf(u8, name_lower, text_lower) != null) return 1;

    return 0;
}

fn on_search_changed(entry: *c.GtkSearchEntry, list_box: *c.GtkListBox) callconv(std.builtin.CallingConvention.c) void {
    c.gtk_list_box_invalidate_filter(list_box);
    _ = entry;
}

fn on_row_activated(_: *c.GtkListBox, row: *c.GtkListBoxRow, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *Context = @ptrCast(@alignCast(user_data));

    const action_ptr = c.g_object_get_data(@ptrCast(row), "command-action");
    if (action_ptr) |a| {
        const action_name: [*c]const u8 = @ptrCast(a);

        // Split action name from potential parameter?
        // Our commands are simple "app.xyz".

        // Special case for split-view which expects a boolean state change?
        // If we just activate it, does it toggle?
        // GSimpleAction stateful: activation triggers "activate" signal, but default handler for stateful action is to toggle state if parameter matches or request state change.
        // If we pass NULL as parameter to g_action_group_activate_action...
        // Let's try activating with NULL.

        // Note: g_action_group_activate_action (GActionGroup *group, const gchar *action_name, GVariant *parameter)
        c.g_action_group_activate_action(@ptrCast(ctx.app), action_name, null);
    }

    c.gtk_window_destroy(ctx.window);
}

fn on_destroy(data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *Context = @ptrCast(@alignCast(data));
    std.heap.c_allocator.destroy(ctx);
}

fn on_escape(controller: *c.GtkEventControllerKey, keyval: c_uint, keycode: c_uint, state: c.GdkModifierType, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) c.gboolean {
    _ = controller;
    _ = keycode;
    _ = state;
    if (keyval == c.GDK_KEY_Escape) {
        const window: *c.GtkWindow = @ptrCast(@alignCast(user_data));
        c.gtk_window_close(window);
        return 1;
    }
    return 0;
}

fn on_entry_activate(entry: *c.GtkSearchEntry, list_box: *c.GtkListBox) callconv(std.builtin.CallingConvention.c) void {
    _ = entry;
    // Select first visible row and activate it
    var row = c.gtk_list_box_get_row_at_index(list_box, 0);
    var i: i32 = 0;
    while (row != null) {
        // Check visibility (filter)
        if (c.gtk_widget_get_child_visible(@ptrCast(row)) != 0) {
            c.g_signal_emit_by_name(list_box, "row-activated", row);
            return;
        }
        i += 1;
        row = c.gtk_list_box_get_row_at_index(list_box, i);
    }
}

pub fn showCommandPalette(parent: ?*c.GtkWindow, app: *c.GtkApplication) void {
    const window = c.gtk_window_new();
    c.gtk_window_set_title(@ptrCast(window), "Command Palette");
    c.gtk_window_set_modal(@ptrCast(window), 1);
    c.gtk_window_set_transient_for(@ptrCast(window), parent);
    c.gtk_window_set_default_size(@ptrCast(window), 400, 300);
    c.gtk_window_set_resizable(@ptrCast(window), 0);
    c.gtk_window_set_decorated(@ptrCast(window), 0); // Frameless

    // Create context
    const ctx = std.heap.c_allocator.create(Context) catch return;
    ctx.* = .{ .app = app, .window = @ptrCast(window) };

    // Cleanup context on destroy
    _ = c.g_signal_connect_data(window, "destroy", @ptrCast(&on_destroy), ctx, null, 0);

    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 10);
    c.gtk_widget_set_margin_end(box, 10);
    c.gtk_window_set_child(@ptrCast(window), box);

    // CSS for styling - Removed for simplicity in this iteration

    // Search Entry
    const entry = c.gtk_search_entry_new();
    c.gtk_box_append(@ptrCast(box), entry);

    // Scrolled Window
    const scrolled = c.gtk_scrolled_window_new();
    c.gtk_widget_set_vexpand(scrolled, 1);
    c.gtk_box_append(@ptrCast(box), scrolled);

    // List Box
    const list_box = c.gtk_list_box_new();
    c.gtk_list_box_set_selection_mode(@ptrCast(list_box), c.GTK_SELECTION_SINGLE);
    c.gtk_list_box_set_activate_on_single_click(@ptrCast(list_box), 1);
    c.gtk_scrolled_window_set_child(@ptrCast(scrolled), list_box);

    // Populate
    for (commands) |cmd| {
        const row = c.gtk_list_box_row_new();
        const label = c.gtk_label_new(cmd.name.ptr);
        c.gtk_widget_set_halign(label, c.GTK_ALIGN_START);
        c.gtk_widget_set_margin_start(label, 10);
        c.gtk_widget_set_margin_top(label, 8);
        c.gtk_widget_set_margin_bottom(label, 8);
        c.gtk_list_box_row_set_child(@ptrCast(row), label);

        c.g_object_set_data(@ptrCast(row), "command-name", @ptrCast(@constCast(cmd.name.ptr)));
        c.g_object_set_data(@ptrCast(row), "command-action", @ptrCast(@constCast(cmd.action.ptr)));

        c.gtk_list_box_append(@ptrCast(list_box), row);
    }

    // Filtering
    c.gtk_list_box_set_filter_func(@ptrCast(list_box), filter_func, entry, null);
    _ = c.g_signal_connect_data(entry, "search-changed", @ptrCast(&on_search_changed), list_box, null, 0);

    // Activation
    _ = c.g_signal_connect_data(list_box, "row-activated", @ptrCast(&on_row_activated), ctx, null, 0);

    // Enter key in entry activates first result
    _ = c.g_signal_connect_data(entry, "activate", @ptrCast(&on_entry_activate), list_box, null, 0);

    // Escape key
    const key_controller = c.gtk_event_controller_key_new();
    _ = c.g_signal_connect_data(key_controller, "key-pressed", @ptrCast(&on_escape), window, null, 0);
    c.gtk_widget_add_controller(@ptrCast(window), @ptrCast(key_controller));

    c.gtk_window_present(@ptrCast(window));
}
