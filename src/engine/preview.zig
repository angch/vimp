const std = @import("std");
const c = @import("../c.zig").c;
const TypesMod = @import("types.zig");

const PreviewMode = TypesMod.PreviewMode;
const TransformParams = TypesMod.TransformParams;

pub const PreviewContext = struct {
    mode: PreviewMode,
    radius: f64 = 0.0,
    angle: f64 = 0.0,
    pixel_size: f64 = 10.0,
    transform: TransformParams = .{},
    unsharp_scale: f64 = 0.0,
    noise_iterations: c_int = 0,
    oilify_mask_radius: f64 = 3.5,
    drop_shadow_x: f64 = 10.0,
    drop_shadow_y: f64 = 10.0,
    drop_shadow_radius: f64 = 10.0,
    drop_shadow_opacity: f64 = 0.5,
    red_eye_threshold: f64 = 0.4,
    waves_amplitude: f64 = 30.0,
    waves_phase: f64 = 0.0,
    waves_wavelength: f64 = 20.0,
    waves_center_x: f64 = 0.5,
    waves_center_y: f64 = 0.5,
    supernova_x: f64 = 400.0,
    supernova_y: f64 = 300.0,
    supernova_radius: f64 = 20.0,
    supernova_spokes: c_int = 100,
    supernova_color: [4]u8 = .{ 100, 100, 255, 255 },
    lighting_x: f64 = 0.0,
    lighting_y: f64 = 0.0,
    lighting_z: f64 = 100.0,
    lighting_intensity: f64 = 1.0,
    lighting_color: [4]u8 = .{ 255, 255, 255, 255 },

    split_view_enabled: bool = false,
    split_x: f64 = 400.0,
    canvas_width: c_int = 800,
    canvas_height: c_int = 600,

    floating_buffer: ?*c.GeglBuffer = null,
    floating_x: f64 = 0.0,
    floating_y: f64 = 0.0,

    source_layer_buffer: *c.GeglBuffer,
};

pub const PreviewResult = struct {
    output: *c.GeglNode,
    bbox: ?c.GeglRectangle = null,
};

fn applySplitView(
    allocator: std.mem.Allocator,
    graph: *c.GeglNode,
    original: *c.GeglNode,
    filtered: *c.GeglNode,
    ctx: PreviewContext,
    nodes: *std.ArrayList(*c.GeglNode)
) !*c.GeglNode {
    const w: f64 = @floatFromInt(ctx.canvas_width);
    const h: f64 = @floatFromInt(ctx.canvas_height);
    const sx = ctx.split_x;

    const left_crop = c.gegl_node_new_child(graph, "operation", "gegl:crop", "x", @as(f64, 0.0), "y", @as(f64, 0.0), "width", sx, "height", h, @as(?*anyopaque, null));
    if (left_crop == null) return error.GeglNodeFailed;
    _ = c.gegl_node_connect(left_crop, "input", original, "output");
    try nodes.append(allocator, left_crop.?);

    const right_crop = c.gegl_node_new_child(graph, "operation", "gegl:crop", "x", sx, "y", @as(f64, 0.0), "width", w - sx, "height", h, @as(?*anyopaque, null));
    if (right_crop == null) return error.GeglNodeFailed;
    _ = c.gegl_node_connect(right_crop, "input", filtered, "output");
    try nodes.append(allocator, right_crop.?);

    const split_over = c.gegl_node_new_child(graph, "operation", "gegl:over", @as(?*anyopaque, null));
    if (split_over == null) return error.GeglNodeFailed;
    _ = c.gegl_node_connect(split_over, "input", left_crop, "output");
    _ = c.gegl_node_connect(split_over, "aux", right_crop, "output");
    try nodes.append(allocator, split_over.?);

    return split_over.?;
}

