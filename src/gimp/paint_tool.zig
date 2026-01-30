const std = @import("std");
const c = @import("../c.zig").c;
const tool_mod = @import("tool.zig");
const color_tool_mod = @import("color_tool.zig");
const GimpColorTool = color_tool_mod.GimpColorTool;
const GimpColorToolClass = color_tool_mod.GimpColorToolClass;

const GimpDisplay = tool_mod.GimpDisplay;
const GList = tool_mod.GList;
const GimpCanvasItem = tool_mod.GimpCanvasItem;

pub const GimpPaintCore = opaque {}; // Complex struct in paint/gimppaintcore.h
pub const GimpDrawable = opaque {}; // In core/core-types.h

pub const GimpPaintTool = extern struct {
    parent_instance: GimpColorTool,

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

    core: *GimpPaintCore,

    display: *GimpDisplay,
    drawables: *GList,

    cursor_x: f64,
    cursor_y: f64,

    paint_x: f64,
    paint_y: f64,
};

pub const GimpPaintToolClass = extern struct {
    parent_class: GimpColorToolClass,

    paint_prepare: ?*const fn (*GimpPaintTool, *GimpDisplay) callconv(.C) void,
    paint_start: ?*const fn (*GimpPaintTool) callconv(.C) void,
    paint_end: ?*const fn (*GimpPaintTool) callconv(.C) void,
    paint_flush: ?*const fn (*GimpPaintTool) callconv(.C) void,

    get_outline: ?*const fn (*GimpPaintTool, *GimpDisplay, f64, f64) callconv(.C) *GimpCanvasItem,

    is_alpha_only: ?*const fn (*GimpPaintTool, *GimpDrawable) callconv(.C) c.gboolean,
};
