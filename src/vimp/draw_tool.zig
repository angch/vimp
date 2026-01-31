const std = @import("std");
const c = @import("../c.zig").c;
const tool_mod = @import("tool.zig");
const VimpTool = tool_mod.VimpTool;
const VimpToolClass = tool_mod.VimpToolClass;
const GList = tool_mod.GList;
const VimpDisplay = tool_mod.VimpDisplay;
const VimpCanvasItem = tool_mod.VimpCanvasItem;

pub const VimpToolWidget = opaque {};

pub const VimpDrawTool = extern struct {
    parent_instance: VimpTool,

    display: *VimpDisplay,
    paused_count: c.gint,
    draw_timeout: c.guint,
    last_draw_time: u64, // guint64

    widget: *VimpToolWidget,
    default_status: [*c]c.gchar,
    preview: *VimpCanvasItem,
    item: *VimpCanvasItem,
    group_stack: *GList,
};

pub const VimpDrawToolClass = extern struct {
    parent_class: VimpToolClass,

    draw: ?*const fn (*VimpDrawTool) callconv(.C) void,
};
