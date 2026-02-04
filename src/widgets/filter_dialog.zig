const std = @import("std");
const c = @import("../c.zig").c;
const Engine = @import("../engine.zig").Engine;

const Context = struct {
    engine: *Engine,
    length_spin: *c.GtkWidget,
    angle_spin: *c.GtkWidget,
    update_cb: *const fn () void,
};

fn on_preview_change(_: *c.GtkWidget, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *Context = @ptrCast(@alignCast(data));
    const length = c.gtk_spin_button_get_value(@ptrCast(ctx.length_spin));
    const angle = c.gtk_spin_button_get_value(@ptrCast(ctx.angle_spin));
    ctx.engine.setPreviewMotionBlur(length, angle);
    ctx.update_cb();
}

pub fn showMotionBlurDialog(
    parent: ?*c.GtkWindow,
    engine: *Engine,
    update_cb: *const fn () void,
) void {
    const dialog = c.adw_message_dialog_new(
        parent,
        "Motion Blur",
        "Adjust motion blur parameters.",
    );

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "_Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "apply", "_Apply");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "apply");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    // Body
    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 10);
    c.gtk_widget_set_margin_end(box, 10);

    // Grid
    const grid = c.gtk_grid_new();
    c.gtk_grid_set_row_spacing(@ptrCast(grid), 10);
    c.gtk_grid_set_column_spacing(@ptrCast(grid), 10);
    c.gtk_widget_set_halign(grid, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(box), grid);

    // Length
    const l_label = c.gtk_label_new_with_mnemonic("_Length (px):");
    c.gtk_widget_set_halign(l_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), l_label, 0, 0, 1, 1);
    const length_spin = c.gtk_spin_button_new_with_range(0.0, 500.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(l_label), length_spin);
    c.gtk_spin_button_set_value(@ptrCast(length_spin), 10.0);
    c.gtk_grid_attach(@ptrCast(grid), length_spin, 1, 0, 1, 1);

    // Angle
    const a_label = c.gtk_label_new_with_mnemonic("_Angle (deg):");
    c.gtk_widget_set_halign(a_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), a_label, 0, 1, 1, 1);
    const angle_spin = c.gtk_spin_button_new_with_range(0.0, 360.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(a_label), angle_spin);
    c.gtk_spin_button_set_value(@ptrCast(angle_spin), 0.0);
    c.gtk_grid_attach(@ptrCast(grid), angle_spin, 1, 1, 1, 1);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    const ctx = std.heap.c_allocator.create(Context) catch return;
    ctx.* = .{
        .engine = engine,
        .length_spin = length_spin,
        .angle_spin = angle_spin,
        .update_cb = update_cb,
    };

    // Connect preview signals
    _ = c.g_signal_connect_data(length_spin, "value-changed", @ptrCast(&on_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(angle_spin, "value-changed", @ptrCast(&on_preview_change), ctx, null, 0);

    // Initial preview
    engine.setPreviewMotionBlur(10.0, 0.0);
    update_cb();

    const on_response = struct {
        fn func(d: *c.AdwMessageDialog, response: [*c]const u8, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
            const context: *Context = @ptrCast(@alignCast(data));
            defer std.heap.c_allocator.destroy(context);

            const resp_span = std.mem.span(response);
            if (std.mem.eql(u8, resp_span, "apply")) {
                context.engine.commitPreview() catch {};
            } else {
                context.engine.cancelPreview();
            }
            context.update_cb();
            c.gtk_window_destroy(@ptrCast(d));
        }
    }.func;

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&on_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}

const LightingContext = struct {
    engine: *Engine,
    x_spin: *c.GtkWidget,
    y_spin: *c.GtkWidget,
    z_spin: *c.GtkWidget,
    intensity_scale: *c.GtkWidget,
    color_btn: *c.GtkWidget,
    update_cb: *const fn () void,
};

fn on_lighting_preview_change(_: *c.GtkWidget, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *LightingContext = @ptrCast(@alignCast(data));
    const x = c.gtk_spin_button_get_value(@ptrCast(ctx.x_spin));
    const y = c.gtk_spin_button_get_value(@ptrCast(ctx.y_spin));
    const z = c.gtk_spin_button_get_value(@ptrCast(ctx.z_spin));
    const intensity = c.gtk_range_get_value(@ptrCast(ctx.intensity_scale));

    var rgba: c.GdkRGBA = undefined;
    c.gtk_color_chooser_get_rgba(@ptrCast(ctx.color_btn), &rgba);
    const r: u8 = @intFromFloat(rgba.red * 255.0);
    const g: u8 = @intFromFloat(rgba.green * 255.0);
    const b: u8 = @intFromFloat(rgba.blue * 255.0);
    const a: u8 = @intFromFloat(rgba.alpha * 255.0);

    ctx.engine.setPreviewLighting(x, y, z, intensity, .{r, g, b, a});
    ctx.update_cb();
}

pub fn showLightingDialog(
    parent: ?*c.GtkWindow,
    engine: *Engine,
    update_cb: *const fn () void,
) void {
    const dialog = c.adw_message_dialog_new(
        parent,
        "Lighting Effects",
        "Add lighting (Point Light).",
    );

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "_Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "apply", "_Apply");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "apply");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 10);
    c.gtk_widget_set_margin_end(box, 10);

    const grid = c.gtk_grid_new();
    c.gtk_grid_set_row_spacing(@ptrCast(grid), 10);
    c.gtk_grid_set_column_spacing(@ptrCast(grid), 10);
    c.gtk_widget_set_halign(grid, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(box), grid);

    // Light X
    const x_label = c.gtk_label_new_with_mnemonic("Light _X:");
    c.gtk_widget_set_halign(x_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), x_label, 0, 0, 1, 1);
    const x_spin = c.gtk_spin_button_new_with_range(-2000.0, 10000.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(x_label), x_spin);
    const cx: f64 = @floatFromInt(@divFloor(engine.canvas_width, 2));
    c.gtk_spin_button_set_value(@ptrCast(x_spin), cx);
    c.gtk_grid_attach(@ptrCast(grid), x_spin, 1, 0, 1, 1);

    // Light Y
    const y_label = c.gtk_label_new_with_mnemonic("Light _Y:");
    c.gtk_widget_set_halign(y_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), y_label, 0, 1, 1, 1);
    const y_spin = c.gtk_spin_button_new_with_range(-2000.0, 10000.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(y_label), y_spin);
    const cy: f64 = @floatFromInt(@divFloor(engine.canvas_height, 2));
    c.gtk_spin_button_set_value(@ptrCast(y_spin), cy);
    c.gtk_grid_attach(@ptrCast(grid), y_spin, 1, 1, 1, 1);

    // Light Z
    const z_label = c.gtk_label_new_with_mnemonic("Light _Z:");
    c.gtk_widget_set_halign(z_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), z_label, 0, 2, 1, 1);
    const z_spin = c.gtk_spin_button_new_with_range(1.0, 1000.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(z_label), z_spin);
    c.gtk_spin_button_set_value(@ptrCast(z_spin), 100.0);
    c.gtk_grid_attach(@ptrCast(grid), z_spin, 1, 2, 1, 1);

    // Intensity
    const i_label = c.gtk_label_new_with_mnemonic("_Intensity:");
    c.gtk_widget_set_halign(i_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), i_label, 0, 3, 1, 1);
    const intensity_scale = c.gtk_scale_new_with_range(c.GTK_ORIENTATION_HORIZONTAL, 0.0, 5.0, 0.1);
    c.gtk_label_set_mnemonic_widget(@ptrCast(i_label), intensity_scale);
    c.gtk_widget_set_size_request(intensity_scale, 150, -1);
    c.gtk_range_set_value(@ptrCast(intensity_scale), 1.0);
    c.gtk_grid_attach(@ptrCast(grid), intensity_scale, 1, 3, 1, 1);

    // Color
    const c_label = c.gtk_label_new_with_mnemonic("_Color:");
    c.gtk_widget_set_halign(c_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), c_label, 0, 4, 1, 1);

    const color_btn = c.gtk_color_button_new();
    c.gtk_label_set_mnemonic_widget(@ptrCast(c_label), color_btn);
    const white = c.GdkRGBA{ .red = 1.0, .green = 1.0, .blue = 1.0, .alpha = 1.0 };
    c.gtk_color_chooser_set_rgba(@ptrCast(color_btn), &white);
    c.gtk_grid_attach(@ptrCast(grid), color_btn, 1, 4, 1, 1);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    const ctx = std.heap.c_allocator.create(LightingContext) catch return;
    ctx.* = .{
        .engine = engine,
        .x_spin = x_spin,
        .y_spin = y_spin,
        .z_spin = z_spin,
        .intensity_scale = intensity_scale,
        .color_btn = color_btn,
        .update_cb = update_cb,
    };

    _ = c.g_signal_connect_data(x_spin, "value-changed", @ptrCast(&on_lighting_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(y_spin, "value-changed", @ptrCast(&on_lighting_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(z_spin, "value-changed", @ptrCast(&on_lighting_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(intensity_scale, "value-changed", @ptrCast(&on_lighting_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(color_btn, "color-set", @ptrCast(&on_lighting_preview_change), ctx, null, 0);

    engine.setPreviewLighting(cx, cy, 100.0, 1.0, .{ 255, 255, 255, 255 });
    update_cb();

    const on_response = struct {
        fn func(d: *c.AdwMessageDialog, response: [*c]const u8, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
            const context: *LightingContext = @ptrCast(@alignCast(data));
            defer std.heap.c_allocator.destroy(context);

            const resp_span = std.mem.span(response);
            if (std.mem.eql(u8, resp_span, "apply")) {
                context.engine.commitPreview() catch {};
            } else {
                context.engine.cancelPreview();
            }
            context.update_cb();
            c.gtk_window_destroy(@ptrCast(d));
        }
    }.func;

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&on_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}

const UnsharpMaskContext = struct {
    engine: *Engine,
    std_dev_spin: *c.GtkWidget,
    scale_spin: *c.GtkWidget,
    update_cb: *const fn () void,
};

fn on_unsharp_mask_preview_change(_: *c.GtkWidget, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *UnsharpMaskContext = @ptrCast(@alignCast(data));
    const std_dev = c.gtk_spin_button_get_value(@ptrCast(ctx.std_dev_spin));
    const scale = c.gtk_spin_button_get_value(@ptrCast(ctx.scale_spin));
    ctx.engine.setPreviewUnsharpMask(std_dev, scale);
    ctx.update_cb();
}

pub fn showUnsharpMaskDialog(
    parent: ?*c.GtkWindow,
    engine: *Engine,
    update_cb: *const fn () void,
) void {
    const dialog = c.adw_message_dialog_new(
        parent,
        "Unsharp Mask",
        "Sharpen image.",
    );

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "_Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "apply", "_Apply");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "apply");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 10);
    c.gtk_widget_set_margin_end(box, 10);

    const grid = c.gtk_grid_new();
    c.gtk_grid_set_row_spacing(@ptrCast(grid), 10);
    c.gtk_grid_set_column_spacing(@ptrCast(grid), 10);
    c.gtk_widget_set_halign(grid, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(box), grid);

    // Std Dev
    const sd_label = c.gtk_label_new_with_mnemonic("_Radius (Std Dev):");
    c.gtk_widget_set_halign(sd_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), sd_label, 0, 0, 1, 1);
    const std_dev_spin = c.gtk_spin_button_new_with_range(0.1, 100.0, 0.1);
    c.gtk_label_set_mnemonic_widget(@ptrCast(sd_label), std_dev_spin);
    c.gtk_spin_button_set_value(@ptrCast(std_dev_spin), 1.0);
    c.gtk_grid_attach(@ptrCast(grid), std_dev_spin, 1, 0, 1, 1);

    // Scale
    const s_label = c.gtk_label_new_with_mnemonic("_Amount (Scale):");
    c.gtk_widget_set_halign(s_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), s_label, 0, 1, 1, 1);
    const scale_spin = c.gtk_spin_button_new_with_range(0.0, 10.0, 0.1);
    c.gtk_label_set_mnemonic_widget(@ptrCast(s_label), scale_spin);
    c.gtk_spin_button_set_value(@ptrCast(scale_spin), 1.0);
    c.gtk_grid_attach(@ptrCast(grid), scale_spin, 1, 1, 1, 1);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    const ctx = std.heap.c_allocator.create(UnsharpMaskContext) catch return;
    ctx.* = .{
        .engine = engine,
        .std_dev_spin = std_dev_spin,
        .scale_spin = scale_spin,
        .update_cb = update_cb,
    };

    _ = c.g_signal_connect_data(std_dev_spin, "value-changed", @ptrCast(&on_unsharp_mask_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(scale_spin, "value-changed", @ptrCast(&on_unsharp_mask_preview_change), ctx, null, 0);

    engine.setPreviewUnsharpMask(1.0, 1.0);
    update_cb();

    const on_response = struct {
        fn func(d: *c.AdwMessageDialog, response: [*c]const u8, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
            const context: *UnsharpMaskContext = @ptrCast(@alignCast(data));
            defer std.heap.c_allocator.destroy(context);

            const resp_span = std.mem.span(response);
            if (std.mem.eql(u8, resp_span, "apply")) {
                context.engine.commitPreview() catch {};
            } else {
                context.engine.cancelPreview();
            }
            context.update_cb();
            c.gtk_window_destroy(@ptrCast(d));
        }
    }.func;

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&on_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}

const NoiseReductionContext = struct {
    engine: *Engine,
    iter_spin: *c.GtkWidget,
    update_cb: *const fn () void,
};

fn on_noise_reduction_preview_change(_: *c.GtkWidget, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *NoiseReductionContext = @ptrCast(@alignCast(data));
    const val = c.gtk_spin_button_get_value_as_int(@ptrCast(ctx.iter_spin));
    ctx.engine.setPreviewNoiseReduction(@intCast(val));
    ctx.update_cb();
}

pub fn showNoiseReductionDialog(
    parent: ?*c.GtkWindow,
    engine: *Engine,
    update_cb: *const fn () void,
) void {
    const dialog = c.adw_message_dialog_new(
        parent,
        "Noise Reduction",
        "Reduce noise.",
    );

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "_Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "apply", "_Apply");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "apply");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 10);
    c.gtk_widget_set_margin_end(box, 10);

    const grid = c.gtk_grid_new();
    c.gtk_grid_set_row_spacing(@ptrCast(grid), 10);
    c.gtk_grid_set_column_spacing(@ptrCast(grid), 10);
    c.gtk_widget_set_halign(grid, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(box), grid);

    // Iterations
    const i_label = c.gtk_label_new_with_mnemonic("_Iterations:");
    c.gtk_widget_set_halign(i_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), i_label, 0, 0, 1, 1);
    const iter_spin = c.gtk_spin_button_new_with_range(1.0, 10.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(i_label), iter_spin);
    c.gtk_spin_button_set_value(@ptrCast(iter_spin), 1.0);
    c.gtk_grid_attach(@ptrCast(grid), iter_spin, 1, 0, 1, 1);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    const ctx = std.heap.c_allocator.create(NoiseReductionContext) catch return;
    ctx.* = .{
        .engine = engine,
        .iter_spin = iter_spin,
        .update_cb = update_cb,
    };

    _ = c.g_signal_connect_data(iter_spin, "value-changed", @ptrCast(&on_noise_reduction_preview_change), ctx, null, 0);

    engine.setPreviewNoiseReduction(1);
    update_cb();

    const on_response = struct {
        fn func(d: *c.AdwMessageDialog, response: [*c]const u8, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
            const context: *NoiseReductionContext = @ptrCast(@alignCast(data));
            defer std.heap.c_allocator.destroy(context);

            const resp_span = std.mem.span(response);
            if (std.mem.eql(u8, resp_span, "apply")) {
                context.engine.commitPreview() catch {};
            } else {
                context.engine.cancelPreview();
            }
            context.update_cb();
            c.gtk_window_destroy(@ptrCast(d));
        }
    }.func;

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&on_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}

const PixelizeContext = struct {
    engine: *Engine,
    size_spin: *c.GtkWidget,
    update_cb: *const fn () void,
};

fn on_pixelize_preview_change(_: *c.GtkWidget, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *PixelizeContext = @ptrCast(@alignCast(data));
    const size = c.gtk_spin_button_get_value(@ptrCast(ctx.size_spin));
    ctx.engine.setPreviewPixelize(size);
    ctx.update_cb();
}

pub fn showPixelizeDialog(
    parent: ?*c.GtkWindow,
    engine: *Engine,
    update_cb: *const fn () void,
) void {
    const dialog = c.adw_message_dialog_new(
        parent,
        "Pixelize",
        "Adjust pixel block size.",
    );

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "_Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "apply", "_Apply");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "apply");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    // Body
    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 10);
    c.gtk_widget_set_margin_end(box, 10);

    // Grid
    const grid = c.gtk_grid_new();
    c.gtk_grid_set_row_spacing(@ptrCast(grid), 10);
    c.gtk_grid_set_column_spacing(@ptrCast(grid), 10);
    c.gtk_widget_set_halign(grid, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(box), grid);

    // Size
    const l_label = c.gtk_label_new_with_mnemonic("_Block Size (px):");
    c.gtk_widget_set_halign(l_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), l_label, 0, 0, 1, 1);
    const size_spin = c.gtk_spin_button_new_with_range(2.0, 200.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(l_label), size_spin);
    c.gtk_spin_button_set_value(@ptrCast(size_spin), 10.0);
    c.gtk_grid_attach(@ptrCast(grid), size_spin, 1, 0, 1, 1);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    const ctx = std.heap.c_allocator.create(PixelizeContext) catch return;
    ctx.* = .{
        .engine = engine,
        .size_spin = size_spin,
        .update_cb = update_cb,
    };

    // Connect preview signals
    _ = c.g_signal_connect_data(size_spin, "value-changed", @ptrCast(&on_pixelize_preview_change), ctx, null, 0);

    // Initial preview
    engine.setPreviewPixelize(10.0);
    update_cb();

    const on_response = struct {
        fn func(d: *c.AdwMessageDialog, response: [*c]const u8, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
            const context: *PixelizeContext = @ptrCast(@alignCast(data));
            defer std.heap.c_allocator.destroy(context);

            const resp_span = std.mem.span(response);
            if (std.mem.eql(u8, resp_span, "apply")) {
                context.engine.commitPreview() catch {};
            } else {
                context.engine.cancelPreview();
            }
            context.update_cb();
            c.gtk_window_destroy(@ptrCast(d));
        }
    }.func;

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&on_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}

const OilifyContext = struct {
    engine: *Engine,
    radius_spin: *c.GtkWidget,
    update_cb: *const fn () void,
};

fn on_oilify_preview_change(_: *c.GtkWidget, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *OilifyContext = @ptrCast(@alignCast(data));
    const radius = c.gtk_spin_button_get_value(@ptrCast(ctx.radius_spin));
    ctx.engine.setPreviewOilify(radius);
    ctx.update_cb();
}

pub fn showOilifyDialog(
    parent: ?*c.GtkWindow,
    engine: *Engine,
    update_cb: *const fn () void,
) void {
    const dialog = c.adw_message_dialog_new(
        parent,
        "Oilify",
        "Adjust mask radius.",
    );

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "_Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "apply", "_Apply");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "apply");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    // Body
    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 10);
    c.gtk_widget_set_margin_end(box, 10);

    // Grid
    const grid = c.gtk_grid_new();
    c.gtk_grid_set_row_spacing(@ptrCast(grid), 10);
    c.gtk_grid_set_column_spacing(@ptrCast(grid), 10);
    c.gtk_widget_set_halign(grid, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(box), grid);

    // Radius
    const l_label = c.gtk_label_new_with_mnemonic("_Mask Radius:");
    c.gtk_widget_set_halign(l_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), l_label, 0, 0, 1, 1);
    const radius_spin = c.gtk_spin_button_new_with_range(1.0, 50.0, 0.5);
    c.gtk_label_set_mnemonic_widget(@ptrCast(l_label), radius_spin);
    c.gtk_spin_button_set_value(@ptrCast(radius_spin), 3.5);
    c.gtk_grid_attach(@ptrCast(grid), radius_spin, 1, 0, 1, 1);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    const ctx = std.heap.c_allocator.create(OilifyContext) catch return;
    ctx.* = .{
        .engine = engine,
        .radius_spin = radius_spin,
        .update_cb = update_cb,
    };

    // Connect preview signals
    _ = c.g_signal_connect_data(radius_spin, "value-changed", @ptrCast(&on_oilify_preview_change), ctx, null, 0);

    // Initial preview
    engine.setPreviewOilify(3.5);
    update_cb();

    const on_response = struct {
        fn func(d: *c.AdwMessageDialog, response: [*c]const u8, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
            const context: *OilifyContext = @ptrCast(@alignCast(data));
            defer std.heap.c_allocator.destroy(context);

            const resp_span = std.mem.span(response);
            if (std.mem.eql(u8, resp_span, "apply")) {
                context.engine.commitPreview() catch {};
            } else {
                context.engine.cancelPreview();
            }
            context.update_cb();
            c.gtk_window_destroy(@ptrCast(d));
        }
    }.func;

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&on_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}

const DropShadowContext = struct {
    engine: *Engine,
    x_spin: *c.GtkWidget,
    y_spin: *c.GtkWidget,
    radius_spin: *c.GtkWidget,
    opacity_scale: *c.GtkWidget,
    update_cb: *const fn () void,
};

fn on_drop_shadow_preview_change(_: *c.GtkWidget, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *DropShadowContext = @ptrCast(@alignCast(data));
    const x = c.gtk_spin_button_get_value(@ptrCast(ctx.x_spin));
    const y = c.gtk_spin_button_get_value(@ptrCast(ctx.y_spin));
    const radius = c.gtk_spin_button_get_value(@ptrCast(ctx.radius_spin));
    const opacity = c.gtk_range_get_value(@ptrCast(ctx.opacity_scale));
    ctx.engine.setPreviewDropShadow(x, y, radius, opacity);
    ctx.update_cb();
}

pub fn showDropShadowDialog(
    parent: ?*c.GtkWindow,
    engine: *Engine,
    update_cb: *const fn () void,
) void {
    const dialog = c.adw_message_dialog_new(
        parent,
        "Drop Shadow",
        "Add a drop shadow.",
    );

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "_Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "apply", "_Apply");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "apply");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    // Body
    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 10);
    c.gtk_widget_set_margin_end(box, 10);

    // Grid
    const grid = c.gtk_grid_new();
    c.gtk_grid_set_row_spacing(@ptrCast(grid), 10);
    c.gtk_grid_set_column_spacing(@ptrCast(grid), 10);
    c.gtk_widget_set_halign(grid, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(box), grid);

    // X Offset
    const x_label = c.gtk_label_new_with_mnemonic("Offset _X:");
    c.gtk_widget_set_halign(x_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), x_label, 0, 0, 1, 1);
    const x_spin = c.gtk_spin_button_new_with_range(-500.0, 500.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(x_label), x_spin);
    c.gtk_spin_button_set_value(@ptrCast(x_spin), 10.0);
    c.gtk_grid_attach(@ptrCast(grid), x_spin, 1, 0, 1, 1);

    // Y Offset
    const y_label = c.gtk_label_new_with_mnemonic("Offset _Y:");
    c.gtk_widget_set_halign(y_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), y_label, 0, 1, 1, 1);
    const y_spin = c.gtk_spin_button_new_with_range(-500.0, 500.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(y_label), y_spin);
    c.gtk_spin_button_set_value(@ptrCast(y_spin), 10.0);
    c.gtk_grid_attach(@ptrCast(grid), y_spin, 1, 1, 1, 1);

    // Radius
    const r_label = c.gtk_label_new_with_mnemonic("_Blur Radius:");
    c.gtk_widget_set_halign(r_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), r_label, 0, 2, 1, 1);
    const radius_spin = c.gtk_spin_button_new_with_range(0.0, 200.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(r_label), radius_spin);
    c.gtk_spin_button_set_value(@ptrCast(radius_spin), 10.0);
    c.gtk_grid_attach(@ptrCast(grid), radius_spin, 1, 2, 1, 1);

    // Opacity
    const o_label = c.gtk_label_new_with_mnemonic("_Opacity:");
    c.gtk_widget_set_halign(o_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), o_label, 0, 3, 1, 1);
    const opacity_scale = c.gtk_scale_new_with_range(c.GTK_ORIENTATION_HORIZONTAL, 0.0, 2.0, 0.1);
    c.gtk_label_set_mnemonic_widget(@ptrCast(o_label), opacity_scale);
    c.gtk_widget_set_size_request(opacity_scale, 150, -1);
    c.gtk_range_set_value(@ptrCast(opacity_scale), 0.5);
    c.gtk_grid_attach(@ptrCast(grid), opacity_scale, 1, 3, 1, 1);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    const ctx = std.heap.c_allocator.create(DropShadowContext) catch return;
    ctx.* = .{
        .engine = engine,
        .x_spin = x_spin,
        .y_spin = y_spin,
        .radius_spin = radius_spin,
        .opacity_scale = opacity_scale,
        .update_cb = update_cb,
    };

    // Connect preview signals
    _ = c.g_signal_connect_data(x_spin, "value-changed", @ptrCast(&on_drop_shadow_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(y_spin, "value-changed", @ptrCast(&on_drop_shadow_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(radius_spin, "value-changed", @ptrCast(&on_drop_shadow_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(opacity_scale, "value-changed", @ptrCast(&on_drop_shadow_preview_change), ctx, null, 0);

    // Initial preview
    engine.setPreviewDropShadow(10.0, 10.0, 10.0, 0.5);
    update_cb();

    const on_response = struct {
        fn func(d: *c.AdwMessageDialog, response: [*c]const u8, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
            const context: *DropShadowContext = @ptrCast(@alignCast(data));
            defer std.heap.c_allocator.destroy(context);

            const resp_span = std.mem.span(response);
            if (std.mem.eql(u8, resp_span, "apply")) {
                context.engine.commitPreview() catch {};
            } else {
                context.engine.cancelPreview();
            }
            context.update_cb();
            c.gtk_window_destroy(@ptrCast(d));
        }
    }.func;

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&on_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}

const RedEyeContext = struct {
    engine: *Engine,
    threshold_scale: *c.GtkWidget,
    update_cb: *const fn () void,
};

fn on_red_eye_preview_change(_: *c.GtkWidget, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *RedEyeContext = @ptrCast(@alignCast(data));
    const threshold = c.gtk_range_get_value(@ptrCast(ctx.threshold_scale));
    ctx.engine.setPreviewRedEyeRemoval(threshold);
    ctx.update_cb();
}

pub fn showRedEyeRemovalDialog(
    parent: ?*c.GtkWindow,
    engine: *Engine,
    update_cb: *const fn () void,
) void {
    const dialog = c.adw_message_dialog_new(
        parent,
        "Red Eye Removal",
        "Adjust threshold.",
    );

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "_Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "apply", "_Apply");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "apply");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    // Body
    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 10);
    c.gtk_widget_set_margin_end(box, 10);

    // Grid
    const grid = c.gtk_grid_new();
    c.gtk_grid_set_row_spacing(@ptrCast(grid), 10);
    c.gtk_grid_set_column_spacing(@ptrCast(grid), 10);
    c.gtk_widget_set_halign(grid, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(box), grid);

    // Threshold
    const t_label = c.gtk_label_new_with_mnemonic("_Threshold:");
    c.gtk_widget_set_halign(t_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), t_label, 0, 0, 1, 1);
    const threshold_scale = c.gtk_scale_new_with_range(c.GTK_ORIENTATION_HORIZONTAL, 0.0, 1.0, 0.01);
    c.gtk_label_set_mnemonic_widget(@ptrCast(t_label), threshold_scale);
    c.gtk_widget_set_size_request(threshold_scale, 150, -1);
    c.gtk_range_set_value(@ptrCast(threshold_scale), 0.4);
    c.gtk_grid_attach(@ptrCast(grid), threshold_scale, 1, 0, 1, 1);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    const ctx = std.heap.c_allocator.create(RedEyeContext) catch return;
    ctx.* = .{
        .engine = engine,
        .threshold_scale = threshold_scale,
        .update_cb = update_cb,
    };

    // Connect preview signals
    _ = c.g_signal_connect_data(threshold_scale, "value-changed", @ptrCast(&on_red_eye_preview_change), ctx, null, 0);

    // Initial preview
    engine.setPreviewRedEyeRemoval(0.4);
    update_cb();

    const on_response = struct {
        fn func(d: *c.AdwMessageDialog, response: [*c]const u8, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
            const context: *RedEyeContext = @ptrCast(@alignCast(data));
            defer std.heap.c_allocator.destroy(context);

            const resp_span = std.mem.span(response);
            if (std.mem.eql(u8, resp_span, "apply")) {
                context.engine.commitPreview() catch {};
            } else {
                context.engine.cancelPreview();
            }
            context.update_cb();
            c.gtk_window_destroy(@ptrCast(d));
        }
    }.func;

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&on_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}

const WavesContext = struct {
    engine: *Engine,
    amplitude_spin: *c.GtkWidget,
    phase_spin: *c.GtkWidget,
    wavelength_spin: *c.GtkWidget,
    update_cb: *const fn () void,
};

fn on_waves_preview_change(_: *c.GtkWidget, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *WavesContext = @ptrCast(@alignCast(data));
    const amplitude = c.gtk_spin_button_get_value(@ptrCast(ctx.amplitude_spin));
    const phase = c.gtk_spin_button_get_value(@ptrCast(ctx.phase_spin));
    const wavelength = c.gtk_spin_button_get_value(@ptrCast(ctx.wavelength_spin));
    ctx.engine.setPreviewWaves(amplitude, phase, wavelength);
    ctx.update_cb();
}

pub fn showWavesDialog(
    parent: ?*c.GtkWindow,
    engine: *Engine,
    update_cb: *const fn () void,
) void {
    const dialog = c.adw_message_dialog_new(
        parent,
        "Waves",
        "Add concentric waves.",
    );

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "_Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "apply", "_Apply");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "apply");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 10);
    c.gtk_widget_set_margin_end(box, 10);

    const grid = c.gtk_grid_new();
    c.gtk_grid_set_row_spacing(@ptrCast(grid), 10);
    c.gtk_grid_set_column_spacing(@ptrCast(grid), 10);
    c.gtk_widget_set_halign(grid, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(box), grid);

    // Amplitude
    const a_label = c.gtk_label_new_with_mnemonic("_Amplitude:");
    c.gtk_widget_set_halign(a_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), a_label, 0, 0, 1, 1);
    const amplitude_spin = c.gtk_spin_button_new_with_range(0.0, 100.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(a_label), amplitude_spin);
    c.gtk_spin_button_set_value(@ptrCast(amplitude_spin), 30.0);
    c.gtk_grid_attach(@ptrCast(grid), amplitude_spin, 1, 0, 1, 1);

    // Phase
    const p_label = c.gtk_label_new_with_mnemonic("_Phase:");
    c.gtk_widget_set_halign(p_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), p_label, 0, 1, 1, 1);
    const phase_spin = c.gtk_spin_button_new_with_range(0.0, 360.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(p_label), phase_spin);
    c.gtk_spin_button_set_value(@ptrCast(phase_spin), 0.0);
    c.gtk_grid_attach(@ptrCast(grid), phase_spin, 1, 1, 1, 1);

    // Wavelength
    const w_label = c.gtk_label_new_with_mnemonic("_Wavelength:");
    c.gtk_widget_set_halign(w_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), w_label, 0, 2, 1, 1);
    const wavelength_spin = c.gtk_spin_button_new_with_range(0.1, 100.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(w_label), wavelength_spin);
    c.gtk_spin_button_set_value(@ptrCast(wavelength_spin), 20.0);
    c.gtk_grid_attach(@ptrCast(grid), wavelength_spin, 1, 2, 1, 1);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    const ctx = std.heap.c_allocator.create(WavesContext) catch return;
    ctx.* = .{
        .engine = engine,
        .amplitude_spin = amplitude_spin,
        .phase_spin = phase_spin,
        .wavelength_spin = wavelength_spin,
        .update_cb = update_cb,
    };

    _ = c.g_signal_connect_data(amplitude_spin, "value-changed", @ptrCast(&on_waves_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(phase_spin, "value-changed", @ptrCast(&on_waves_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(wavelength_spin, "value-changed", @ptrCast(&on_waves_preview_change), ctx, null, 0);

    engine.setPreviewWaves(30.0, 0.0, 20.0);
    update_cb();

    const on_response = struct {
        fn func(d: *c.AdwMessageDialog, response: [*c]const u8, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
            const context: *WavesContext = @ptrCast(@alignCast(data));
            defer std.heap.c_allocator.destroy(context);

            const resp_span = std.mem.span(response);
            if (std.mem.eql(u8, resp_span, "apply")) {
                context.engine.commitPreview() catch {};
            } else {
                context.engine.cancelPreview();
            }
            context.update_cb();
            c.gtk_window_destroy(@ptrCast(d));
        }
    }.func;

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&on_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}

const SupernovaContext = struct {
    engine: *Engine,
    x_spin: *c.GtkWidget,
    y_spin: *c.GtkWidget,
    radius_spin: *c.GtkWidget,
    spokes_spin: *c.GtkWidget,
    color_btn: *c.GtkWidget,
    update_cb: *const fn () void,
};

fn on_supernova_preview_change(_: *c.GtkWidget, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *SupernovaContext = @ptrCast(@alignCast(data));
    const x = c.gtk_spin_button_get_value(@ptrCast(ctx.x_spin));
    const y = c.gtk_spin_button_get_value(@ptrCast(ctx.y_spin));
    const radius = c.gtk_spin_button_get_value(@ptrCast(ctx.radius_spin));
    const spokes_val = c.gtk_spin_button_get_value_as_int(@ptrCast(ctx.spokes_spin));

    var rgba: c.GdkRGBA = undefined;
    c.gtk_color_chooser_get_rgba(@ptrCast(ctx.color_btn), &rgba);
    const r: u8 = @intFromFloat(rgba.red * 255.0);
    const g: u8 = @intFromFloat(rgba.green * 255.0);
    const b: u8 = @intFromFloat(rgba.blue * 255.0);
    const a: u8 = @intFromFloat(rgba.alpha * 255.0);

    ctx.engine.setPreviewSupernova(x, y, radius, @intCast(spokes_val), .{r, g, b, a});
    ctx.update_cb();
}

pub fn showSupernovaDialog(
    parent: ?*c.GtkWindow,
    engine: *Engine,
    update_cb: *const fn () void,
) void {
    const dialog = c.adw_message_dialog_new(
        parent,
        "Supernova",
        "Add a supernova flare.",
    );

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "_Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "apply", "_Apply");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "apply");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 10);
    c.gtk_widget_set_margin_end(box, 10);

    const grid = c.gtk_grid_new();
    c.gtk_grid_set_row_spacing(@ptrCast(grid), 10);
    c.gtk_grid_set_column_spacing(@ptrCast(grid), 10);
    c.gtk_widget_set_halign(grid, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(box), grid);

    // Center X
    const x_label = c.gtk_label_new_with_mnemonic("Center _X (px):");
    c.gtk_widget_set_halign(x_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), x_label, 0, 0, 1, 1);
    const x_spin = c.gtk_spin_button_new_with_range(-2000.0, 10000.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(x_label), x_spin);
    const cx: f64 = @floatFromInt(@divFloor(engine.canvas_width, 2));
    c.gtk_spin_button_set_value(@ptrCast(x_spin), cx);
    c.gtk_grid_attach(@ptrCast(grid), x_spin, 1, 0, 1, 1);

    // Center Y
    const y_label = c.gtk_label_new_with_mnemonic("Center _Y (px):");
    c.gtk_widget_set_halign(y_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), y_label, 0, 1, 1, 1);
    const y_spin = c.gtk_spin_button_new_with_range(-2000.0, 10000.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(y_label), y_spin);
    const cy: f64 = @floatFromInt(@divFloor(engine.canvas_height, 2));
    c.gtk_spin_button_set_value(@ptrCast(y_spin), cy);
    c.gtk_grid_attach(@ptrCast(grid), y_spin, 1, 1, 1, 1);

    // Radius
    const r_label = c.gtk_label_new_with_mnemonic("_Radius:");
    c.gtk_widget_set_halign(r_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), r_label, 0, 2, 1, 1);
    const radius_spin = c.gtk_spin_button_new_with_range(1.0, 1000.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(r_label), radius_spin);
    c.gtk_spin_button_set_value(@ptrCast(radius_spin), 20.0);
    c.gtk_grid_attach(@ptrCast(grid), radius_spin, 1, 2, 1, 1);

    // Spokes
    const s_label = c.gtk_label_new_with_mnemonic("_Spokes:");
    c.gtk_widget_set_halign(s_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), s_label, 0, 3, 1, 1);
    const spokes_spin = c.gtk_spin_button_new_with_range(1.0, 1000.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(s_label), spokes_spin);
    c.gtk_spin_button_set_value(@ptrCast(spokes_spin), 100.0);
    c.gtk_grid_attach(@ptrCast(grid), spokes_spin, 1, 3, 1, 1);

    // Color
    const c_label = c.gtk_label_new_with_mnemonic("_Color:");
    c.gtk_widget_set_halign(c_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), c_label, 0, 4, 1, 1);

    const color_btn = c.gtk_color_button_new();
    c.gtk_label_set_mnemonic_widget(@ptrCast(c_label), color_btn);
    const blue = c.GdkRGBA{ .red = 0.4, .green = 0.4, .blue = 1.0, .alpha = 1.0 };
    c.gtk_color_chooser_set_rgba(@ptrCast(color_btn), &blue);
    c.gtk_grid_attach(@ptrCast(grid), color_btn, 1, 4, 1, 1);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    const ctx = std.heap.c_allocator.create(SupernovaContext) catch return;
    ctx.* = .{
        .engine = engine,
        .x_spin = x_spin,
        .y_spin = y_spin,
        .radius_spin = radius_spin,
        .spokes_spin = spokes_spin,
        .color_btn = color_btn,
        .update_cb = update_cb,
    };

    _ = c.g_signal_connect_data(x_spin, "value-changed", @ptrCast(&on_supernova_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(y_spin, "value-changed", @ptrCast(&on_supernova_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(radius_spin, "value-changed", @ptrCast(&on_supernova_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(spokes_spin, "value-changed", @ptrCast(&on_supernova_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(color_btn, "color-set", @ptrCast(&on_supernova_preview_change), ctx, null, 0);

    engine.setPreviewSupernova(cx, cy, 20.0, 100, .{ 102, 102, 255, 255 });
    update_cb();

    const on_response = struct {
        fn func(d: *c.AdwMessageDialog, response: [*c]const u8, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
            const context: *SupernovaContext = @ptrCast(@alignCast(data));
            defer std.heap.c_allocator.destroy(context);

            const resp_span = std.mem.span(response);
            if (std.mem.eql(u8, resp_span, "apply")) {
                context.engine.commitPreview() catch {};
            } else {
                context.engine.cancelPreview();
            }
            context.update_cb();
            c.gtk_window_destroy(@ptrCast(d));
        }
    }.func;

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&on_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}

const StretchSkewContext = struct {
    engine: *Engine,
    scale_x_spin: *c.GtkWidget,
    scale_y_spin: *c.GtkWidget,
    skew_x_spin: *c.GtkWidget,
    skew_y_spin: *c.GtkWidget,
    update_cb: *const fn () void,
};

fn on_stretch_skew_preview_change(_: *c.GtkWidget, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *StretchSkewContext = @ptrCast(@alignCast(data));
    const sx = c.gtk_spin_button_get_value(@ptrCast(ctx.scale_x_spin)) / 100.0;
    const sy = c.gtk_spin_button_get_value(@ptrCast(ctx.scale_y_spin)) / 100.0;
    const kx = c.gtk_spin_button_get_value(@ptrCast(ctx.skew_x_spin));
    const ky = c.gtk_spin_button_get_value(@ptrCast(ctx.skew_y_spin));

    // We use setTransformPreview.
    ctx.engine.setTransformPreview(.{ .scale_x = sx, .scale_y = sy, .skew_x = kx, .skew_y = ky });
    ctx.update_cb();
}

pub fn showStretchSkewDialog(
    parent: ?*c.GtkWindow,
    engine: *Engine,
    update_cb: *const fn () void,
) void {
    const dialog = c.adw_message_dialog_new(
        parent,
        "Stretch and Skew",
        "Resize or skew content.",
    );

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "_Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "apply", "_Apply");
    c.adw_message_dialog_set_default_response(@ptrCast(dialog), "apply");
    c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_top(box, 10);
    c.gtk_widget_set_margin_bottom(box, 10);
    c.gtk_widget_set_margin_start(box, 10);
    c.gtk_widget_set_margin_end(box, 10);

    const grid = c.gtk_grid_new();
    c.gtk_grid_set_row_spacing(@ptrCast(grid), 10);
    c.gtk_grid_set_column_spacing(@ptrCast(grid), 10);
    c.gtk_widget_set_halign(grid, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(box), grid);

    // Stretch Label
    const stretch_lbl = c.gtk_label_new("Stretch");
    c.gtk_widget_set_halign(stretch_lbl, c.GTK_ALIGN_START);
    c.gtk_widget_add_css_class(stretch_lbl, "heading");
    c.gtk_grid_attach(@ptrCast(grid), stretch_lbl, 0, 0, 2, 1);

    // Width %
    const w_label = c.gtk_label_new_with_mnemonic("_Horizontal (%):");
    c.gtk_widget_set_halign(w_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), w_label, 0, 1, 1, 1);
    const scale_x_spin = c.gtk_spin_button_new_with_range(1.0, 1000.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(w_label), scale_x_spin);
    c.gtk_spin_button_set_value(@ptrCast(scale_x_spin), 100.0);
    c.gtk_grid_attach(@ptrCast(grid), scale_x_spin, 1, 1, 1, 1);

    // Height %
    const h_label = c.gtk_label_new_with_mnemonic("_Vertical (%):");
    c.gtk_widget_set_halign(h_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), h_label, 0, 2, 1, 1);
    const scale_y_spin = c.gtk_spin_button_new_with_range(1.0, 1000.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(h_label), scale_y_spin);
    c.gtk_spin_button_set_value(@ptrCast(scale_y_spin), 100.0);
    c.gtk_grid_attach(@ptrCast(grid), scale_y_spin, 1, 2, 1, 1);

    // Skew Label
    const skew_lbl = c.gtk_label_new("Skew (Degrees)");
    c.gtk_widget_set_halign(skew_lbl, c.GTK_ALIGN_START);
    c.gtk_widget_add_css_class(skew_lbl, "heading");
    c.gtk_widget_set_margin_top(skew_lbl, 10);
    c.gtk_grid_attach(@ptrCast(grid), skew_lbl, 0, 3, 2, 1);

    // Skew X
    const skx_label = c.gtk_label_new_with_mnemonic("H_orizontal:");
    c.gtk_widget_set_halign(skx_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), skx_label, 0, 4, 1, 1);
    const skew_x_spin = c.gtk_spin_button_new_with_range(-89.0, 89.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(skx_label), skew_x_spin);
    c.gtk_spin_button_set_value(@ptrCast(skew_x_spin), 0.0);
    c.gtk_grid_attach(@ptrCast(grid), skew_x_spin, 1, 4, 1, 1);

    // Skew Y
    const sky_label = c.gtk_label_new_with_mnemonic("V_ertical:");
    c.gtk_widget_set_halign(sky_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), sky_label, 0, 5, 1, 1);
    const skew_y_spin = c.gtk_spin_button_new_with_range(-89.0, 89.0, 1.0);
    c.gtk_label_set_mnemonic_widget(@ptrCast(sky_label), skew_y_spin);
    c.gtk_spin_button_set_value(@ptrCast(skew_y_spin), 0.0);
    c.gtk_grid_attach(@ptrCast(grid), skew_y_spin, 1, 5, 1, 1);

    c.adw_message_dialog_set_extra_child(@ptrCast(dialog), box);

    const ctx = std.heap.c_allocator.create(StretchSkewContext) catch return;
    ctx.* = .{
        .engine = engine,
        .scale_x_spin = scale_x_spin,
        .scale_y_spin = scale_y_spin,
        .skew_x_spin = skew_x_spin,
        .skew_y_spin = skew_y_spin,
        .update_cb = update_cb,
    };

    _ = c.g_signal_connect_data(scale_x_spin, "value-changed", @ptrCast(&on_stretch_skew_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(scale_y_spin, "value-changed", @ptrCast(&on_stretch_skew_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(skew_x_spin, "value-changed", @ptrCast(&on_stretch_skew_preview_change), ctx, null, 0);
    _ = c.g_signal_connect_data(skew_y_spin, "value-changed", @ptrCast(&on_stretch_skew_preview_change), ctx, null, 0);

    const on_response = struct {
        fn func(d: *c.AdwMessageDialog, response: [*c]const u8, data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
            const context: *StretchSkewContext = @ptrCast(@alignCast(data));
            defer std.heap.c_allocator.destroy(context);

            const resp_span = std.mem.span(response);
            if (std.mem.eql(u8, resp_span, "apply")) {
                // We must apply transform.
                // Note: Preview mode is .transform.
                // engine.commitPreview() calls applyTransform() if mode is transform.
                context.engine.commitPreview() catch {};
            } else {
                context.engine.cancelPreview();
            }
            context.update_cb();
            c.gtk_window_destroy(@ptrCast(d));
        }
    }.func;

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&on_response), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}
