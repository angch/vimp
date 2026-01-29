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

    // Main layout container (Horizontal Box)
    const main_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 0);
    c.gtk_window_set_child(@ptrCast(window), main_box);

    // Sidebar (Left)
    const sidebar = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    c.gtk_widget_set_size_request(sidebar, 200, -1);
    c.gtk_widget_add_css_class(sidebar, "sidebar");
    c.gtk_box_append(@ptrCast(main_box), sidebar);

    // Main Content (Right)
    const content = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    c.gtk_widget_set_hexpand(content, 1);
    c.gtk_widget_add_css_class(content, "content");
    c.gtk_box_append(@ptrCast(main_box), content);

    // CSS Styling
    const css_provider = c.gtk_css_provider_new();
    const css =
        \\.sidebar { background-color: #e0e0e0; border-right: 1px solid #c0c0c0; }
        \\.content { background-color: #ffffff; }
    ;
    c.gtk_css_provider_load_from_data(css_provider, css, -1);

    const display = c.gtk_widget_get_display(@ptrCast(window));
    c.gtk_style_context_add_provider_for_display(display, @ptrCast(css_provider), c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    c.g_object_unref(css_provider);

    c.gtk_window_present(@ptrCast(window));
}
