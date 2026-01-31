const std = @import("std");
const c = @import("c.zig").c;
const Engine = @import("engine.zig").Engine;

test "gegl:transform availability" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();

    const graph = c.gegl_node_new();
    defer c.g_object_unref(graph);

    // Try to create a transform node
    const transform = c.gegl_node_new_child(graph, "operation", "gegl:transform", "transform", "translate(10, 10)", @as(?*anyopaque, null));

    // Check if it's not null
    try std.testing.expect(transform != null);

    // If it's null, the operation is missing.
    // Cleanup handled by graph unref if linked, but here it is child.
}
