const std = @import("std");
const c = @import("../c.zig").c;
const tool_mod = @import("tool.zig");
const draw_tool_mod = @import("draw_tool.zig");
const GimpDrawTool = draw_tool_mod.GimpDrawTool;
const GimpDrawToolClass = draw_tool_mod.GimpDrawToolClass;

const GimpDisplay = tool_mod.GimpDisplay;
const GimpCoords = tool_mod.GimpCoords;

pub const GimpColorOptions = opaque {};
pub const GimpColorPickTarget = c.gint; // Enum
pub const GimpColorPickState = c.gint; // Enum
pub const GimpSamplePoint = opaque {};
pub const Babl = opaque {};
pub const GeglColor = opaque {};

pub const GimpColorTool = extern struct {
    parent_instance: GimpDrawTool,

    enabled: c.gboolean,
    options: *GimpColorOptions,
    saved_snap_to: c.gboolean,

    pick_target: GimpColorPickTarget,

    can_pick: c.gboolean,
    center_x: c.gint,
    center_y: c.gint,
    sample_point: *GimpSamplePoint,
};

pub const GimpColorToolClass = extern struct {
    parent_class: GimpDrawToolClass,

    can_pick: ?*const fn (*GimpColorTool, *const GimpCoords, *GimpDisplay) callconv(.C) c.gboolean,
    pick: ?*const fn (*GimpColorTool, *const GimpCoords, *GimpDisplay, **const Babl, c.gpointer, **GeglColor) callconv(.C) c.gboolean,

    picked: ?*const fn (*GimpColorTool, *const GimpCoords, *GimpDisplay, GimpColorPickState, *const Babl, c.gpointer, *GeglColor) callconv(.C) void,
};
