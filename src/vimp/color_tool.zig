const std = @import("std");
const c = @import("../c.zig").c;
const tool_mod = @import("tool.zig");
const draw_tool_mod = @import("draw_tool.zig");
const VimpDrawTool = draw_tool_mod.VimpDrawTool;
const VimpDrawToolClass = draw_tool_mod.VimpDrawToolClass;

const VimpDisplay = tool_mod.VimpDisplay;
const VimpCoords = tool_mod.VimpCoords;

pub const VimpColorOptions = opaque {};
pub const VimpColorPickTarget = c.gint; // Enum
pub const VimpColorPickState = c.gint; // Enum
pub const VimpSamplePoint = opaque {};
pub const Babl = opaque {};
pub const GeglColor = opaque {};

pub const VimpColorTool = extern struct {
    parent_instance: VimpDrawTool,

    enabled: c.gboolean,
    options: *VimpColorOptions,
    saved_snap_to: c.gboolean,

    pick_target: VimpColorPickTarget,

    can_pick: c.gboolean,
    center_x: c.gint,
    center_y: c.gint,
    sample_point: *VimpSamplePoint,
};

pub const VimpColorToolClass = extern struct {
    parent_class: VimpDrawToolClass,

    can_pick: ?*const fn (*VimpColorTool, *const VimpCoords, *VimpDisplay) callconv(.C) c.gboolean,
    pick: ?*const fn (*VimpColorTool, *const VimpCoords, *VimpDisplay, **const Babl, c.gpointer, **GeglColor) callconv(.C) c.gboolean,

    picked: ?*const fn (*VimpColorTool, *const VimpCoords, *VimpDisplay, VimpColorPickState, *const Babl, c.gpointer, *GeglColor) callconv(.C) void,
};
