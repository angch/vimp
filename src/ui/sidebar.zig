const std = @import("std");
const c = @import("../c.zig").c;
const Engine = @import("../engine.zig").Engine;
const Tool = @import("../tools.zig").Tool;
const ToolFactory = @import("../tools.zig").ToolFactory;
const ToolOptionsPanel = @import("../widgets/tool_options_panel.zig").ToolOptionsPanel;
const ColorPalette = @import("../widgets/color_palette.zig").ColorPalette;
const Assets = @import("../assets.zig");
const RecentColorsManager = @import("../recent_colors.zig").RecentColorsManager;

pub const SidebarCallbacks = struct {
    tool_toggled: c.GCallback,
    request_update: *const fn () void,
    palette_color_changed: *const fn () void,
};

const ToolGroupItemContext = struct {
    main_btn: *c.GtkWidget,
    active_tool_ref: *Tool,
    tool: Tool,
    popover: *c.GtkPopover,
    callback: c.GCallback,
};

fn destroy_tool_group_item_context(data: ?*anyopaque, _: ?*c.GClosure) callconv(std.builtin.CallingConvention.c) void {
    if (data) |d| {
        const ctx: *ToolGroupItemContext = @ptrCast(@alignCast(d));
        std.heap.c_allocator.destroy(ctx);
    }
}

fn on_group_item_clicked(_: *c.GtkButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *ToolGroupItemContext = @ptrCast(@alignCast(user_data));

    ctx.active_tool_ref.* = ctx.tool;

    var img: *c.GtkWidget = undefined;
    if (ToolFactory.getToolIconData(ctx.tool)) |data| {
        img = Assets.getIconWidget(data, 24);
    } else {
        img = c.gtk_image_new_from_icon_name("image-missing-symbolic");
        c.gtk_widget_set_size_request(img, 24, 24);
    }

    c.gtk_button_set_child(@ptrCast(ctx.main_btn), img);

    const tooltip = ToolFactory.getToolTooltip(ctx.tool);
    c.gtk_widget_set_tooltip_text(ctx.main_btn, tooltip.ptr);

    const is_active = c.gtk_toggle_button_get_active(@ptrCast(ctx.main_btn)) != 0;
    if (!is_active) {
        c.gtk_toggle_button_set_active(@ptrCast(ctx.main_btn), 1);
    } else {
        // Force update by calling the callback manually
        const FuncType = *const fn (*c.GtkToggleButton, ?*anyopaque) callconv(.c) void;
        const func: FuncType = @ptrCast(ctx.callback);
        func(@ptrCast(ctx.main_btn), ctx.active_tool_ref);
    }

    c.gtk_popover_popdown(ctx.popover);
}

fn on_group_right_click(
    gesture: *c.GtkGestureClick,
    _: c_int,
    _: f64,
    _: f64,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    const popover: *c.GtkPopover = @ptrCast(@alignCast(user_data));
    const widget = c.gtk_event_controller_get_widget(@ptrCast(gesture));
    c.gtk_widget_set_parent(@ptrCast(popover), widget);
    c.gtk_popover_popup(popover);
}

fn on_group_long_press(
    gesture: *c.GtkGestureLongPress,
    _: f64,
    _: f64,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    const popover: *c.GtkPopover = @ptrCast(@alignCast(user_data));
    const widget = c.gtk_event_controller_get_widget(@ptrCast(gesture));
    c.gtk_widget_set_parent(@ptrCast(popover), widget);
    c.gtk_popover_popup(popover);
}

