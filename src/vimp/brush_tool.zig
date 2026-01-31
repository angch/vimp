const std = @import("std");
const c = @import("../c.zig").c;
const tool_mod = @import("tool.zig");
const paint_tool_mod = @import("paint_tool.zig");
const VimpPaintTool = paint_tool_mod.VimpPaintTool;
const VimpPaintToolClass = paint_tool_mod.VimpPaintToolClass;

const VimpDisplay = tool_mod.VimpDisplay;
const VimpCanvasItem = tool_mod.VimpCanvasItem;

pub const VimpBezierDesc = opaque {}; // cairo_path_t or void*

pub const VimpBrushTool = extern struct {
    parent_instance: VimpPaintTool,

    boundary: *VimpBezierDesc,
    boundary_width: c.gint,
    boundary_height: c.gint,
    boundary_scale: f64,
    boundary_aspect_ratio: f64,
    boundary_angle: f64,
    boundary_reflect: c.gboolean,
    boundary_hardness: f64,
};

pub const VimpBrushToolClass = extern struct {
    parent_class: VimpPaintToolClass,
    // No new virtual methods in VimpBrushToolClass
};
