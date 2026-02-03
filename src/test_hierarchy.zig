const std = @import("std");
const tool_mod = @import("vimp/tool.zig");
const draw_tool_mod = @import("vimp/draw_tool.zig");
const color_tool_mod = @import("vimp/color_tool.zig");
const paint_tool_mod = @import("vimp/paint_tool.zig");
const brush_tool_mod = @import("vimp/brush_tool.zig");

const c = @cImport({
    @cDefine("G_LOG_DOMAIN", "\"Vimp-Tool\"");
    @cDefine("GIMP_COMPILATION", "1");
    // We need basic types first
    @cInclude("gtk/gtk.h");
    @cInclude("gdk/gdk.h");
    @cInclude("gegl.h");
    @cInclude("babl/babl.h");

    // Mock GTK3 types removed in GTK4 to allow GIMP headers to compile
    @cInclude("vimp/mock_gtk3.h");

    // GIMP headers
    @cInclude("app/config/config-types.h");
    @cInclude("app/core/core-types.h");

    // Manual typedefs that might be missing if we don't include everything in perfect order
    // But let's try including the type headers first
    @cInclude("app/paint/paint-types.h"); // Dependency for tools-types.h
    @cInclude("app/display/display-types.h"); // Dependency for tools-types.h
    @cInclude("app/tools/tools-types.h");

    @cInclude("app/tools/gimptool.h");
    @cInclude("app/tools/gimpdrawtool.h");
    @cInclude("app/tools/gimpcolortool.h");
    @cInclude("app/tools/gimppainttool.h");
    @cInclude("app/tools/gimpbrushtool.h");
});

fn checkOffset(comptime ZigType: type, comptime CType: type, comptime field: []const u8) !void {
    const zig_offset = @bitOffsetOf(ZigType, field);
    const c_offset = @bitOffsetOf(CType, field);
    if (zig_offset != c_offset) {
        std.debug.print("Offset mismatch for {s}.{s}: Zig={} C={}\n", .{ @typeName(ZigType), field, zig_offset, c_offset });
        return error.LayoutMismatch;
    }
}

test "VimpTool offset verification" {
    try checkOffset(tool_mod.VimpTool, c.struct__GimpTool, "parent_instance");
    try checkOffset(tool_mod.VimpTool, c.struct__GimpTool, "tool_info");
    try checkOffset(tool_mod.VimpTool, c.struct__GimpTool, "ID");
    try checkOffset(tool_mod.VimpTool, c.struct__GimpTool, "control");
    try checkOffset(tool_mod.VimpTool, c.struct__GimpTool, "last_pointer_coords");
    try checkOffset(tool_mod.VimpTool, c.struct__GimpTool, "button_press_coords");
}

test "VimpDrawTool offset verification" {
    try checkOffset(draw_tool_mod.VimpDrawTool, c.struct__GimpDrawTool, "parent_instance");
    try checkOffset(draw_tool_mod.VimpDrawTool, c.struct__GimpDrawTool, "display");
    try checkOffset(draw_tool_mod.VimpDrawTool, c.struct__GimpDrawTool, "widget");
}

test "VimpColorTool offset verification" {
    try checkOffset(color_tool_mod.VimpColorTool, c.struct__GimpColorTool, "parent_instance");
    try checkOffset(color_tool_mod.VimpColorTool, c.struct__GimpColorTool, "enabled");
    try checkOffset(color_tool_mod.VimpColorTool, c.struct__GimpColorTool, "options");
}

test "VimpPaintTool offset verification" {
    try checkOffset(paint_tool_mod.VimpPaintTool, c.struct__GimpPaintTool, "parent_instance");
    try checkOffset(paint_tool_mod.VimpPaintTool, c.struct__GimpPaintTool, "core");
    try checkOffset(paint_tool_mod.VimpPaintTool, c.struct__GimpPaintTool, "cursor_x");
    try checkOffset(paint_tool_mod.VimpPaintTool, c.struct__GimpPaintTool, "paint_x");
}

test "VimpBrushTool offset verification" {
    try checkOffset(brush_tool_mod.VimpBrushTool, c.struct__GimpBrushTool, "parent_instance");
    try checkOffset(brush_tool_mod.VimpBrushTool, c.struct__GimpBrushTool, "boundary");
    try checkOffset(brush_tool_mod.VimpBrushTool, c.struct__GimpBrushTool, "boundary_hardness");
}

test {
    _ = @import("engine.zig");
    _ = @import("widgets/text_style_editor.zig");
    _ = @import("widgets/import_dialogs.zig");
    _ = @import("widgets/open_location_dialog.zig");
    _ = @import("widgets/color_palette.zig");
    _ = @import("recent.zig");
    _ = @import("recent_colors.zig");
    _ = @import("raw_loader.zig");
    _ = @import("canvas_utils.zig");
    _ = @import("engine_curve_test.zig");
    _ = @import("test_polygon.zig");
    _ = @import("test_rounded_rect.zig");
    _ = @import("test_zoom_pan.zig");
    _ = @import("test_paint_colors.zig");
}
