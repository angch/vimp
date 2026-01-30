const std = @import("std");
const c = @import("../c.zig").c;
const tool_mod = @import("tool.zig");
const GimpTool = tool_mod.GimpTool;
const GimpToolClass = tool_mod.GimpToolClass;
const GList = tool_mod.GList;
const GimpDisplay = tool_mod.GimpDisplay;
const GimpCanvasItem = tool_mod.GimpCanvasItem;

pub const GimpToolWidget = opaque {};

pub const GimpDrawTool = extern struct {
    parent_instance: GimpTool,

    display: *GimpDisplay,
    paused_count: c.gint,
    draw_timeout: c.guint,
    last_draw_time: u64, // guint64

    widget: *GimpToolWidget,
    default_status: [*c]c.gchar,
    preview: *GimpCanvasItem,
    item: *GimpCanvasItem,
    group_stack: *GList,
};

pub const GimpDrawToolClass = extern struct {
    parent_class: GimpToolClass,

    draw: ?*const fn (*GimpDrawTool) callconv(.C) void,
};
