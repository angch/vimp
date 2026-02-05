const std = @import("std");
const c = @import("../c.zig").c;

pub fn applyGaussianBlur(buffer: *c.GeglBuffer, radius: f64) !*c.GeglBuffer {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const input_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null));
    const blur_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:gaussian-blur", "std-dev-x", radius, "std-dev-y", radius, @as(?*anyopaque, null));

    const extent = c.gegl_buffer_get_extent(buffer);
    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(extent, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));

    if (input_node == null or blur_node == null or write_node == null) return error.GeglNodeFailed;

    _ = c.gegl_node_link_many(input_node, blur_node, write_node, @as(?*anyopaque, null));
    _ = c.gegl_node_process(write_node);

    return new_buffer.?;
}

pub fn applyMotionBlur(buffer: *c.GeglBuffer, length: f64, angle: f64) !*c.GeglBuffer {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const input_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null));
    const blur_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:motion-blur-linear", "length", length, "angle", angle, @as(?*anyopaque, null));

    const extent = c.gegl_buffer_get_extent(buffer);
    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(extent, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));

    if (input_node == null or blur_node == null or write_node == null) return error.GeglNodeFailed;

    _ = c.gegl_node_link_many(input_node, blur_node, write_node, @as(?*anyopaque, null));
    _ = c.gegl_node_process(write_node);

    return new_buffer.?;
}

pub fn applyPixelize(buffer: *c.GeglBuffer, size: f64) !*c.GeglBuffer {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const input_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null));
    const pixelize_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:pixelize", "size-x", size, "size-y", size, @as(?*anyopaque, null));

    const extent = c.gegl_buffer_get_extent(buffer);
    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(extent, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));

    if (input_node == null or pixelize_node == null or write_node == null) return error.GeglNodeFailed;

    _ = c.gegl_node_link_many(input_node, pixelize_node, write_node, @as(?*anyopaque, null));
    _ = c.gegl_node_process(write_node);

    return new_buffer.?;
}

pub fn applyUnsharpMask(buffer: *c.GeglBuffer, std_dev: f64, scale: f64) !*c.GeglBuffer {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const input_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null));
    const unsharp_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:unsharp-mask", "std-dev", std_dev, "scale", scale, @as(?*anyopaque, null));

    const extent = c.gegl_buffer_get_extent(buffer);
    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(extent, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));

    if (input_node == null or unsharp_node == null or write_node == null) return error.GeglNodeFailed;

    _ = c.gegl_node_link_many(input_node, unsharp_node, write_node, @as(?*anyopaque, null));
    _ = c.gegl_node_process(write_node);

    return new_buffer.?;
}

pub fn applyNoiseReduction(buffer: *c.GeglBuffer, iterations: c_int) !*c.GeglBuffer {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const input_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null));
    const noise_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:noise-reduction", "iterations", iterations, @as(?*anyopaque, null));

    const extent = c.gegl_buffer_get_extent(buffer);
    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(extent, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));

    if (input_node == null or noise_node == null or write_node == null) return error.GeglNodeFailed;

    _ = c.gegl_node_link_many(input_node, noise_node, write_node, @as(?*anyopaque, null));
    _ = c.gegl_node_process(write_node);

    return new_buffer.?;
}

pub fn applyOilify(buffer: *c.GeglBuffer, mask_radius: f64) !*c.GeglBuffer {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const input_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null));
    const oilify_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:oilify", "mask-radius", mask_radius, @as(?*anyopaque, null));

    const extent = c.gegl_buffer_get_extent(buffer);
    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(extent, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));

    if (input_node == null or oilify_node == null or write_node == null) return error.GeglNodeFailed;

    _ = c.gegl_node_link_many(input_node, oilify_node, write_node, @as(?*anyopaque, null));
    _ = c.gegl_node_process(write_node);

    return new_buffer.?;
}

