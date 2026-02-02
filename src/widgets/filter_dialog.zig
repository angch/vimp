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

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "apply", "Apply");
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
    const l_label = c.gtk_label_new("Length (px):");
    c.gtk_widget_set_halign(l_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), l_label, 0, 0, 1, 1);
    const length_spin = c.gtk_spin_button_new_with_range(0.0, 500.0, 1.0);
    c.gtk_spin_button_set_value(@ptrCast(length_spin), 10.0);
    c.gtk_grid_attach(@ptrCast(grid), length_spin, 1, 0, 1, 1);

    // Angle
    const a_label = c.gtk_label_new("Angle (deg):");
    c.gtk_widget_set_halign(a_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), a_label, 0, 1, 1, 1);
    const angle_spin = c.gtk_spin_button_new_with_range(0.0, 360.0, 1.0);
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

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "apply", "Apply");
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
    const sd_label = c.gtk_label_new("Radius (Std Dev):");
    c.gtk_widget_set_halign(sd_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), sd_label, 0, 0, 1, 1);
    const std_dev_spin = c.gtk_spin_button_new_with_range(0.1, 100.0, 0.1);
    c.gtk_spin_button_set_value(@ptrCast(std_dev_spin), 1.0);
    c.gtk_grid_attach(@ptrCast(grid), std_dev_spin, 1, 0, 1, 1);

    // Scale
    const s_label = c.gtk_label_new("Amount (Scale):");
    c.gtk_widget_set_halign(s_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), s_label, 0, 1, 1, 1);
    const scale_spin = c.gtk_spin_button_new_with_range(0.0, 10.0, 0.1);
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

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "apply", "Apply");
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
    const i_label = c.gtk_label_new("Iterations:");
    c.gtk_widget_set_halign(i_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), i_label, 0, 0, 1, 1);
    const iter_spin = c.gtk_spin_button_new_with_range(1.0, 10.0, 1.0);
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

    c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "Cancel");
    c.adw_message_dialog_add_response(@ptrCast(dialog), "apply", "Apply");
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
    const l_label = c.gtk_label_new("Block Size (px):");
    c.gtk_widget_set_halign(l_label, c.GTK_ALIGN_END);
    c.gtk_grid_attach(@ptrCast(grid), l_label, 0, 0, 1, 1);
    const size_spin = c.gtk_spin_button_new_with_range(2.0, 200.0, 1.0);
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