pub const Sidebar = struct {
    widget: *c.GtkWidget,
    layers_list_box: ?*c.GtkWidget = null,
    undo_list_box: ?*c.GtkWidget = null,
    tool_options_panel: ?*ToolOptionsPanel = null,
    color_btn: ?*c.GtkWidget = null,
    default_tool_btn: ?*c.GtkWidget = null,
    window: *c.GtkWindow,

    // Tool state
    active_selection_tool: Tool = .rect_select,
    active_shape_tool: Tool = .rect_shape,
    active_paint_tool: Tool = .brush,
    active_line_tool: Tool = .line,

    // Tool constants
    brush_tool: Tool = .brush,
    pencil_tool: Tool = .pencil,
    airbrush_tool: Tool = .airbrush,
    eraser_tool: Tool = .eraser,
    bucket_fill_tool: Tool = .bucket_fill,
    rect_select_tool: Tool = .rect_select,
    ellipse_select_tool: Tool = .ellipse_select,
    lasso_tool: Tool = .lasso,
    rect_shape_tool: Tool = .rect_shape,
    ellipse_shape_tool: Tool = .ellipse_shape,
    rounded_rect_shape_tool: Tool = .rounded_rect_shape,
    polygon_tool: Tool = .polygon,
    text_tool: Tool = .text,
    unified_transform_tool: Tool = .unified_transform,
    color_picker_tool: Tool = .color_picker,
    gradient_tool: Tool = .gradient,
    line_tool: Tool = .line,
    curve_tool: Tool = .curve,

    engine: *Engine,
    recent_colors_manager: *RecentColorsManager,
    callbacks: SidebarCallbacks,

    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator, engine: *Engine, recent_colors_manager: *RecentColorsManager, callbacks: SidebarCallbacks, window: *c.GtkWindow) !*Sidebar {
        const self = try allocator.create(Sidebar);
        self.* = .{
            .widget = undefined,
            .engine = engine,
            .recent_colors_manager = recent_colors_manager,
            .callbacks = callbacks,
            .allocator = allocator,
            .window = window,
        };

        const sidebar = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
        c.gtk_widget_set_size_request(sidebar, 160, -1);
        c.gtk_widget_add_css_class(sidebar, "sidebar");
        self.widget = sidebar;

        const tools_label = c.gtk_label_new("Tools");
        c.gtk_box_append(@ptrCast(sidebar), tools_label);

        const tools_container = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 5);
        c.gtk_widget_set_halign(tools_container, c.GTK_ALIGN_CENTER);
        c.gtk_box_append(@ptrCast(sidebar), tools_container);

        var tools_row_box: ?*c.GtkWidget = null;
        var tools_in_row: usize = 0;

        // Paint Group
        const paint_tools = [_]Tool{ .brush, .pencil, .airbrush };
        const paint_group_btn = try self.createToolGroup(&self.active_paint_tool, &paint_tools, null);
        self.appendTool(tools_container, paint_group_btn, &tools_row_box, &tools_in_row);
        self.default_tool_btn = paint_group_btn;

        // Eraser
        const eraser_btn = self.createToolButton(&self.eraser_tool, @ptrCast(paint_group_btn));
        self.appendTool(tools_container, eraser_btn, &tools_row_box, &tools_in_row);

        // Bucket Fill
        const fill_btn = self.createToolButton(&self.bucket_fill_tool, @ptrCast(paint_group_btn));
        self.appendTool(tools_container, fill_btn, &tools_row_box, &tools_in_row);

        // Selection Group
        const select_tools = [_]Tool{ .rect_select, .ellipse_select, .lasso };
        const select_group_btn = try self.createToolGroup(&self.active_selection_tool, &select_tools, @ptrCast(paint_group_btn));
        self.appendTool(tools_container, select_group_btn, &tools_row_box, &tools_in_row);

        // Text Tool
        const text_btn = self.createToolButton(&self.text_tool, @ptrCast(paint_group_btn));
        self.appendTool(tools_container, text_btn, &tools_row_box, &tools_in_row);

        // Shapes Group
        const shape_tools = [_]Tool{ .rect_shape, .ellipse_shape, .rounded_rect_shape, .polygon };
        const shape_group_btn = try self.createToolGroup(&self.active_shape_tool, &shape_tools, @ptrCast(paint_group_btn));
        self.appendTool(tools_container, shape_group_btn, &tools_row_box, &tools_in_row);

        // Unified Transform
        const transform_btn = self.createToolButton(&self.unified_transform_tool, @ptrCast(paint_group_btn));
        self.appendTool(tools_container, transform_btn, &tools_row_box, &tools_in_row);

        // Color Picker
        const picker_btn = self.createToolButton(&self.color_picker_tool, @ptrCast(paint_group_btn));
        self.appendTool(tools_container, picker_btn, &tools_row_box, &tools_in_row);

        // Gradient Tool
        const gradient_btn = self.createToolButton(&self.gradient_tool, @ptrCast(paint_group_btn));
        self.appendTool(tools_container, gradient_btn, &tools_row_box, &tools_in_row);

        // Lines Group
        const line_tools = [_]Tool{ .line, .curve };
        const line_group_btn = try self.createToolGroup(&self.active_line_tool, &line_tools, @ptrCast(paint_group_btn));
        self.appendTool(tools_container, line_group_btn, &tools_row_box, &tools_in_row);

        c.gtk_box_append(@ptrCast(sidebar), c.gtk_separator_new(c.GTK_ORIENTATION_HORIZONTAL));

        // Color Palette
        const palette = ColorPalette.create(engine, callbacks.palette_color_changed);
        c.gtk_box_append(@ptrCast(sidebar), palette);

        const color_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 5);
        c.gtk_widget_set_halign(color_box, c.GTK_ALIGN_CENTER);
        c.gtk_box_append(@ptrCast(sidebar), color_box);

        const color_btn = self.createColorButton();
        self.color_btn = color_btn;
        c.gtk_box_append(@ptrCast(color_box), color_btn);

        const edit_colors_btn = c.gtk_button_new_with_mnemonic("_Edit Colors");
        _ = c.g_signal_connect_data(edit_colors_btn, "clicked", @ptrCast(&on_edit_colors_clicked), self, null, 0);
        c.gtk_box_append(@ptrCast(color_box), edit_colors_btn);

        const tool_options_panel = ToolOptionsPanel.create(engine, callbacks.request_update);
        self.tool_options_panel = tool_options_panel;
        c.gtk_box_append(@ptrCast(sidebar), tool_options_panel.widget());
        tool_options_panel.update(.brush);

        c.gtk_box_append(@ptrCast(sidebar), c.gtk_separator_new(c.GTK_ORIENTATION_HORIZONTAL));
        c.gtk_box_append(@ptrCast(sidebar), c.gtk_label_new("Layers"));

        const layers_list = c.gtk_list_box_new();
        c.gtk_widget_set_vexpand(layers_list, 1);
        c.gtk_list_box_set_selection_mode(@ptrCast(layers_list), c.GTK_SELECTION_SINGLE);
        _ = c.g_signal_connect_data(layers_list, "row-selected", @ptrCast(&on_layer_selected), self, null, 0);

        const scrolled = c.gtk_scrolled_window_new();
        c.gtk_scrolled_window_set_child(@ptrCast(scrolled), layers_list);
        c.gtk_widget_set_vexpand(scrolled, 1);
        c.gtk_box_append(@ptrCast(sidebar), scrolled);
        self.layers_list_box = layers_list;

        const layers_btns = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 5);
        c.gtk_widget_set_halign(layers_btns, c.GTK_ALIGN_CENTER);
        c.gtk_box_append(@ptrCast(sidebar), layers_btns);

        const add_layer_btn = c.gtk_button_new_from_icon_name("list-add-symbolic");
        c.gtk_widget_set_tooltip_text(add_layer_btn, "Add Layer");
        c.gtk_box_append(@ptrCast(layers_btns), add_layer_btn);
        _ = c.g_signal_connect_data(add_layer_btn, "clicked", @ptrCast(&on_layer_add), self, null, 0);

        const remove_layer_btn = c.gtk_button_new_from_icon_name("list-remove-symbolic");
        c.gtk_widget_set_tooltip_text(remove_layer_btn, "Remove Layer");
        c.gtk_box_append(@ptrCast(layers_btns), remove_layer_btn);
        _ = c.g_signal_connect_data(remove_layer_btn, "clicked", @ptrCast(&on_layer_remove), self, null, 0);

        const up_layer_btn = c.gtk_button_new_from_icon_name("go-up-symbolic");
        c.gtk_widget_set_tooltip_text(up_layer_btn, "Move Up");
        c.gtk_box_append(@ptrCast(layers_btns), up_layer_btn);
        _ = c.g_signal_connect_data(up_layer_btn, "clicked", @ptrCast(&on_layer_up), self, null, 0);

        const down_layer_btn = c.gtk_button_new_from_icon_name("go-down-symbolic");
        c.gtk_widget_set_tooltip_text(down_layer_btn, "Move Down");
        c.gtk_box_append(@ptrCast(layers_btns), down_layer_btn);
        _ = c.g_signal_connect_data(down_layer_btn, "clicked", @ptrCast(&on_layer_down), self, null, 0);

        c.gtk_box_append(@ptrCast(sidebar), c.gtk_separator_new(c.GTK_ORIENTATION_HORIZONTAL));
        c.gtk_box_append(@ptrCast(sidebar), c.gtk_label_new("Undo History"));

        const undo_list = c.gtk_list_box_new();
        c.gtk_list_box_set_selection_mode(@ptrCast(undo_list), c.GTK_SELECTION_NONE);

        const undo_scrolled = c.gtk_scrolled_window_new();
        c.gtk_scrolled_window_set_child(@ptrCast(undo_scrolled), undo_list);
        c.gtk_widget_set_vexpand(undo_scrolled, 1);
        c.gtk_box_append(@ptrCast(sidebar), undo_scrolled);
        self.undo_list_box = undo_list;

        return self;
    }

    pub fn activateDefaultTool(self: *Sidebar) void {
        if (self.default_tool_btn) |btn| {
            c.gtk_toggle_button_set_active(@ptrCast(btn), 1);
        }
    }

    fn appendTool(self: *Sidebar, container: *c.GtkWidget, btn: *c.GtkWidget, row_ref: *?*c.GtkWidget, count_ref: *usize) void {
        _ = self;
        if (row_ref.* == null or count_ref.* >= 6) {
            const row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 5);
            c.gtk_widget_set_halign(row, c.GTK_ALIGN_CENTER);
            c.gtk_box_append(@ptrCast(container), row);
            row_ref.* = row;
            count_ref.* = 0;
        }
        c.gtk_box_append(@ptrCast(row_ref.*.?), btn);
        count_ref.* += 1;
    }

    fn createToolButton(self: *Sidebar, tool_val: *Tool, group: ?*c.GtkToggleButton) *c.GtkWidget {
        const btn = if (group) |_| c.gtk_toggle_button_new() else c.gtk_toggle_button_new();
        if (group) |g| c.gtk_toggle_button_set_group(@ptrCast(btn), g);

        var img: *c.GtkWidget = undefined;
        if (ToolFactory.getToolIconData(tool_val.*)) |data| {
            img = Assets.getIconWidget(data, 24);
        } else {
            img = c.gtk_image_new_from_icon_name("image-missing-symbolic");
            c.gtk_widget_set_size_request(img, 24, 24);
        }

        c.gtk_button_set_child(@ptrCast(btn), img);

        const tooltip = ToolFactory.getToolTooltip(tool_val.*);
        c.gtk_widget_set_tooltip_text(btn, tooltip.ptr);

        _ = c.g_signal_connect_data(btn, "toggled", self.callbacks.tool_toggled, tool_val, null, 0);
        return btn;
    }

    fn createToolGroup(self: *Sidebar, active_tool_ref: *Tool, tools: []const Tool, group: ?*c.GtkToggleButton) !*c.GtkWidget {
        const btn = if (group) |_| c.gtk_toggle_button_new() else c.gtk_toggle_button_new();
        if (group) |g| c.gtk_toggle_button_set_group(@ptrCast(btn), g);

        // Set initial state
        var current_tool: Tool = tools[0];
        for (tools) |t| {
            if (t == active_tool_ref.*) {
                current_tool = t;
                break;
            }
        }

        var img: *c.GtkWidget = undefined;
        if (ToolFactory.getToolIconData(current_tool)) |data| {
            img = Assets.getIconWidget(data, 24);
        } else {
            img = c.gtk_image_new_from_icon_name("image-missing-symbolic");
            c.gtk_widget_set_size_request(img, 24, 24);
        }

        c.gtk_button_set_child(@ptrCast(btn), img);

        const tooltip = ToolFactory.getToolTooltip(current_tool);
        c.gtk_widget_set_tooltip_text(btn, tooltip.ptr);

        _ = c.g_signal_connect_data(btn, "toggled", self.callbacks.tool_toggled, active_tool_ref, null, 0);

        const popover = c.gtk_popover_new();
        const grid = c.gtk_grid_new();
        c.gtk_grid_set_row_spacing(@ptrCast(grid), 5);
        c.gtk_grid_set_column_spacing(@ptrCast(grid), 5);
        c.gtk_widget_set_margin_top(grid, 5);
        c.gtk_widget_set_margin_bottom(grid, 5);
        c.gtk_widget_set_margin_start(grid, 5);
        c.gtk_widget_set_margin_end(grid, 5);
        c.gtk_popover_set_child(@ptrCast(popover), grid);

        for (tools, 0..) |t, i| {
            const item_btn = c.gtk_button_new();
            var item_img: *c.GtkWidget = undefined;
            if (ToolFactory.getToolIconData(t)) |data| {
                item_img = Assets.getIconWidget(data, 24);
            } else {
                item_img = c.gtk_image_new_from_icon_name("image-missing-symbolic");
                c.gtk_widget_set_size_request(item_img, 24, 24);
            }

            c.gtk_button_set_child(@ptrCast(item_btn), item_img);

            const item_tooltip = ToolFactory.getToolTooltip(t);
            c.gtk_widget_set_tooltip_text(item_btn, item_tooltip.ptr);

            const col = @as(c_int, @intCast(i % 3));
            const row = @as(c_int, @intCast(i / 3));
            c.gtk_grid_attach(@ptrCast(grid), item_btn, col, row, 1, 1);

            const ctx = try std.heap.c_allocator.create(ToolGroupItemContext);
            ctx.* = .{
                .main_btn = btn,
                .active_tool_ref = active_tool_ref,
                .tool = t,
                .popover = @ptrCast(popover),
                .callback = self.callbacks.tool_toggled,
            };

            _ = c.g_signal_connect_data(item_btn, "clicked", @ptrCast(&on_group_item_clicked), ctx, @ptrCast(&destroy_tool_group_item_context), 0);
        }

        const click = c.gtk_gesture_click_new();
        c.gtk_gesture_single_set_button(@ptrCast(click), 3);
        _ = c.g_signal_connect_data(click, "pressed", @ptrCast(&on_group_right_click), popover, null, 0);
        c.gtk_widget_add_controller(btn, @ptrCast(click));

        const long_press = c.gtk_gesture_long_press_new();
        _ = c.g_signal_connect_data(long_press, "pressed", @ptrCast(&on_group_long_press), popover, null, 0);
        c.gtk_widget_add_controller(btn, @ptrCast(long_press));

        return btn;
    }

    fn populateRecentColors(self: *Sidebar, chooser: *c.GtkColorChooser) void {
        if (self.recent_colors_manager.colors.items.len > 0) {
            c.gtk_color_chooser_add_palette(
                chooser,
                c.GTK_ORIENTATION_HORIZONTAL,
                5,
                @intCast(self.recent_colors_manager.colors.items.len),
                self.recent_colors_manager.colors.items.ptr,
            );
        }
    }

    fn createColorButton(self: *Sidebar) *c.GtkWidget {
        const btn = c.gtk_color_button_new();
        c.gtk_widget_set_valign(btn, c.GTK_ALIGN_START);
        c.gtk_widget_set_halign(btn, c.GTK_ALIGN_CENTER);

        _ = c.g_signal_connect_data(btn, "color-set", @ptrCast(&on_color_changed), self, null, 0);

        self.populateRecentColors(@ptrCast(btn));
        return btn;
    }

    pub fn rebuildRecentColors(self: *Sidebar) void {
        if (self.color_btn == null or self.tool_options_panel == null) return;

        const parent = c.gtk_widget_get_parent(self.color_btn.?);
        if (parent == null) return;

        c.gtk_box_remove(@ptrCast(parent), self.color_btn.?);

        self.color_btn = self.createColorButton();

        const fg = self.engine.fg_color;
        const rgba = c.GdkRGBA{
            .red = @as(f32, @floatFromInt(fg[0])) / 255.0,
            .green = @as(f32, @floatFromInt(fg[1])) / 255.0,
            .blue = @as(f32, @floatFromInt(fg[2])) / 255.0,
            .alpha = @as(f32, @floatFromInt(fg[3])) / 255.0,
        };
        c.gtk_color_chooser_set_rgba(@ptrCast(self.color_btn.?), &rgba);

        c.gtk_box_prepend(@ptrCast(parent), self.color_btn.?);

        _ = c.gtk_widget_grab_focus(self.color_btn.?);
    }

    pub fn updateColorButton(self: *Sidebar) void {
        if (self.color_btn) |btn| {
            const fg = self.engine.fg_color;
            const rgba = c.GdkRGBA{
                .red = @as(f32, @floatFromInt(fg[0])) / 255.0,
                .green = @as(f32, @floatFromInt(fg[1])) / 255.0,
                .blue = @as(f32, @floatFromInt(fg[2])) / 255.0,
                .alpha = @as(f32, @floatFromInt(fg[3])) / 255.0,
            };
            c.gtk_color_chooser_set_rgba(@ptrCast(btn), &rgba);
        }
    }

    // --- Logic previously in main.zig ---

    pub fn refreshLayers(self: *Sidebar) void {
        if (self.layers_list_box) |box| {
            var child = c.gtk_widget_get_first_child(@ptrCast(box));
            while (child != null) {
                const next = c.gtk_widget_get_next_sibling(child);
                c.gtk_list_box_remove(@ptrCast(box), child);
                child = next;
            }

            var i: usize = self.engine.layers.list.items.len;
            while (i > 0) {
                i -= 1;
                const idx = i;
                const layer = &self.engine.layers.list.items[idx];

                const row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 5);

                const vis_check = c.gtk_check_button_new();
                c.gtk_check_button_set_active(@ptrCast(vis_check), if (layer.visible) 1 else 0);
                c.gtk_widget_set_tooltip_text(vis_check, "Visible");
                c.g_object_set_data(@ptrCast(vis_check), "layer-index", @ptrFromInt(idx));
                _ = c.g_signal_connect_data(vis_check, "toggled", @ptrCast(&on_layer_visibility_toggled), self, null, 0);
                c.gtk_box_append(@ptrCast(row), vis_check);

                const lock_check = c.gtk_check_button_new();
                c.gtk_check_button_set_active(@ptrCast(lock_check), if (layer.locked) 1 else 0);
                c.gtk_widget_set_tooltip_text(lock_check, "Lock");
                c.g_object_set_data(@ptrCast(lock_check), "layer-index", @ptrFromInt(idx));
                _ = c.g_signal_connect_data(lock_check, "toggled", @ptrCast(&on_layer_lock_toggled), self, null, 0);
                c.gtk_box_append(@ptrCast(row), lock_check);

                const name_span = std.mem.span(@as([*:0]const u8, @ptrCast(&layer.name)));
                const label = c.gtk_label_new(name_span.ptr);
                c.gtk_widget_set_hexpand(label, 1);
                c.gtk_widget_set_halign(label, c.GTK_ALIGN_START);
                c.gtk_box_append(@ptrCast(row), label);

                c.gtk_list_box_insert(@ptrCast(box), row, -1);
                if (idx == self.engine.layers.active_index) {
                     const list_row = c.gtk_widget_get_parent(row);
                     if (list_row) |lr| {
                         c.gtk_list_box_select_row(@ptrCast(box), @ptrCast(lr));
                     }
                }
            }
        }
    }

    pub fn refreshUndo(self: *Sidebar) void {
        if (self.undo_list_box) |box| {
            var child = c.gtk_widget_get_first_child(@ptrCast(box));
            while (child != null) {
                const next = c.gtk_widget_get_next_sibling(child);
                c.gtk_list_box_remove(@ptrCast(box), child);
                child = next;
            }

            for (self.engine.history.undo_stack.items) |cmd| {
                const desc = cmd.description();
                const label = c.gtk_label_new(desc);
                c.gtk_widget_set_halign(label, c.GTK_ALIGN_START);
                c.gtk_widget_set_margin_start(label, 5);
                c.gtk_list_box_insert(@ptrCast(box), label, -1);
            }
        }
    }

    fn rebuild_recent_colors_wrapper(_: ?*anyopaque) callconv(std.builtin.CallingConvention.c) c.gboolean {
         // We cannot easily get self here unless we pass it.
         // But g_idle_add takes user_data.
         return 0; // Handled in specific functions
    }
};

