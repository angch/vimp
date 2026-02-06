const std = @import("std");
const c = @import("../c.zig").c;
const Engine = @import("../engine.zig").Engine;
const Tool = @import("../tools.zig").Tool;
const ToolOptionsPanel = @import("../widgets/tool_options_panel.zig").ToolOptionsPanel;
const ColorPalette = @import("../widgets/color_palette.zig").ColorPalette;
const Assets = @import("../assets.zig");
const RecentColorsManager = @import("../recent_colors.zig").RecentColorsManager;

pub const ToolEntry = struct {
    tool: Tool,
    icon_data: ?[]const u8 = null,
    icon_name: ?[:0]const u8 = null,
    tooltip: [:0]const u8,
};

pub const SidebarCallbacks = struct {
    tool_toggled: c.GCallback,
    color_changed: c.GCallback,
    edit_colors_clicked: c.GCallback,
    layer_selected: c.GCallback,
    layer_add: c.GCallback,
    layer_remove: c.GCallback,
    layer_up: c.GCallback,
    layer_down: c.GCallback,
    queue_draw_fn: *const fn () void,
    palette_color_changed: *const fn () void,
    rebuild_recent_colors: ?*const fn (?*anyopaque) callconv(.c) c.gboolean,
};

const ToolGroupItemContext = struct {
    main_btn: *c.GtkWidget,
    active_tool_ref: *Tool,
    tool: Tool,
    icon_data: ?[]const u8,
    icon_name: ?[:0]const u8,
    tooltip: [:0]const u8,
    popover: *c.GtkPopover,
    callback: c.GCallback, // We need to store the callback to call it manually
};

fn destroy_tool_group_item_context(data: ?*anyopaque, _: ?*c.GClosure) callconv(std.builtin.CallingConvention.c) void {
    if (data) |d| {
        const ctx: *ToolGroupItemContext = @ptrCast(@alignCast(d));
        std.heap.c_allocator.destroy(ctx);
    }
}

