const std = @import("std");
const c = @import("../c.zig").c;
const Engine = @import("../engine.zig").Engine;
const Tool = @import("../tools.zig").Tool;

pub const ToolOptionsPanel = struct {
    box: *c.GtkWidget,
    engine: *Engine,
    current_tool: Tool,
    queue_draw_callback: *const fn () void,

    // UI References
    transform_x_spin: ?*c.GtkWidget = null,
    transform_y_spin: ?*c.GtkWidget = null,
    transform_r_scale: ?*c.GtkWidget = null,
    transform_s_scale: ?*c.GtkWidget = null,

    pub fn create(engine: *Engine, queue_draw_cb: *const fn () void) *ToolOptionsPanel {
        const self = std.heap.c_allocator.create(ToolOptionsPanel) catch @panic("OOM");
        self.* = .{
            .box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 5),
            .engine = engine,
            .current_tool = .brush,
            .queue_draw_callback = queue_draw_cb,
        };
        return self;
    }

    pub fn widget(self: *ToolOptionsPanel) *c.GtkWidget {
        return self.box;
    }

    pub fn resetTransformUI(self: *ToolOptionsPanel) void {
        if (self.transform_x_spin) |w| c.gtk_spin_button_set_value(@ptrCast(w), 0.0);
        if (self.transform_y_spin) |w| c.gtk_spin_button_set_value(@ptrCast(w), 0.0);
        if (self.transform_r_scale) |w| c.gtk_range_set_value(@ptrCast(w), 0.0);
        if (self.transform_s_scale) |w| c.gtk_range_set_value(@ptrCast(w), 1.0);
    }

    pub fn update(self: *ToolOptionsPanel, tool: Tool) void {
        self.current_tool = tool;

        // Clear children
        var child = c.gtk_widget_get_first_child(self.box);
        while (child != null) {
            const next = c.gtk_widget_get_next_sibling(child);
            c.gtk_box_remove(@ptrCast(self.box), child);
            child = next;
        }

        // Reset pointers
        self.transform_x_spin = null;
        self.transform_y_spin = null;
        self.transform_r_scale = null;
        self.transform_s_scale = null;

        const box = self.box;

        switch (self.current_tool) {
            .brush, .pencil, .airbrush, .eraser, .line, .curve, .polygon => {
                const label = c.gtk_label_new_with_mnemonic("_Size");
                c.gtk_widget_set_halign(label, c.GTK_ALIGN_START);
                c.gtk_box_append(@ptrCast(box), label);
                const slider = c.gtk_scale_new_with_range(c.GTK_ORIENTATION_HORIZONTAL, 1.0, 100.0, 1.0);
                c.gtk_label_set_mnemonic_widget(@ptrCast(label), slider);
                c.gtk_range_set_value(@ptrCast(slider), @floatFromInt(self.engine.brush_size));
                c.gtk_widget_set_hexpand(slider, 1);
                c.gtk_box_append(@ptrCast(box), slider);
                _ = c.g_signal_connect_data(slider, "value-changed", @ptrCast(&brush_size_changed), self, null, 0);

                if (self.current_tool != .eraser) {
                    const op_label = c.gtk_label_new_with_mnemonic("_Opacity");
                    c.gtk_widget_set_halign(op_label, c.GTK_ALIGN_START);
                    c.gtk_box_append(@ptrCast(box), op_label);
                    const op_slider = c.gtk_scale_new_with_range(c.GTK_ORIENTATION_HORIZONTAL, 0.0, 100.0, 1.0);
                    c.gtk_label_set_mnemonic_widget(@ptrCast(op_label), op_slider);
                    c.gtk_range_set_value(@ptrCast(op_slider), self.engine.brush_opacity * 100.0);
                    c.gtk_widget_set_hexpand(op_slider, 1);
                    c.gtk_box_append(@ptrCast(box), op_slider);
                    _ = c.g_signal_connect_data(op_slider, "value-changed", @ptrCast(&opacity_changed), self, null, 0);
                }
            },
            .rect_shape, .ellipse_shape, .rounded_rect_shape => {
                const label = c.gtk_label_new_with_mnemonic("_Thickness");
                c.gtk_widget_set_halign(label, c.GTK_ALIGN_START);
                c.gtk_box_append(@ptrCast(box), label);
                const slider = c.gtk_scale_new_with_range(c.GTK_ORIENTATION_HORIZONTAL, 1.0, 100.0, 1.0);
                c.gtk_label_set_mnemonic_widget(@ptrCast(label), slider);
                c.gtk_range_set_value(@ptrCast(slider), @floatFromInt(self.engine.brush_size));
                c.gtk_widget_set_hexpand(slider, 1);
                c.gtk_box_append(@ptrCast(box), slider);
                _ = c.g_signal_connect_data(slider, "value-changed", @ptrCast(&brush_size_changed), self, null, 0);

                const op_label = c.gtk_label_new_with_mnemonic("_Opacity");
                c.gtk_widget_set_halign(op_label, c.GTK_ALIGN_START);
                c.gtk_box_append(@ptrCast(box), op_label);
                const op_slider = c.gtk_scale_new_with_range(c.GTK_ORIENTATION_HORIZONTAL, 0.0, 100.0, 1.0);
                c.gtk_label_set_mnemonic_widget(@ptrCast(op_label), op_slider);
                c.gtk_range_set_value(@ptrCast(op_slider), self.engine.brush_opacity * 100.0);
                c.gtk_widget_set_hexpand(op_slider, 1);
                c.gtk_box_append(@ptrCast(box), op_slider);
                _ = c.g_signal_connect_data(op_slider, "value-changed", @ptrCast(&opacity_changed), self, null, 0);

                const check = c.gtk_check_button_new_with_mnemonic("_Filled");
                c.gtk_check_button_set_active(@ptrCast(check), if (self.engine.brush_filled) 1 else 0);
                c.gtk_box_append(@ptrCast(box), check);
                _ = c.g_signal_connect_data(check, "toggled", @ptrCast(&shape_fill_toggled), self, null, 0);
            },
            .rect_select, .ellipse_select, .lasso => {
                const check = c.gtk_check_button_new_with_mnemonic("_Transparent");
                c.gtk_check_button_set_active(@ptrCast(check), if (self.engine.selection_transparent) 1 else 0);
                c.gtk_box_append(@ptrCast(box), check);
                _ = c.g_signal_connect_data(check, "toggled", @ptrCast(&selection_transparent_toggled), self, null, 0);
            },
            .text => {
                const label = c.gtk_label_new_with_mnemonic("_Font Size");
                c.gtk_widget_set_halign(label, c.GTK_ALIGN_START);
                c.gtk_box_append(@ptrCast(box), label);
                const spin = c.gtk_spin_button_new_with_range(8.0, 500.0, 1.0);
                c.gtk_label_set_mnemonic_widget(@ptrCast(label), spin);
                c.gtk_spin_button_set_value(@ptrCast(spin), @floatFromInt(self.engine.font_size));
                c.gtk_box_append(@ptrCast(box), spin);
                _ = c.g_signal_connect_data(spin, "value-changed", @ptrCast(&font_size_changed), self, null, 0);
            },
            .unified_transform => {
                const label_x = c.gtk_label_new_with_mnemonic("Translate _X");
                c.gtk_widget_set_halign(label_x, c.GTK_ALIGN_START);
                c.gtk_box_append(@ptrCast(box), label_x);
                const t_x = c.gtk_spin_button_new_with_range(-1000.0, 1000.0, 1.0);
                c.gtk_label_set_mnemonic_widget(@ptrCast(label_x), t_x);
                self.transform_x_spin = t_x;
                c.gtk_box_append(@ptrCast(box), t_x);
                _ = c.g_signal_connect_data(t_x, "value-changed", @ptrCast(&transform_param_changed), self, null, 0);

                const label_y = c.gtk_label_new_with_mnemonic("Translate _Y");
                c.gtk_widget_set_halign(label_y, c.GTK_ALIGN_START);
                c.gtk_box_append(@ptrCast(box), label_y);
                const t_y = c.gtk_spin_button_new_with_range(-1000.0, 1000.0, 1.0);
                c.gtk_label_set_mnemonic_widget(@ptrCast(label_y), t_y);
                self.transform_y_spin = t_y;
                c.gtk_box_append(@ptrCast(box), t_y);
                _ = c.g_signal_connect_data(t_y, "value-changed", @ptrCast(&transform_param_changed), self, null, 0);

                const label_r = c.gtk_label_new_with_mnemonic("_Rotate (Deg)");
                c.gtk_widget_set_halign(label_r, c.GTK_ALIGN_START);
                c.gtk_box_append(@ptrCast(box), label_r);
                const t_r = c.gtk_scale_new_with_range(c.GTK_ORIENTATION_HORIZONTAL, -180.0, 180.0, 1.0);
                c.gtk_label_set_mnemonic_widget(@ptrCast(label_r), t_r);
                self.transform_r_scale = t_r;
                c.gtk_box_append(@ptrCast(box), t_r);
                _ = c.g_signal_connect_data(t_r, "value-changed", @ptrCast(&transform_param_changed), self, null, 0);

                const label_s = c.gtk_label_new_with_mnemonic("_Scale");
                c.gtk_widget_set_halign(label_s, c.GTK_ALIGN_START);
                c.gtk_box_append(@ptrCast(box), label_s);
                const t_s = c.gtk_scale_new_with_range(c.GTK_ORIENTATION_HORIZONTAL, 0.1, 5.0, 0.1);
                c.gtk_label_set_mnemonic_widget(@ptrCast(label_s), t_s);
                c.gtk_range_set_value(@ptrCast(t_s), 1.0);
                self.transform_s_scale = t_s;
                c.gtk_box_append(@ptrCast(box), t_s);
                _ = c.g_signal_connect_data(t_s, "value-changed", @ptrCast(&transform_param_changed), self, null, 0);
            },
            else => {},
        }

        const first = c.gtk_widget_get_first_child(@ptrCast(box));
        c.gtk_widget_set_visible(@ptrCast(box), if (first != null) 1 else 0);
    }

    fn brush_size_changed(range: *c.GtkRange, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
        const self: *ToolOptionsPanel = @ptrCast(@alignCast(user_data));
        const value = c.gtk_range_get_value(range);
        const size: c_int = @intFromFloat(value);
        self.engine.setBrushSize(size);
    }

    fn opacity_changed(range: *c.GtkRange, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
        const self: *ToolOptionsPanel = @ptrCast(@alignCast(user_data));
        const value = c.gtk_range_get_value(range); // 0-100
        self.engine.brush_opacity = value / 100.0;
    }

    fn shape_fill_toggled(check: *c.GtkCheckButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
        const self: *ToolOptionsPanel = @ptrCast(@alignCast(user_data));
        self.engine.brush_filled = c.gtk_check_button_get_active(check) != 0;
    }

    fn selection_transparent_toggled(check: *c.GtkCheckButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
        const self: *ToolOptionsPanel = @ptrCast(@alignCast(user_data));
        const active = c.gtk_check_button_get_active(check) != 0;
        self.engine.setSelectionTransparent(active);
    }

    fn font_size_changed(spin: *c.GtkSpinButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
        const self: *ToolOptionsPanel = @ptrCast(@alignCast(user_data));
        self.engine.font_size = @intCast(c.gtk_spin_button_get_value_as_int(spin));
    }

    fn transform_param_changed(_: *c.GtkWidget, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
        const self: *ToolOptionsPanel = @ptrCast(@alignCast(user_data));
        if (self.transform_x_spin == null) return;
        const x = c.gtk_spin_button_get_value(@ptrCast(self.transform_x_spin.?));
        const y = c.gtk_spin_button_get_value(@ptrCast(self.transform_y_spin.?));
        const r = c.gtk_range_get_value(@ptrCast(self.transform_r_scale.?));
        const s = c.gtk_range_get_value(@ptrCast(self.transform_s_scale.?));

        self.engine.setTransformPreview(.{ .x = x, .y = y, .rotate = r, .scale_x = s, .scale_y = s });
        // Trigger redraw
        self.queue_draw_callback();
    }
};