pub fn applyDropShadow(buffer: *c.GeglBuffer, x: f64, y: f64, radius: f64, opacity: f64) !*c.GeglBuffer {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const input_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null));
    const ds_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:dropshadow", "x", x, "y", y, "radius", radius, "opacity", opacity, @as(?*anyopaque, null));

    if (input_node == null or ds_node == null) return error.GeglNodeFailed;

    _ = c.gegl_node_connect(ds_node, "input", input_node, "output");

    const bbox = c.gegl_node_get_bounding_box(ds_node);
    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(&bbox, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));
    if (write_node == null) return error.GeglNodeFailed;

    _ = c.gegl_node_connect(write_node, "input", ds_node, "output");
    _ = c.gegl_node_process(write_node);

    return new_buffer.?;
}

pub fn applyRedEyeRemoval(buffer: *c.GeglBuffer, threshold: f64) !*c.GeglBuffer {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const input_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null));
    const filter_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:red-eye-removal", "threshold", threshold, @as(?*anyopaque, null));

    const extent = c.gegl_buffer_get_extent(buffer);
    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(extent, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));

    if (input_node == null or filter_node == null or write_node == null) return error.GeglNodeFailed;

    _ = c.gegl_node_link_many(input_node, filter_node, write_node, @as(?*anyopaque, null));
    _ = c.gegl_node_process(write_node);

    return new_buffer.?;
}

pub fn applyWaves(buffer: *c.GeglBuffer, amplitude: f64, phase: f64, wavelength: f64, center_x: f64, center_y: f64) !*c.GeglBuffer {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const input_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null));
    const filter_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:waves", "amplitude", amplitude, "phase", phase, "wavelength", wavelength, "center-x", center_x, "center-y", center_y, @as(?*anyopaque, null));

    const extent = c.gegl_buffer_get_extent(buffer);
    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(extent, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));

    if (input_node == null or filter_node == null or write_node == null) return error.GeglNodeFailed;

    _ = c.gegl_node_link_many(input_node, filter_node, write_node, @as(?*anyopaque, null));
    _ = c.gegl_node_process(write_node);

    return new_buffer.?;
}

pub fn applySupernova(buffer: *c.GeglBuffer, x: f64, y: f64, radius: f64, spokes: c_int, color_rgba: [4]u8) !*c.GeglBuffer {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const color_str = try std.fmt.allocPrintSentinel(std.heap.c_allocator, "rgba({d}, {d}, {d}, {d})", .{
        color_rgba[0],
        color_rgba[1],
        color_rgba[2],
        @as(f32, @floatFromInt(color_rgba[3])) / 255.0,
    }, 0);
    defer std.heap.c_allocator.free(color_str);
    const color = c.gegl_color_new(color_str.ptr);
    defer c.g_object_unref(color);

    const input_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null));
    const filter_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:supernova", "center-x", x, "center-y", y, "radius", radius, "spokes", spokes, "color", color, @as(?*anyopaque, null));

    const extent = c.gegl_buffer_get_extent(buffer);
    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(extent, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));

    if (input_node == null or filter_node == null or write_node == null) return error.GeglNodeFailed;

    _ = c.gegl_node_link_many(input_node, filter_node, write_node, @as(?*anyopaque, null));
    _ = c.gegl_node_process(write_node);

    return new_buffer.?;
}

pub fn applyLighting(buffer: *c.GeglBuffer, x: f64, y: f64, z: f64, intensity: f64, color_rgba: [4]u8) !*c.GeglBuffer {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const color_str = try std.fmt.allocPrintSentinel(std.heap.c_allocator, "rgba({d}, {d}, {d}, {d})", .{
        color_rgba[0],
        color_rgba[1],
        color_rgba[2],
        @as(f32, @floatFromInt(color_rgba[3])) / 255.0,
    }, 0);
    defer std.heap.c_allocator.free(color_str);
    const color = c.gegl_color_new(color_str.ptr);
    defer c.g_object_unref(color);

    const input_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null));
    const filter_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:lighting", "x", x, "y", y, "z", z, "intensity", intensity, "color", color, "type", @as(c_int, 0), @as(?*anyopaque, null));

    const extent = c.gegl_buffer_get_extent(buffer);
    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(extent, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));

    if (input_node == null or filter_node == null or write_node == null) return error.GeglNodeFailed;

    _ = c.gegl_node_link_many(input_node, filter_node, write_node, @as(?*anyopaque, null));
    _ = c.gegl_node_process(write_node);

    return new_buffer.?;
}