fn rebuild_recent_colors_idle(user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) c.gboolean {
    const self: *Sidebar = @ptrCast(@alignCast(user_data));
    self.rebuildRecentColors();
    return 0;
}

fn on_color_changed(button: *c.GtkColorButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const self: *Sidebar = @ptrCast(@alignCast(user_data));
    var rgba: c.GdkRGBA = undefined;
    c.gtk_color_chooser_get_rgba(@ptrCast(button), &rgba);

    const r: u8 = @intFromFloat(rgba.red * 255.0);
    const g: u8 = @intFromFloat(rgba.green * 255.0);
    const b: u8 = @intFromFloat(rgba.blue * 255.0);
    const a: u8 = @intFromFloat(rgba.alpha * 255.0);

    self.engine.setFgColor(r, g, b, a);
    self.recent_colors_manager.add(rgba) catch {};
    _ = c.g_idle_add(@ptrCast(&rebuild_recent_colors_idle), self);
}

fn on_edit_colors_response(dialog: *c.GtkDialog, response_id: c_int, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const self: *Sidebar = @ptrCast(@alignCast(user_data));
    if (response_id == c.GTK_RESPONSE_OK) {
        var rgba: c.GdkRGBA = undefined;
        c.gtk_color_chooser_get_rgba(@ptrCast(dialog), &rgba);

        const r: u8 = @intFromFloat(rgba.red * 255.0);
        const g: u8 = @intFromFloat(rgba.green * 255.0);
        const b: u8 = @intFromFloat(rgba.blue * 255.0);
        const a: u8 = @intFromFloat(rgba.alpha * 255.0);

        self.engine.setFgColor(r, g, b, a);
        self.recent_colors_manager.add(rgba) catch {};
        _ = c.g_idle_add(@ptrCast(&rebuild_recent_colors_idle), self);
    }
    c.gtk_window_destroy(@ptrCast(dialog));
}

