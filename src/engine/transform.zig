const std = @import("std");
const c = @import("../c.zig").c;
const TypesMod = @import("types.zig");

const TransformParams = TypesMod.TransformParams;

fn calculateTransformBBox(layer_bbox: *const c.GeglRectangle, params: TransformParams) c.GeglRectangle {
    const cx = @as(f64, @floatFromInt(layer_bbox.x)) + @as(f64, @floatFromInt(layer_bbox.width)) / 2.0;
    const cy = @as(f64, @floatFromInt(layer_bbox.y)) + @as(f64, @floatFromInt(layer_bbox.height)) / 2.0;

    const rad_x = std.math.degreesToRadians(params.skew_x);
    const rad_y = std.math.degreesToRadians(params.skew_y);
    const tan_x = std.math.tan(rad_x);
    const tan_y = std.math.tan(rad_y);

    const rad_rot = std.math.degreesToRadians(params.rotate);
    const cos_r = std.math.cos(rad_rot);
    const sin_r = std.math.sin(rad_rot);

    var min_x: f64 = std.math.inf(f64);
    var min_y: f64 = std.math.inf(f64);
    var max_x: f64 = -std.math.inf(f64);
    var max_y: f64 = -std.math.inf(f64);

    const corners = [4][2]f64{
        .{ @floatFromInt(layer_bbox.x), @floatFromInt(layer_bbox.y) },
        .{ @floatFromInt(layer_bbox.x + layer_bbox.width), @floatFromInt(layer_bbox.y) },
        .{ @floatFromInt(layer_bbox.x + layer_bbox.width), @floatFromInt(layer_bbox.y + layer_bbox.height) },
        .{ @floatFromInt(layer_bbox.x), @floatFromInt(layer_bbox.y + layer_bbox.height) },
    };

    for (corners) |p| {
        var x = p[0] - cx;
        var y = p[1] - cy;
        x *= params.scale_x;
        y *= params.scale_y;
        const x_skew = x + tan_x * y;
        const y_skew = tan_y * x + y;
        x = x_skew;
        y = y_skew;
        const x_rot = x * cos_r - y * sin_r;
        const y_rot = x * sin_r + y * cos_r;
        x = x_rot;
        y = y_rot;
        x += cx + params.x;
        y += cy + params.y;
        if (x < min_x) min_x = x;
        if (x > max_x) max_x = x;
        if (y < min_y) min_y = y;
        if (y > max_y) max_y = y;
    }

    return c.GeglRectangle{
        .x = @intFromFloat(std.math.floor(min_x)),
        .y = @intFromFloat(std.math.floor(min_y)),
        .width = @intFromFloat(std.math.ceil(max_x - min_x)),
        .height = @intFromFloat(std.math.ceil(max_y - min_y)),
    };
}

pub fn transformBuffer(buffer: *c.GeglBuffer, params: TransformParams) !*c.GeglBuffer {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const input_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null));

    const extent = c.gegl_buffer_get_extent(buffer);
    const cx = @as(f64, @floatFromInt(extent.*.x)) + @as(f64, @floatFromInt(extent.*.width)) / 2.0;
    const cy = @as(f64, @floatFromInt(extent.*.y)) + @as(f64, @floatFromInt(extent.*.height)) / 2.0;

    const t1 = c.gegl_node_new_child(temp_graph, "operation", "gegl:translate", "x", -cx, "y", -cy, @as(?*anyopaque, null));
    const scale = c.gegl_node_new_child(temp_graph, "operation", "gegl:scale-ratio", "x", params.scale_x, "y", params.scale_y, @as(?*anyopaque, null));
    const rotate = c.gegl_node_new_child(temp_graph, "operation", "gegl:rotate", "degrees", params.rotate, @as(?*anyopaque, null));
    const t2 = c.gegl_node_new_child(temp_graph, "operation", "gegl:translate", "x", cx + params.x, "y", cy + params.y, @as(?*anyopaque, null));

    var skew: ?*c.GeglNode = null;
    const has_skew = (@abs(params.skew_x) > 0.001 or @abs(params.skew_y) > 0.001);
    var buf: [128]u8 = undefined;

    if (has_skew) {
        const rad_x = std.math.degreesToRadians(params.skew_x);
        const rad_y = std.math.degreesToRadians(params.skew_y);
        const tan_x = std.math.tan(rad_x);
        const tan_y = std.math.tan(rad_y);
        const transform_str = std.fmt.bufPrintZ(&buf, "matrix(1.0 {d:.6} {d:.6} 1.0 0.0 0.0)", .{ tan_y, tan_x }) catch "matrix(1.0 0.0 0.0 1.0 0.0 0.0)";
        skew = c.gegl_node_new_child(temp_graph, "operation", "gegl:transform", "transform", transform_str.ptr, @as(?*anyopaque, null));
    }

    if (t1 == null or scale == null or rotate == null or t2 == null) return error.GeglNodeFailed;
    if (has_skew and skew == null) return error.GeglNodeFailed;

    _ = c.gegl_node_connect(t1, "input", input_node, "output");
    _ = c.gegl_node_connect(scale, "input", t1, "output");

    if (has_skew) {
        _ = c.gegl_node_connect(skew, "input", scale, "output");
        _ = c.gegl_node_connect(rotate, "input", skew, "output");
    } else {
        _ = c.gegl_node_connect(rotate, "input", scale, "output");
    }
    _ = c.gegl_node_connect(t2, "input", rotate, "output");

    var bbox = calculateTransformBBox(extent, params);

    // Safety limits
    if (bbox.width > 20000) bbox.width = 20000;
    if (bbox.height > 20000) bbox.height = 20000;
    if (bbox.width <= 0) bbox.width = 1;
    if (bbox.height <= 0) bbox.height = 1;

    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(&bbox, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const w: usize = @intCast(bbox.width);
    const h: usize = @intCast(bbox.height);
    const stride: c_int = bbox.width * 4;
    const size = w * h * 4;

    const mem = try std.heap.c_allocator.alloc(u8, size);
    defer std.heap.c_allocator.free(mem);

    c.gegl_node_blit(t2, 1.0, &bbox, format, mem.ptr, stride, c.GEGL_BLIT_DEFAULT);
    c.gegl_buffer_set(new_buffer, &bbox, 0, format, mem.ptr, stride);

    return new_buffer.?;
}