pub fn addPreviewOps(
    allocator: std.mem.Allocator,
    graph: *c.GeglNode,
    input: *c.GeglNode,
    ctx: PreviewContext,
    nodes: *std.ArrayList(*c.GeglNode)
) !PreviewResult {
    var result = PreviewResult{ .output = input };

    if (ctx.mode == .blur) {
        if (c.gegl_node_new_child(graph, "operation", "gegl:gaussian-blur", "std-dev-x", ctx.radius, "std-dev-y", ctx.radius, @as(?*anyopaque, null))) |node| {
            _ = c.gegl_node_connect(node, "input", input, "output");
            try nodes.append(allocator, node);
            if (ctx.split_view_enabled) {
                result.output = try applySplitView(allocator, graph, input, node, ctx, nodes);
            } else {
                result.output = node;
            }
        }
    } else if (ctx.mode == .motion_blur) {
        if (c.gegl_node_new_child(graph, "operation", "gegl:motion-blur-linear", "length", ctx.radius, "angle", ctx.angle, @as(?*anyopaque, null))) |node| {
            _ = c.gegl_node_connect(node, "input", input, "output");
            try nodes.append(allocator, node);
            if (ctx.split_view_enabled) {
                result.output = try applySplitView(allocator, graph, input, node, ctx, nodes);
            } else {
                result.output = node;
            }
        }
    } else if (ctx.mode == .pixelize) {
        if (c.gegl_node_new_child(graph, "operation", "gegl:pixelize", "size-x", ctx.pixel_size, "size-y", ctx.pixel_size, @as(?*anyopaque, null))) |node| {
            _ = c.gegl_node_connect(node, "input", input, "output");
            try nodes.append(allocator, node);
            if (ctx.split_view_enabled) {
                result.output = try applySplitView(allocator, graph, input, node, ctx, nodes);
            } else {
                result.output = node;
            }
        }
    } else if (ctx.mode == .unsharp_mask) {
        if (c.gegl_node_new_child(graph, "operation", "gegl:unsharp-mask", "std-dev", ctx.radius, "scale", ctx.unsharp_scale, @as(?*anyopaque, null))) |node| {
            _ = c.gegl_node_connect(node, "input", input, "output");
            try nodes.append(allocator, node);
            if (ctx.split_view_enabled) {
                result.output = try applySplitView(allocator, graph, input, node, ctx, nodes);
            } else {
                result.output = node;
            }
        }
    } else if (ctx.mode == .noise_reduction) {
        if (c.gegl_node_new_child(graph, "operation", "gegl:noise-reduction", "iterations", ctx.noise_iterations, @as(?*anyopaque, null))) |node| {
            _ = c.gegl_node_connect(node, "input", input, "output");
            try nodes.append(allocator, node);
            if (ctx.split_view_enabled) {
                result.output = try applySplitView(allocator, graph, input, node, ctx, nodes);
            } else {
                result.output = node;
            }
        }
    } else if (ctx.mode == .oilify) {
        if (c.gegl_node_new_child(graph, "operation", "gegl:oilify", "mask-radius", ctx.oilify_mask_radius, @as(?*anyopaque, null))) |node| {
            _ = c.gegl_node_connect(node, "input", input, "output");
            try nodes.append(allocator, node);
            if (ctx.split_view_enabled) {
                result.output = try applySplitView(allocator, graph, input, node, ctx, nodes);
            } else {
                result.output = node;
            }
        }
    } else if (ctx.mode == .drop_shadow) {
        if (c.gegl_node_new_child(graph, "operation", "gegl:dropshadow", "x", ctx.drop_shadow_x, "y", ctx.drop_shadow_y, "radius", ctx.drop_shadow_radius, "opacity", ctx.drop_shadow_opacity, @as(?*anyopaque, null))) |node| {
            _ = c.gegl_node_connect(node, "input", input, "output");
            try nodes.append(allocator, node);
            if (ctx.split_view_enabled) {
                result.output = try applySplitView(allocator, graph, input, node, ctx, nodes);
            } else {
                result.output = node;
            }
        }
    } else if (ctx.mode == .red_eye_removal) {
        if (c.gegl_node_new_child(graph, "operation", "gegl:red-eye-removal", "threshold", ctx.red_eye_threshold, @as(?*anyopaque, null))) |node| {
            _ = c.gegl_node_connect(node, "input", input, "output");
            try nodes.append(allocator, node);
            if (ctx.split_view_enabled) {
                result.output = try applySplitView(allocator, graph, input, node, ctx, nodes);
            } else {
                result.output = node;
            }
        }
    } else if (ctx.mode == .waves) {
        if (c.gegl_node_new_child(graph, "operation", "gegl:waves", "amplitude", ctx.waves_amplitude, "phase", ctx.waves_phase, "wavelength", ctx.waves_wavelength, "center-x", ctx.waves_center_x, "center-y", ctx.waves_center_y, @as(?*anyopaque, null))) |node| {
            _ = c.gegl_node_connect(node, "input", input, "output");
            try nodes.append(allocator, node);
            if (ctx.split_view_enabled) {
                result.output = try applySplitView(allocator, graph, input, node, ctx, nodes);
            } else {
                result.output = node;
            }
        }
    } else if (ctx.mode == .supernova) {
        var buf: [64]u8 = undefined;
        const color_str = std.fmt.bufPrintZ(&buf, "rgba({d}, {d}, {d}, {d})", .{
            ctx.supernova_color[0],
            ctx.supernova_color[1],
            ctx.supernova_color[2],
            @as(f32, @floatFromInt(ctx.supernova_color[3])) / 255.0,
        }) catch "rgba(0,0,1,1)";
        const color = c.gegl_color_new(color_str.ptr);
        defer c.g_object_unref(color);

        if (c.gegl_node_new_child(graph, "operation", "gegl:supernova", "center-x", ctx.supernova_x, "center-y", ctx.supernova_y, "radius", ctx.supernova_radius, "spokes", ctx.supernova_spokes, "color", color, @as(?*anyopaque, null))) |node| {
            _ = c.gegl_node_connect(node, "input", input, "output");
            try nodes.append(allocator, node);
            if (ctx.split_view_enabled) {
                result.output = try applySplitView(allocator, graph, input, node, ctx, nodes);
            } else {
                result.output = node;
            }
        }
    } else if (ctx.mode == .lighting) {
        var buf: [64]u8 = undefined;
        const color_str = std.fmt.bufPrintZ(&buf, "rgba({d}, {d}, {d}, {d})", .{
            ctx.lighting_color[0],
            ctx.lighting_color[1],
            ctx.lighting_color[2],
            @as(f32, @floatFromInt(ctx.lighting_color[3])) / 255.0,
        }) catch "rgba(1,1,1,1)";
        const color = c.gegl_color_new(color_str.ptr);
        defer c.g_object_unref(color);

        if (c.gegl_node_new_child(graph, "operation", "gegl:lighting", "x", ctx.lighting_x, "y", ctx.lighting_y, "z", ctx.lighting_z, "intensity", ctx.lighting_intensity, "color", color, "type", @as(c_int, 0), @as(?*anyopaque, null))) |node| {
            _ = c.gegl_node_connect(node, "input", input, "output");
            try nodes.append(allocator, node);
            if (ctx.split_view_enabled) {
                result.output = try applySplitView(allocator, graph, input, node, ctx, nodes);
            } else {
                result.output = node;
            }
        }
    } else if (ctx.mode == .transform) {
        const extent = c.gegl_buffer_get_extent(ctx.source_layer_buffer);
        const cx = @as(f64, @floatFromInt(extent.*.x)) + @as(f64, @floatFromInt(extent.*.width)) / 2.0;
        const cy = @as(f64, @floatFromInt(extent.*.y)) + @as(f64, @floatFromInt(extent.*.height)) / 2.0;
        const tp = ctx.transform;
        const t1 = c.gegl_node_new_child(graph, "operation", "gegl:translate", "x", -cx, "y", -cy, @as(?*anyopaque, null));
        const scale = c.gegl_node_new_child(graph, "operation", "gegl:scale-ratio", "x", tp.scale_x, "y", tp.scale_y, @as(?*anyopaque, null));
        const rotate = c.gegl_node_new_child(graph, "operation", "gegl:rotate", "degrees", tp.rotate, @as(?*anyopaque, null));
        const t2 = c.gegl_node_new_child(graph, "operation", "gegl:translate", "x", cx + tp.x, "y", cy + tp.y, @as(?*anyopaque, null));

        var skew: ?*c.GeglNode = null;
        const has_skew = (@abs(tp.skew_x) > 0.001 or @abs(tp.skew_y) > 0.001);
        var buf: [128]u8 = undefined;
        if (has_skew) {
            const rad_x = std.math.degreesToRadians(tp.skew_x);
            const rad_y = std.math.degreesToRadians(tp.skew_y);
            const tan_x = std.math.tan(rad_x);
            const tan_y = std.math.tan(rad_y);
            const transform_str = std.fmt.bufPrintZ(&buf, "matrix(1.0 {d:.6} {d:.6} 1.0 0.0 0.0)", .{ tan_y, tan_x }) catch "matrix(1.0 0.0 0.0 1.0 0.0 0.0)";
            skew = c.gegl_node_new_child(graph, "operation", "gegl:transform", "transform", transform_str.ptr, @as(?*anyopaque, null));
        }

        if (t1 != null and scale != null and rotate != null and t2 != null) {
            _ = c.gegl_node_connect(t1, "input", input, "output");
            _ = c.gegl_node_connect(scale, "input", t1, "output");
            if (has_skew and skew != null) {
                _ = c.gegl_node_connect(skew, "input", scale, "output");
                _ = c.gegl_node_connect(rotate, "input", skew, "output");
                try nodes.append(allocator, skew.?);
            } else {
                _ = c.gegl_node_connect(rotate, "input", scale, "output");
            }
            _ = c.gegl_node_connect(t2, "input", rotate, "output");

            try nodes.append(allocator, t1.?);
            try nodes.append(allocator, scale.?);
            try nodes.append(allocator, rotate.?);
            try nodes.append(allocator, t2.?);

            result.output = t2.?;
            result.bbox = c.gegl_node_get_bounding_box(t2);
        }
    } else if (ctx.mode == .move_selection) {
        if (ctx.floating_buffer) |fb| {
            const float_src = c.gegl_node_new_child(graph, "operation", "gegl:buffer-source", "buffer", fb, @as(?*anyopaque, null));
            const translate = c.gegl_node_new_child(graph, "operation", "gegl:translate", "x", ctx.floating_x, "y", ctx.floating_y, @as(?*anyopaque, null));
            _ = c.gegl_node_link_many(float_src, translate, @as(?*anyopaque, null));

            const over = c.gegl_node_new_child(graph, "operation", "gegl:over", @as(?*anyopaque, null));
            _ = c.gegl_node_connect(over, "input", input, "output");
            _ = c.gegl_node_connect(over, "aux", translate, "output");

            try nodes.append(allocator, float_src.?);
            try nodes.append(allocator, translate.?);
            try nodes.append(allocator, over.?);

            result.output = over.?;
            result.bbox = c.gegl_node_get_bounding_box(translate);
        }
    }

    return result;
}