fn on_edit_colors_clicked(_: *c.GtkButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const self: *Sidebar = @ptrCast(@alignCast(user_data));
    const dialog = c.gtk_color_chooser_dialog_new("Edit Colors", self.window);
    if (self.recent_colors_manager.colors.items.len > 0) {
        c.gtk_color_chooser_add_palette(
            @ptrCast(dialog),
            c.GTK_ORIENTATION_HORIZONTAL,
            5,
            @intCast(self.recent_colors_manager.colors.items.len),
            self.recent_colors_manager.colors.items.ptr,
        );
    }
    c.gtk_color_chooser_set_use_alpha(@ptrCast(dialog), 1);

    const fg = self.engine.fg_color;
    const rgba = c.GdkRGBA{
        .red = @as(f32, @floatFromInt(fg[0])) / 255.0,
        .green = @as(f32, @floatFromInt(fg[1])) / 255.0,
        .blue = @as(f32, @floatFromInt(fg[2])) / 255.0,
        .alpha = @as(f32, @floatFromInt(fg[3])) / 255.0,
    };
    c.gtk_color_chooser_set_rgba(@ptrCast(dialog), &rgba);

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&on_edit_colors_response), self, null, 0);
    c.gtk_window_present(@ptrCast(dialog));
}

fn on_layer_selected(_: *c.GtkListBox, row: ?*c.GtkListBoxRow, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const self: *Sidebar = @ptrCast(@alignCast(user_data));
    if (row) |r| {
        const index_in_list = c.gtk_list_box_row_get_index(r);
        if (index_in_list >= 0) {
            const k: usize = @intCast(index_in_list);
            if (k < self.engine.layers.list.items.len) {
                // List is reversed (top layer first)
                const layer_idx = self.engine.layers.list.items.len - 1 - k;
                self.engine.setActiveLayer(layer_idx);
            }
        }
    }
}

