const std = @import("std");

const c = @cImport({
    @cInclude("gtk/gtk.h");
});

pub fn main() !void {
    // Create the application
    const app = c.gtk_application_new("org.vimp.app", c.G_APPLICATION_DEFAULT_FLAGS);
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
    // We pass 0 and null for argc/argv for now
    const status = c.g_application_run(@ptrCast(app), 0, null);

    // In a real app we might handle the status
    _ = status;
}

fn activate(app: *c.GtkApplication, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    _ = user_data;

    const window = c.gtk_application_window_new(app);
    c.gtk_window_set_title(@ptrCast(window), "Vimp");
    c.gtk_window_set_default_size(@ptrCast(window), 800, 600);

    const header_bar = c.gtk_header_bar_new();
    c.gtk_window_set_titlebar(@ptrCast(window), header_bar);

    c.gtk_window_present(@ptrCast(window));
}
