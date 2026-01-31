const std = @import("std");
const c = @import("../c.zig").c;

pub const TextStyleEditor = struct {
    // State or widgets can be stored here if needed
};

// Callback stubs for the controllers
fn on_enter(controller: *c.GtkEventControllerMotion, x: f64, y: f64, user_data: ?*anyopaque) callconv(.c) void {
    _ = controller;
    _ = x;
    _ = y;
    _ = user_data;
    // Set cursor to move/fleur
}

fn on_leave(controller: *c.GtkEventControllerMotion, user_data: ?*anyopaque) callconv(.c) void {
    _ = controller;
    _ = user_data;
    // Reset cursor
}

fn on_drag_begin(gesture: *c.GtkGestureDrag, x: f64, y: f64, user_data: ?*anyopaque) callconv(.c) void {
    _ = gesture;
    _ = x;
    _ = y;
    _ = user_data;
    // Start drag
}

fn on_drag_update(gesture: *c.GtkGestureDrag, offset_x: f64, offset_y: f64, user_data: ?*anyopaque) callconv(.c) void {
    _ = gesture;
    _ = offset_x;
    _ = offset_y;
    _ = user_data;
    // Update position
}

fn on_drag_end(gesture: *c.GtkGestureDrag, offset_x: f64, offset_y: f64, user_data: ?*anyopaque) callconv(.c) void {
    _ = gesture;
    _ = offset_x;
    _ = offset_y;
    _ = user_data;
    // End drag
}

/// Creates a Drag-and-Drop handle for the text style editor.
/// In GTK4, GtkEventBox is deprecated. We use GtkBox and attach GtkEventControllers.
pub fn createDndHandle() *c.GtkWidget {
    // Create a GtkBox instead of GtkEventBox
    const handle = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 0);
    c.gtk_widget_set_margin_start(handle, 4);
    c.gtk_widget_set_margin_end(handle, 4);

    // Add icon (using a generic one as placeholder)
    const icon = c.gtk_image_new_from_icon_name("open-menu-symbolic");
    c.gtk_box_append(@ptrCast(handle), icon);

    // Event Controller for Motion (Enter/Leave) - Replaces enter/leave signals on EventBox
    const motion = c.gtk_event_controller_motion_new();
    c.gtk_widget_add_controller(handle, @ptrCast(motion));
    _ = c.g_signal_connect_data(motion, "enter", @ptrCast(&on_enter), null, null, 0);
    _ = c.g_signal_connect_data(motion, "leave", @ptrCast(&on_leave), null, null, 0);

    // Gesture for Dragging - Replaces Button Press/Release/Motion for dragging
    const drag = c.gtk_gesture_drag_new();
    c.gtk_widget_add_controller(handle, @ptrCast(drag));
    _ = c.g_signal_connect_data(drag, "drag-begin", @ptrCast(&on_drag_begin), null, null, 0);
    _ = c.g_signal_connect_data(drag, "drag-update", @ptrCast(&on_drag_update), null, null, 0);
    _ = c.g_signal_connect_data(drag, "drag-end", @ptrCast(&on_drag_end), null, null, 0);

    return handle;
}

test "create dnd handle compilation" {
    // This test ensures the function signature is correct and compiles.
    // We avoid running it if GTK is not initialized, but referencing it checks types.
    const func_ptr = &createDndHandle;
    _ = func_ptr;
}