fn on_layer_add(_: *c.GtkButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const self: *Sidebar = @ptrCast(@alignCast(user_data));
    self.engine.addLayer("New Layer") catch return;
    self.refreshLayers();
    self.refreshUndo();
    self.callbacks.request_update();
}

fn on_layer_remove(_: *c.GtkButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const self: *Sidebar = @ptrCast(@alignCast(user_data));
    if (self.engine.layers.list.items.len > 0) {
        self.engine.removeLayer(self.engine.layers.active_index);
        self.refreshLayers();
        self.refreshUndo();
        self.callbacks.request_update();
    }
}

fn on_layer_up(_: *c.GtkButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const self: *Sidebar = @ptrCast(@alignCast(user_data));
    const idx = self.engine.layers.active_index;
    if (idx + 1 < self.engine.layers.list.items.len) {
        self.engine.reorderLayer(idx, idx + 1);
        self.refreshLayers();
        self.refreshUndo();
        self.callbacks.request_update();
    }
}

fn on_layer_down(_: *c.GtkButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const self: *Sidebar = @ptrCast(@alignCast(user_data));
    const idx = self.engine.layers.active_index;
    if (idx > 0) {
        self.engine.reorderLayer(idx, idx - 1);
        self.refreshLayers();
        self.refreshUndo();
        self.callbacks.request_update();
    }
}

fn on_layer_visibility_toggled(btn: *c.GtkCheckButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const self: *Sidebar = @ptrCast(@alignCast(user_data));
    const idx_ptr = c.g_object_get_data(@ptrCast(btn), "layer-index");
    const idx: usize = @intFromPtr(idx_ptr);
    self.engine.toggleLayerVisibility(idx);
    self.callbacks.request_update();
    self.refreshUndo();
}

fn on_layer_lock_toggled(btn: *c.GtkCheckButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const self: *Sidebar = @ptrCast(@alignCast(user_data));
    const idx_ptr = c.g_object_get_data(@ptrCast(btn), "layer-index");
    const idx: usize = @intFromPtr(idx_ptr);
    self.engine.toggleLayerLock(idx);
    self.refreshUndo();
}
