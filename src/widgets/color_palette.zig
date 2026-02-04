const std = @import("std");
const c = @import("../c.zig").c;
const Engine = @import("../engine.zig").Engine;

pub const ColorPalette = struct {
    // 28 Colors (MS Paint Classic)
    const PaletteColor = struct { r: u8, g: u8, b: u8 };
    const colors = [_]PaletteColor{
        // Row 1
        .{ .r = 0, .g = 0, .b = 0 }, // Black
        .{ .r = 128, .g = 128, .b = 128 }, // Dark Gray
        .{ .r = 128, .g = 0, .b = 0 }, // Dark Red
        .{ .r = 128, .g = 128, .b = 0 }, // Olive
        .{ .r = 0, .g = 128, .b = 0 }, // Dark Green
        .{ .r = 0, .g = 128, .b = 128 }, // Dark Teal
        .{ .r = 0, .g = 0, .b = 128 }, // Navy
        .{ .r = 128, .g = 0, .b = 128 }, // Purple
        .{ .r = 128, .g = 128, .b = 64 }, // Wheat
        .{ .r = 0, .g = 64, .b = 64 }, // Dark Teal 2
        .{ .r = 0, .g = 128, .b = 255 }, // Blue
        .{ .r = 0, .g = 64, .b = 128 }, // Dark Blue 2
        .{ .r = 64, .g = 0, .b = 255 }, // Purple Blue
        .{ .r = 128, .g = 64, .b = 0 }, // Brown
        // Row 2
        .{ .r = 255, .g = 255, .b = 255 }, // White
        .{ .r = 192, .g = 192, .b = 192 }, // Light Gray
        .{ .r = 255, .g = 0, .b = 0 }, // Red
        .{ .r = 255, .g = 255, .b = 0 }, // Yellow
        .{ .r = 0, .g = 255, .b = 0 }, // Green
        .{ .r = 0, .g = 255, .b = 255 }, // Cyan
        .{ .r = 0, .g = 0, .b = 255 }, // Blue
        .{ .r = 255, .g = 0, .b = 255 }, // Magenta
        .{ .r = 255, .g = 255, .b = 128 }, // Light Yellow
        .{ .r = 0, .g = 255, .b = 128 }, // Light Green
        .{ .r = 128, .g = 255, .b = 255 }, // Light Cyan
        .{ .r = 128, .g = 128, .b = 255 }, // Light Blue
        .{ .r = 255, .g = 0, .b = 128 }, // Pink
        .{ .r = 255, .g = 128, .b = 64 }, // Orange
    };

    const Context = struct {
        engine: *Engine,
        update_cb: ?*const fn() void,
        color: PaletteColor,
    };

    fn on_right_click(gesture: *c.GtkGestureClick, n_press: c_int, x: f64, y: f64, user_data: ?*anyopaque) callconv(.c) void {
        _ = n_press;
        _ = x;
        _ = y;
        const ctx: *Context = @ptrCast(@alignCast(user_data));
        const button = c.gtk_gesture_single_get_current_button(@ptrCast(gesture));

        if (button == 3) { // Right Click -> BG
            ctx.engine.setBgColor(ctx.color.r, ctx.color.g, ctx.color.b, 255);
            // No UI update callback for BG yet
        }
    }

    fn on_clicked(_: *c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
        const ctx: *Context = @ptrCast(@alignCast(user_data));
        // Left Click / Keyboard -> FG
        ctx.engine.setFgColor(ctx.color.r, ctx.color.g, ctx.color.b, 255);
        if (ctx.update_cb) |cb| cb();
    }

    fn destroy_context(data: ?*anyopaque, _: ?*c.GClosure) callconv(.c) void {
        if (data) |d| {
            const ctx: *Context = @ptrCast(@alignCast(d));
            std.heap.c_allocator.destroy(ctx);
        }
    }

    pub fn create(engine: *Engine, update_cb: ?*const fn() void) *c.GtkWidget {
        const grid = c.gtk_grid_new();
        c.gtk_grid_set_row_spacing(@ptrCast(grid), 1);
        c.gtk_grid_set_column_spacing(@ptrCast(grid), 1);
        c.gtk_widget_set_halign(grid, c.GTK_ALIGN_CENTER);
        c.gtk_widget_set_margin_bottom(grid, 5);

        for (colors, 0..) |col, i| {
            const btn = c.gtk_button_new();
            c.gtk_widget_set_size_request(btn, 20, 20);
            // Remove button padding/border visuals to look like a swatch
            c.gtk_widget_add_css_class(btn, "flat");

            var css_buf: [128]u8 = undefined;
            // Use border to distinguish similar colors from background
            const css = std.fmt.bufPrintZ(&css_buf,
                "button {{ background: rgb({d},{d},{d}); min-width: 20px; min-height: 20px; padding: 0; margin: 0; border: 1px solid alpha(currentColor, 0.2); }}",
                .{col.r, col.g, col.b}
            ) catch "button { background: black; }";

            const provider = c.gtk_css_provider_new();
            c.gtk_css_provider_load_from_data(provider, css.ptr, -1);
            const ctx_style = c.gtk_widget_get_style_context(btn);
            c.gtk_style_context_add_provider(ctx_style, @ptrCast(provider), c.GTK_STYLE_PROVIDER_PRIORITY_USER);
            c.g_object_unref(provider);

            // Context
            if (std.heap.c_allocator.create(Context)) |context| {
                context.* = .{ .engine = engine, .update_cb = update_cb, .color = col };

                // Gesture - Right Click (Secondary)
                const gesture = c.gtk_gesture_click_new();
                c.gtk_gesture_single_set_button(@ptrCast(gesture), 3); // Button 3 only
                _ = c.g_signal_connect_data(@ptrCast(gesture), "pressed", @ptrCast(&on_right_click), context, null, 0);
                c.gtk_widget_add_controller(btn, @ptrCast(gesture));

                // Clicked - Left Click / Keyboard (Primary)
                // Attach destroy callback here to manage lifecycle
                _ = c.g_signal_connect_data(btn, "clicked", @ptrCast(&on_clicked), context, @ptrCast(&destroy_context), 0);

            } else |_| {
                // Allocation failed
            }

            const row: c_int = if (i < 14) 0 else 1;
            const column: c_int = @intCast(i % 14);
            c.gtk_grid_attach(@ptrCast(grid), btn, column, row, 1, 1);
        }

        return grid;
    }
};

// test "ColorPalette creation" {
//     // This test requires GTK initialization which is not available in the headless test runner.
//     // Uncomment to test in an environment with a display and gtk_init() called.
//     var engine = Engine{};
//     const cb = struct { fn f() void {} }.f;
//     const widget = ColorPalette.create(&engine, &cb);
//     _ = c.g_object_ref_sink(widget);
//     c.g_object_unref(widget);
// }