fn on_group_item_clicked(_: *c.GtkButton, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *ToolGroupItemContext = @ptrCast(@alignCast(user_data));

    // 1. Update active tool ref
    ctx.active_tool_ref.* = ctx.tool;

    // 2. Update Main Button Icon/Tooltip
    var img: *c.GtkWidget = undefined;
    if (ctx.icon_data) |data| {
        img = Assets.getIconWidget(data, 24);
    } else if (ctx.icon_name) |name| {
        img = c.gtk_image_new_from_icon_name(name);
        c.gtk_widget_set_size_request(img, 24, 24);
    } else {
        img = c.gtk_image_new_from_icon_name("image-missing-symbolic");
        c.gtk_widget_set_size_request(img, 24, 24);
    }

    c.gtk_button_set_child(@ptrCast(ctx.main_btn), img);
    c.gtk_widget_set_tooltip_text(ctx.main_btn, ctx.tooltip);

    // 3. Activate Main Button
    const is_active = c.gtk_toggle_button_get_active(@ptrCast(ctx.main_btn)) != 0;
    if (!is_active) {
        c.gtk_toggle_button_set_active(@ptrCast(ctx.main_btn), 1);
    } else {
        // Force update by calling the callback manually
        // The callback signature is (button, user_data)
        // We cast it to the correct function pointer type
        const FuncType = *const fn (*c.GtkToggleButton, ?*anyopaque) callconv(.c) void;
        const func: FuncType = @ptrCast(ctx.callback);
        func(@ptrCast(ctx.main_btn), ctx.active_tool_ref);
    }

    // 4. Hide Popover
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

    // Tool state
    active_selection_tool: Tool = .rect_select,
    active_shape_tool: Tool = .rect_shape,
    active_paint_tool: Tool = .brush,
    active_line_tool: Tool = .line,

    // Tool constants (pointers used as user_data)
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

    // Context references
    engine: *Engine,
    recent_colors_manager: *RecentColorsManager,
    callbacks: SidebarCallbacks,

    // We need to store allocator to destroy if needed, though Sidebar usually lives for app duration
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator, engine: *Engine, recent_colors_manager: *RecentColorsManager, callbacks: SidebarCallbacks, window: *c.GtkWindow) !*Sidebar {
        const self = try allocator.create(Sidebar);
        self.* = .{
            .widget = undefined,
            .engine = engine,
            .recent_colors_manager = recent_colors_manager,
            .callbacks = callbacks,
            .allocator = allocator,
        };

        // Sidebar (Left / Sidebar Pane)
        const sidebar = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
        c.gtk_widget_set_size_request(sidebar, 160, -1);
        c.gtk_widget_add_css_class(sidebar, "sidebar");
        self.widget = sidebar;

        // Tools Header
        const tools_label = c.gtk_label_new("Tools");
        c.gtk_box_append(@ptrCast(sidebar), tools_label);

        // Tools Container
        const tools_container = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 5);
        c.gtk_widget_set_halign(tools_container, c.GTK_ALIGN_CENTER);
        c.gtk_box_append(@ptrCast(sidebar), tools_container);

        var tools_row_box: ?*c.GtkWidget = null;
        var tools_in_row: usize = 0;

        // Paint Group
        const paint_entries = [_]ToolEntry{
            .{ .tool = .brush, .icon_data = Assets.brush_png, .tooltip = "Brush" },
            .{ .tool = .pencil, .icon_data = Assets.pencil_png, .tooltip = "Pencil" },
            .{ .tool = .airbrush, .icon_data = Assets.airbrush_png, .tooltip = "Airbrush" },
        };
        const paint_group_btn = try self.createToolGroup(&self.active_paint_tool, &paint_entries, null);
        self.appendTool(tools_container, paint_group_btn, &tools_row_box, &tools_in_row);
        self.default_tool_btn = paint_group_btn;

        // Eraser
        const eraser_btn = self.createToolButton(&self.eraser_tool, Assets.eraser_png, null, "Eraser", @ptrCast(paint_group_btn));
        self.appendTool(tools_container, eraser_btn, &tools_row_box, &tools_in_row);

        // Bucket Fill
        const fill_btn = self.createToolButton(&self.bucket_fill_tool, Assets.bucket_png, null, "Bucket Fill", @ptrCast(paint_group_btn));
        self.appendTool(tools_container, fill_btn, &tools_row_box, &tools_in_row);

        // Selection Group
        const select_entries = [_]ToolEntry{
            .{ .tool = .rect_select, .icon_data = Assets.rect_select_svg, .tooltip = "Rectangle Select" },
            .{ .tool = .ellipse_select, .icon_data = Assets.ellipse_select_svg, .tooltip = "Ellipse Select" },
            .{ .tool = .lasso, .icon_data = Assets.lasso_select_svg, .tooltip = "Lasso Select" },
        };
        const select_group_btn = try self.createToolGroup(&self.active_selection_tool, &select_entries, @ptrCast(paint_group_btn));
        self.appendTool(tools_container, select_group_btn, &tools_row_box, &tools_in_row);

        // Text Tool
        const text_btn = self.createToolButton(&self.text_tool, Assets.text_svg, null, "Text Tool", @ptrCast(paint_group_btn));
        self.appendTool(tools_container, text_btn, &tools_row_box, &tools_in_row);

        // Shapes Group
        const shape_entries = [_]ToolEntry{
            .{ .tool = .rect_shape, .icon_data = Assets.rect_shape_svg, .tooltip = "Rectangle Tool" },
            .{ .tool = .ellipse_shape, .icon_data = Assets.ellipse_shape_svg, .tooltip = "Ellipse Tool" },
            .{ .tool = .rounded_rect_shape, .icon_data = Assets.rounded_rect_shape_svg, .tooltip = "Rounded Rectangle Tool" },
            .{ .tool = .polygon, .icon_data = Assets.polygon_svg, .tooltip = "Polygon Tool" },
        };
        const shape_group_btn = try self.createToolGroup(&self.active_shape_tool, &shape_entries, @ptrCast(paint_group_btn));
        self.appendTool(tools_container, shape_group_btn, &tools_row_box, &tools_in_row);

        // Unified Transform
        const transform_btn = self.createToolButton(&self.unified_transform_tool, Assets.transform_svg, null, "Unified Transform", @ptrCast(paint_group_btn));
        self.appendTool(tools_container, transform_btn, &tools_row_box, &tools_in_row);

        // Color Picker
        const picker_btn = self.createToolButton(&self.color_picker_tool, Assets.color_picker_svg, null, "Color Picker", @ptrCast(paint_group_btn));
        self.appendTool(tools_container, picker_btn, &tools_row_box, &tools_in_row);

        // Gradient Tool
        const gradient_btn = self.createToolButton(&self.gradient_tool, Assets.gradient_svg, null, "Gradient Tool", @ptrCast(paint_group_btn));
        self.appendTool(tools_container, gradient_btn, &tools_row_box, &tools_in_row);

        // Lines Group
        const line_entries = [_]ToolEntry{
            .{ .tool = .line, .icon_data = Assets.line_svg, .tooltip = "Line Tool (Shift to snap)" },
            .{ .tool = .curve, .icon_data = Assets.curve_svg, .tooltip = "Curve Tool (Drag Line -> Bend 1 -> Bend 2)" },
        };
        const line_group_btn = try self.createToolGroup(&self.active_line_tool, &line_entries, @ptrCast(paint_group_btn));
        self.appendTool(tools_container, line_group_btn, &tools_row_box, &tools_in_row);

        // Separator
        c.gtk_box_append(@ptrCast(sidebar), c.gtk_separator_new(c.GTK_ORIENTATION_HORIZONTAL));

        // Color Palette
        // We need a wrapper callback for update_color_btn_visual.
        // Actually ColorPalette expects `*const fn () void`.
        // We can pass a wrapper that calls self.updateColorButton() but we need a closure or global.
        // Since we are moving `update_color_btn_visual` to Sidebar, ColorPalette needs to be updated or we provide a static wrapper.
        // But ColorPalette interface is simple function pointer.
        // For now, let's pass the one from callbacks.
        const palette = ColorPalette.create(engine, callbacks.palette_color_changed);
        c.gtk_box_append(@ptrCast(sidebar), palette);

        // Color Selection & Edit
        const color_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 5);
        c.gtk_widget_set_halign(color_box, c.GTK_ALIGN_CENTER);
        c.gtk_box_append(@ptrCast(sidebar), color_box);

        const color_btn = self.createColorButton();
        self.color_btn = color_btn;
        c.gtk_box_append(@ptrCast(color_box), color_btn);

        const edit_colors_btn = c.gtk_button_new_with_mnemonic("_Edit Colors");
        _ = c.g_signal_connect_data(edit_colors_btn, "clicked", callbacks.edit_colors_clicked, window, null, 0);
        c.gtk_box_append(@ptrCast(color_box), edit_colors_btn);

        // Tool Options Panel
        const tool_options_panel = ToolOptionsPanel.create(engine, callbacks.queue_draw_fn);
        self.tool_options_panel = tool_options_panel;
        c.gtk_box_append(@ptrCast(sidebar), tool_options_panel.widget());
        // Initialize with default tool (Brush)
        tool_options_panel.update(.brush);

        // Layers Section
        c.gtk_box_append(@ptrCast(sidebar), c.gtk_separator_new(c.GTK_ORIENTATION_HORIZONTAL));
        c.gtk_box_append(@ptrCast(sidebar), c.gtk_label_new("Layers"));

        const layers_list = c.gtk_list_box_new();
        c.gtk_widget_set_vexpand(layers_list, 1);
        c.gtk_list_box_set_selection_mode(@ptrCast(layers_list), c.GTK_SELECTION_SINGLE);
        _ = c.g_signal_connect_data(layers_list, "row-selected", callbacks.layer_selected, null, null, 0);

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
        _ = c.g_signal_connect_data(add_layer_btn, "clicked", callbacks.layer_add, null, null, 0);

        const remove_layer_btn = c.gtk_button_new_from_icon_name("list-remove-symbolic");
        c.gtk_widget_set_tooltip_text(remove_layer_btn, "Remove Layer");
        c.gtk_box_append(@ptrCast(layers_btns), remove_layer_btn);
        _ = c.g_signal_connect_data(remove_layer_btn, "clicked", callbacks.layer_remove, null, null, 0);

        const up_layer_btn = c.gtk_button_new_from_icon_name("go-up-symbolic");
        c.gtk_widget_set_tooltip_text(up_layer_btn, "Move Up");
        c.gtk_box_append(@ptrCast(layers_btns), up_layer_btn);
        _ = c.g_signal_connect_data(up_layer_btn, "clicked", callbacks.layer_up, null, null, 0);

        const down_layer_btn = c.gtk_button_new_from_icon_name("go-down-symbolic");
        c.gtk_widget_set_tooltip_text(down_layer_btn, "Move Down");
        c.gtk_box_append(@ptrCast(layers_btns), down_layer_btn);
        _ = c.g_signal_connect_data(down_layer_btn, "clicked", callbacks.layer_down, null, null, 0);

        // Undo History Section
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

    fn createToolButton(self: *Sidebar, tool_val: *Tool, icon_data: ?[]const u8, icon_name: ?[:0]const u8, tooltip: [:0]const u8, group: ?*c.GtkToggleButton) *c.GtkWidget {
        const btn = if (group) |_| c.gtk_toggle_button_new() else c.gtk_toggle_button_new();
        if (group) |g| c.gtk_toggle_button_set_group(@ptrCast(btn), g);

        var img: *c.GtkWidget = undefined;
        if (icon_data) |data| {
            img = Assets.getIconWidget(data, 24);
        } else if (icon_name) |name| {
            img = c.gtk_image_new_from_icon_name(name);
            c.gtk_widget_set_size_request(img, 24, 24);
        } else {
            img = c.gtk_image_new_from_icon_name("image-missing-symbolic");
            c.gtk_widget_set_size_request(img, 24, 24);
        }

        c.gtk_button_set_child(@ptrCast(btn), img);
        c.gtk_widget_set_tooltip_text(btn, tooltip);

        _ = c.g_signal_connect_data(btn, "toggled", self.callbacks.tool_toggled, tool_val, null, 0);
        return btn;
    }

    fn createToolGroup(self: *Sidebar, active_tool_ref: *Tool, entries: []const ToolEntry, group: ?*c.GtkToggleButton) !*c.GtkWidget {
        const btn = if (group) |_| c.gtk_toggle_button_new() else c.gtk_toggle_button_new();
        if (group) |g| c.gtk_toggle_button_set_group(@ptrCast(btn), g);

        // Set initial state
        var current_entry: ?ToolEntry = null;
        for (entries) |e| {
            if (e.tool == active_tool_ref.*) {
                current_entry = e;
                break;
            }
        }
        if (current_entry == null) current_entry = entries[0];

        var img: *c.GtkWidget = undefined;
        if (current_entry.?.icon_data) |data| {
            img = Assets.getIconWidget(data, 24);
        } else if (current_entry.?.icon_name) |name| {
            img = c.gtk_image_new_from_icon_name(name);
            c.gtk_widget_set_size_request(img, 24, 24);
        } else {
            img = c.gtk_image_new_from_icon_name("image-missing-symbolic");
            c.gtk_widget_set_size_request(img, 24, 24);
        }

        c.gtk_button_set_child(@ptrCast(btn), img);
        c.gtk_widget_set_tooltip_text(btn, current_entry.?.tooltip);

        _ = c.g_signal_connect_data(btn, "toggled", self.callbacks.tool_toggled, active_tool_ref, null, 0);

        // Popover
        const popover = c.gtk_popover_new();
        const grid = c.gtk_grid_new();
        c.gtk_grid_set_row_spacing(@ptrCast(grid), 5);
        c.gtk_grid_set_column_spacing(@ptrCast(grid), 5);
        c.gtk_widget_set_margin_top(grid, 5);
        c.gtk_widget_set_margin_bottom(grid, 5);
        c.gtk_widget_set_margin_start(grid, 5);
        c.gtk_widget_set_margin_end(grid, 5);
        c.gtk_popover_set_child(@ptrCast(popover), grid);

        for (entries, 0..) |entry, i| {
            const item_btn = c.gtk_button_new();
            var item_img: *c.GtkWidget = undefined;
            if (entry.icon_data) |data| {
                item_img = Assets.getIconWidget(data, 24);
            } else if (entry.icon_name) |name| {
                item_img = c.gtk_image_new_from_icon_name(name);
                c.gtk_widget_set_size_request(item_img, 24, 24);
            } else {
                item_img = c.gtk_image_new_from_icon_name("image-missing-symbolic");
                c.gtk_widget_set_size_request(item_img, 24, 24);
            }

            c.gtk_button_set_child(@ptrCast(item_btn), item_img);
            c.gtk_widget_set_tooltip_text(item_btn, entry.tooltip);

            const col = @as(c_int, @intCast(i % 3));
            const row = @as(c_int, @intCast(i / 3));
            c.gtk_grid_attach(@ptrCast(grid), item_btn, col, row, 1, 1);

            const ctx = try std.heap.c_allocator.create(ToolGroupItemContext);
            ctx.* = .{
                .main_btn = btn,
                .active_tool_ref = active_tool_ref,
                .tool = entry.tool,
                .icon_data = entry.icon_data,
                .icon_name = entry.icon_name,
                .tooltip = entry.tooltip,
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
                5, // colors per line
                @intCast(self.recent_colors_manager.colors.items.len),
                self.recent_colors_manager.colors.items.ptr,
            );
        }
    }

    fn createColorButton(self: *Sidebar) *c.GtkWidget {
        const btn = c.gtk_color_button_new();
        c.gtk_widget_set_valign(btn, c.GTK_ALIGN_START);
        c.gtk_widget_set_halign(btn, c.GTK_ALIGN_CENTER);

        _ = c.g_signal_connect_data(btn, "color-set", self.callbacks.color_changed, null, null, 0);

        self.populateRecentColors(@ptrCast(btn));
        return btn;
    }

    pub fn rebuildRecentColors(self: *Sidebar) void {
        if (self.color_btn == null or self.tool_options_panel == null) return;

        const parent = c.gtk_widget_get_parent(self.color_btn.?);
        if (parent == null) return;

        c.gtk_box_remove(@ptrCast(parent), self.color_btn.?);

        // Recreate button
        self.color_btn = self.createColorButton();

        // Restore color from engine
        const fg = self.engine.fg_color;
        const rgba = c.GdkRGBA{
            .red = @as(f32, @floatFromInt(fg[0])) / 255.0,
            .green = @as(f32, @floatFromInt(fg[1])) / 255.0,
            .blue = @as(f32, @floatFromInt(fg[2])) / 255.0,
            .alpha = @as(f32, @floatFromInt(fg[3])) / 255.0,
        };
        c.gtk_color_chooser_set_rgba(@ptrCast(self.color_btn.?), &rgba);

        c.gtk_box_prepend(@ptrCast(parent), self.color_btn.?);

        // Restore focus
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
};
