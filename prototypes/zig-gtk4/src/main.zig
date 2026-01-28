const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});

fn draw_func(
    drawing_area: [*c]c.GtkDrawingArea,
    cr: ?*c.cairo_t,
    width: c_int,
    height: c_int,
    user_data: ?*anyopaque,
) callconv(.c) void {
    _ = drawing_area;
    _ = width;
    _ = height;
    _ = user_data;

    if (cr) |cairo_ctx| {
        // Draw a red background
        c.cairo_set_source_rgb(cairo_ctx, 0.9, 0.1, 0.1);
        c.cairo_paint(cairo_ctx);

        // Draw a blue rectangle
        c.cairo_set_source_rgb(cairo_ctx, 0.1, 0.1, 0.9);
        c.cairo_rectangle(cairo_ctx, 50, 50, 100, 100);
        c.cairo_fill(cairo_ctx);
    }
}

fn activate(app: *c.GtkApplication, user_data: ?*anyopaque) callconv(.c) void {
    _ = user_data;

    const window = c.gtk_application_window_new(app);
    c.gtk_window_set_title(@ptrCast(window), "Zig GTK4 Canvas");
    c.gtk_window_set_default_size(@ptrCast(window), 400, 300);

    const drawing_area = c.gtk_drawing_area_new();
    c.gtk_drawing_area_set_draw_func(@ptrCast(drawing_area), draw_func, null, null);
    c.gtk_window_set_child(@ptrCast(window), drawing_area);

    c.gtk_widget_show(@ptrCast(window));
}

pub fn main() !void {
    const app = c.gtk_application_new("org.gtk.zig.example", c.G_APPLICATION_DEFAULT_FLAGS);
    defer c.g_object_unref(app);

    // g_signal_connect is a C macro, so we use g_signal_connect_data
    _ = c.g_signal_connect_data(app, "activate", @ptrCast(&activate), null, null, 0);

    const status = c.g_application_run(@ptrCast(app), 0, null);
    if (status != 0) {
        std.debug.print("Application exited with status {}\n", .{status});
    }
}
