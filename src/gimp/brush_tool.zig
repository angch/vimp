const std = @import("std");
const c = @import("../c.zig").c;
const tool_mod = @import("tool.zig");
const paint_tool_mod = @import("paint_tool.zig");
const GimpPaintTool = paint_tool_mod.GimpPaintTool;
const GimpPaintToolClass = paint_tool_mod.GimpPaintToolClass;

const GimpDisplay = tool_mod.GimpDisplay;
const GimpCanvasItem = tool_mod.GimpCanvasItem;

pub const GimpBezierDesc = opaque {}; // cairo_path_t or void*

pub const GimpBrushTool = extern struct {
    parent_instance: GimpPaintTool,

    boundary: *GimpBezierDesc,
    boundary_width: c.gint,
    boundary_height: c.gint,
    boundary_scale: f64,
    boundary_aspect_ratio: f64,
    boundary_angle: f64,
    boundary_reflect: c.gboolean,
    boundary_hardness: f64,
};

pub const GimpBrushToolClass = extern struct {
    parent_class: GimpPaintToolClass,
    // No new virtual methods in GimpBrushToolClass
};
