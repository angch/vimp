const std = @import("std");
const c = @import("../c.zig").c;
const Engine = @import("../engine.zig").Engine;

pub fn showFullscreenPreview(parent: *c.GtkWindow, engine: *Engine) void {
    const texture = engine.getPreviewTexture(4096) catch |err| {
        std.debug.print("Failed to get preview texture: {}\n", .{err});
        return;
    };
    defer c.g_object_unref(texture);

    const window = c.gtk_window_new();
    c.gtk_window_set_transient_for(@ptrCast(window), parent);
    c.gtk_window_set_modal(@ptrCast(window), 1);
    c.gtk_window_fullscreen(@ptrCast(window));
    c.gtk_window_set_decorated(@ptrCast(window), 0);

    // Set background black using CSS
    const css_provider = c.gtk_css_provider_new();
    const css = "window { background-color: black; }";
    c.gtk_css_provider_load_from_data(css_provider, css, -1);
    const ctx = c.gtk_widget_get_style_context(@ptrCast(window));
    c.gtk_style_context_add_provider(ctx, @ptrCast(css_provider), c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    c.g_object_unref(css_provider);

    const picture = c.gtk_picture_new_for_paintable(@ptrCast(texture));
    c.gtk_picture_set_can_shrink(@ptrCast(picture), 1);
    c.gtk_picture_set_content_fit(@ptrCast(picture), c.GTK_CONTENT_FIT_CONTAIN);

    c.gtk_window_set_child(@ptrCast(window), picture);

    const click = c.gtk_gesture_click_new();
    _ = c.g_signal_connect_data(click, "pressed", @ptrCast(&on_click), window, null, 0);
    c.gtk_widget_add_controller(window, @ptrCast(click));

    const key = c.gtk_event_controller_key_new();
    _ = c.g_signal_connect_data(key, "key-pressed", @ptrCast(&on_key_pressed), window, null, 0);
    c.gtk_widget_add_controller(window, @ptrCast(key));

    c.gtk_window_present(@ptrCast(window));
}

fn on_click(_: *c.GtkGestureClick, _: c_int, _: f64, _: f64, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: *c.GtkWindow = @ptrCast(@alignCast(user_data));
    c.gtk_window_close(window);
}

fn on_key_pressed(_: *c.GtkEventControllerKey, keyval: c_uint, _: c_uint, _: c.GdkModifierType, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) c.gboolean {
    const window: *c.GtkWindow = @ptrCast(@alignCast(user_data));
    // GDK_KEY_Escape is 0xff1b
    if (keyval == 0xff1b) {
        c.gtk_window_close(window);
        return 1;
    }
    return 0;
}
