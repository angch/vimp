const std = @import("std");
const c = @import("../c.zig").c;
const LayersMod = @import("layers.zig");
const PreviewMod = @import("preview.zig");

pub const CompositionResult = struct {
    output: *c.GeglNode,
    bbox: ?c.GeglRectangle = null,
};

pub fn rebuild(
    allocator: std.mem.Allocator,
    graph: *c.GeglNode,
    base_node: ?*c.GeglNode,
    layers: []const LayersMod.Layer,
    active_layer_idx: usize,
    preview_ctx: PreviewMod.PreviewContext,
    composition_nodes: *std.ArrayList(*c.GeglNode)
) !CompositionResult {
    // Clear old nodes from graph
    for (composition_nodes.items) |node| {
        _ = c.gegl_node_remove_child(graph, node);
    }
    composition_nodes.clearRetainingCapacity();

    if (base_node == null) return error.NoBaseNode;

    var current_input = base_node.?;
    var result = CompositionResult{ .output = current_input };

    for (layers, 0..) |layer, i| {
        if (!layer.visible) continue;

        var source_output = layer.source_node;

        if (i == active_layer_idx and preview_ctx.mode != .none) {
            // Apply preview ops
            var ctx = preview_ctx;
            ctx.source_layer_buffer = layer.buffer;

            if (PreviewMod.addPreviewOps(allocator, graph, source_output, ctx, composition_nodes)) |res| {
                source_output = res.output;
                result.bbox = res.bbox;
            } else |err| {
                std.debug.print("Failed to add preview ops: {}\n", .{err});
            }
        }

        if (c.gegl_node_new_child(graph, "operation", "gegl:over", @as(?*anyopaque, null))) |over_node| {
            _ = c.gegl_node_connect(over_node, "input", current_input, "output");
            _ = c.gegl_node_connect(over_node, "aux", source_output, "output");

            composition_nodes.append(allocator, over_node) catch {};
            current_input = over_node;
        }
    }

    result.output = current_input;
    return result;
}
