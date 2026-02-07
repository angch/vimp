const std = @import("std");
const c = @import("../c.zig").c;
const Tool = @import("types.zig").Tool;
const ToolInterface = @import("interface.zig").ToolInterface;
const Assets = @import("../assets.zig");

const BrushTool = @import("brush.zig").BrushTool;
const PencilTool = @import("pencil.zig").PencilTool;
const BucketFillTool = @import("bucket_fill.zig").BucketFillTool;
const EraserTool = @import("eraser.zig").EraserTool;
const AirbrushTool = @import("airbrush.zig").AirbrushTool;
const RectSelectTool = @import("rect_select.zig").RectSelectTool;
const EllipseSelectTool = @import("ellipse_select.zig").EllipseSelectTool;
const LassoTool = @import("lasso.zig").LassoTool;
const RectShapeTool = @import("rect_shape.zig").RectShapeTool;
const EllipseShapeTool = @import("ellipse_shape.zig").EllipseShapeTool;
const RoundedRectShapeTool = @import("rounded_rect_shape.zig").RoundedRectShapeTool;
const LineTool = @import("line.zig").LineTool;
const CurveTool = @import("curve.zig").CurveTool;
const PolygonTool = @import("polygon.zig").PolygonTool;
const TextTool = @import("text.zig").TextTool;
const GradientTool = @import("gradient.zig").GradientTool;
const ColorPickerTool = @import("color_picker.zig").ColorPickerTool;
const UnifiedTransformTool = @import("unified_transform.zig").UnifiedTransformTool;

pub const ToolCreationContext = struct {
    window: ?*c.GtkWindow = null,
    color_picked_cb: ?*const fn ([4]u8) void = null,
    text_complete_cb: ?*const fn () void = null,
};

pub const ToolFactory = struct {
    pub fn createTool(allocator: std.mem.Allocator, tool_type: Tool, ctx: ToolCreationContext) !ToolInterface {
        switch (tool_type) {
            .brush => {
                const tool = try BrushTool.create(allocator);
                return tool.interface();
            },
            .pencil => {
                const tool = try PencilTool.create(allocator);
                return tool.interface();
            },
            .airbrush => {
                const tool = try AirbrushTool.create(allocator);
                return tool.interface();
            },
            .eraser => {
                const tool = try EraserTool.create(allocator);
                return tool.interface();
            },
            .bucket_fill => {
                const tool = try BucketFillTool.create(allocator);
                return tool.interface();
            },
            .rect_select => {
                const tool = try RectSelectTool.create(allocator);
                return tool.interface();
            },
            .ellipse_select => {
                const tool = try EllipseSelectTool.create(allocator);
                return tool.interface();
            },
            .rect_shape => {
                const tool = try RectShapeTool.create(allocator);
                return tool.interface();
            },
            .ellipse_shape => {
                const tool = try EllipseShapeTool.create(allocator);
                return tool.interface();
            },
            .rounded_rect_shape => {
                const tool = try RoundedRectShapeTool.create(allocator);
                return tool.interface();
            },
            .unified_transform => {
                const tool = try UnifiedTransformTool.create(allocator);
                return tool.interface();
            },
            .color_picker => {
                const tool = try ColorPickerTool.create(allocator, ctx.color_picked_cb);
                return tool.interface();
            },
            .gradient => {
                const tool = try GradientTool.create(allocator);
                return tool.interface();
            },
            .line => {
                const tool = try LineTool.create(allocator);
                return tool.interface();
            },
            .curve => {
                const tool = try CurveTool.create(allocator);
                return tool.interface();
            },
            .polygon => {
                const tool = try PolygonTool.create(allocator);
                return tool.interface();
            },
            .lasso => {
                const tool = try LassoTool.create(allocator);
                return tool.interface();
            },
            .text => {
                const tool = try TextTool.create(allocator, ctx.window, ctx.text_complete_cb);
                return tool.interface();
            },
        }
    }

    pub fn getToolName(tool_type: Tool) []const u8 {
        return switch (tool_type) {
            .brush => "Brush",
            .pencil => "Pencil",
            .airbrush => "Airbrush",
            .eraser => "Eraser",
            .bucket_fill => "Bucket Fill",
            .rect_select => "Rectangle Select",
            .ellipse_select => "Ellipse Select",
            .lasso => "Lasso Select",
            .rect_shape => "Rectangle Tool",
            .ellipse_shape => "Ellipse Tool",
            .rounded_rect_shape => "Rounded Rectangle Tool",
            .polygon => "Polygon Tool",
            .text => "Text Tool",
            .unified_transform => "Unified Transform",
            .color_picker => "Color Picker",
            .gradient => "Gradient Tool",
            .line => "Line Tool",
            .curve => "Curve Tool",
        };
    }

    pub fn getToolIconData(tool_type: Tool) ?[]const u8 {
        return switch (tool_type) {
            .brush => Assets.brush_png,
            .pencil => Assets.pencil_png,
            .airbrush => Assets.airbrush_png,
            .eraser => Assets.eraser_png,
            .bucket_fill => Assets.bucket_png,
            .rect_select => Assets.rect_select_svg,
            .ellipse_select => Assets.ellipse_select_svg,
            .lasso => Assets.lasso_select_svg,
            .rect_shape => Assets.rect_shape_svg,
            .ellipse_shape => Assets.ellipse_shape_svg,
            .rounded_rect_shape => Assets.rounded_rect_shape_svg,
            .polygon => Assets.polygon_svg,
            .text => Assets.text_svg,
            .unified_transform => Assets.transform_svg,
            .color_picker => Assets.color_picker_svg,
            .gradient => Assets.gradient_svg,
            .line => Assets.line_svg,
            .curve => Assets.curve_svg,
        };
    }

    pub fn getToolTooltip(tool_type: Tool) [:0]const u8 {
        return switch (tool_type) {
            .brush => "Brush",
            .pencil => "Pencil",
            .airbrush => "Airbrush",
            .eraser => "Eraser",
            .bucket_fill => "Bucket Fill",
            .rect_select => "Rectangle Select",
            .ellipse_select => "Ellipse Select",
            .lasso => "Lasso Select",
            .rect_shape => "Rectangle Tool",
            .ellipse_shape => "Ellipse Tool",
            .rounded_rect_shape => "Rounded Rectangle Tool",
            .polygon => "Polygon Tool",
            .text => "Text Tool",
            .unified_transform => "Unified Transform",
            .color_picker => "Color Picker",
            .gradient => "Gradient Tool",
            .line => "Line Tool (Shift to snap)",
            .curve => "Curve Tool (Drag Line -> Bend 1 -> Bend 2)",
        };
    }
};

test "ToolFactory instantiation" {
    // We mock the callbacks
    const callbacks = struct {
        fn on_pick(_: [4]u8) void {}
        fn on_complete() void {}
    };

    const ctx = ToolCreationContext{
        .window = null,
        .color_picked_cb = &callbacks.on_pick,
        .text_complete_cb = &callbacks.on_complete,
    };

    // Try creating every tool type
    inline for (std.meta.fields(Tool)) |field| {
        const tool_enum = @field(Tool, field.name);

        // Verify metadata
        const name = ToolFactory.getToolName(tool_enum);
        const icon = ToolFactory.getToolIconData(tool_enum);
        const tooltip = ToolFactory.getToolTooltip(tool_enum);

        try std.testing.expect(name.len > 0);
        try std.testing.expect(tooltip.len > 0);
        try std.testing.expect(icon != null);

        // Verify creation
        var tool = try ToolFactory.createTool(std.testing.allocator, tool_enum, ctx);
        tool.destroy(std.testing.allocator);
    }
}