pub fn rotateBuffer(buffer: *c.GeglBuffer, degrees: f64) !*c.GeglBuffer {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const extent = c.gegl_buffer_get_extent(buffer);
    const cx = @as(f64, @floatFromInt(extent.*.x)) + @as(f64, @floatFromInt(extent.*.width)) / 2.0;
    const cy = @as(f64, @floatFromInt(extent.*.y)) + @as(f64, @floatFromInt(extent.*.height)) / 2.0;

    const input_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null));
    const t1 = c.gegl_node_new_child(temp_graph, "operation", "gegl:translate", "x", -cx, "y", -cy, @as(?*anyopaque, null));
    const rotate = c.gegl_node_new_child(temp_graph, "operation", "gegl:rotate", "degrees", degrees, "sampler", c.GEGL_SAMPLER_NEAREST, @as(?*anyopaque, null));
    const t2 = c.gegl_node_new_child(temp_graph, "operation", "gegl:translate", "x", cx, "y", cy, @as(?*anyopaque, null));

    _ = c.gegl_node_link_many(input_node, t1, rotate, t2, @as(?*anyopaque, null));

    const bbox = c.gegl_node_get_bounding_box(t2);
    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(&bbox, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));
    _ = c.gegl_node_link(t2, write_node);
    _ = c.gegl_node_process(write_node);

    return new_buffer.?;
}

pub fn flipBuffer(buffer: *c.GeglBuffer, horizontal: bool) !*c.GeglBuffer {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const extent = c.gegl_buffer_get_extent(buffer);
    const cx = @as(f64, @floatFromInt(extent.*.x)) + @as(f64, @floatFromInt(extent.*.width)) / 2.0;
    const cy = @as(f64, @floatFromInt(extent.*.y)) + @as(f64, @floatFromInt(extent.*.height)) / 2.0;

    const scale_x: f64 = if (horizontal) -1.0 else 1.0;
    const scale_y: f64 = if (horizontal) 1.0 else -1.0;

    const input_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null));
    const t1 = c.gegl_node_new_child(temp_graph, "operation", "gegl:translate", "x", -cx, "y", -cy, @as(?*anyopaque, null));
    const scale = c.gegl_node_new_child(temp_graph, "operation", "gegl:scale-ratio", "x", scale_x, "y", scale_y, "sampler", c.GEGL_SAMPLER_NEAREST, @as(?*anyopaque, null));
    const t2 = c.gegl_node_new_child(temp_graph, "operation", "gegl:translate", "x", cx, "y", cy, @as(?*anyopaque, null));

    _ = c.gegl_node_link_many(input_node, t1, scale, t2, @as(?*anyopaque, null));

    const bbox = c.gegl_node_get_bounding_box(t2);
    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(&bbox, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));
    _ = c.gegl_node_link(t2, write_node);
    _ = c.gegl_node_process(write_node);

    return new_buffer.?;
}
