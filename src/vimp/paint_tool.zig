const std = @import("std");
const c = @import("../c.zig").c;
const tool_mod = @import("tool.zig");
const color_tool_mod = @import("color_tool.zig");
const VimpColorTool = color_tool_mod.VimpColorTool;
const VimpColorToolClass = color_tool_mod.VimpColorToolClass;

const VimpDisplay = tool_mod.VimpDisplay;
const GList = tool_mod.GList;
const VimpCanvasItem = tool_mod.VimpCanvasItem;

pub const VimpPaintCore = opaque {}; // Complex struct in paint/gimppaintcore.h
pub const VimpDrawable = opaque {}; // In core/core-types.h

pub const VimpPaintTool = extern struct {
    parent_instance: VimpColorTool,

    active: c.gboolean,
    pick_colors: c.gboolean,
    can_multi_paint: c.gboolean,
    draw_line: c.gboolean,

    show_cursor: c.gboolean,
    draw_brush: c.gboolean,
    snap_brush: c.gboolean,
    draw_fallback: c.gboolean,
    fallback_size: c.gint,
    draw_circle: c.gboolean,
    circle_size: c.gint,

    status: [*c]const c.gchar,
    status_line: [*c]const c.gchar,
    status_ctrl: [*c]const c.gchar,

    core: *VimpPaintCore,

    display: *VimpDisplay,
    drawables: *GList,

    cursor_x: f64,
    cursor_y: f64,

    paint_x: f64,
    paint_y: f64,
};

pub const VimpPaintToolClass = extern struct {
    parent_class: VimpColorToolClass,

    paint_prepare: ?*const fn (*VimpPaintTool, *VimpDisplay) callconv(.C) void,
    paint_start: ?*const fn (*VimpPaintTool) callconv(.C) void,
    paint_end: ?*const fn (*VimpPaintTool) callconv(.C) void,
    paint_flush: ?*const fn (*VimpPaintTool) callconv(.C) void,

    get_outline: ?*const fn (*VimpPaintTool, *VimpDisplay, f64, f64) callconv(.C) *VimpCanvasItem,

    is_alpha_only: ?*const fn (*VimpPaintTool, *VimpDrawable) callconv(.C) c.gboolean,
};
