const std = @import("std");
const c = @import("src/c.zig").c;

test "Check gegl:split-preview availability" {
    c.gegl_init(null, null);
    defer c.gegl_exit();

    const node = c.gegl_node_new();
    defer c.g_object_unref(node);

    const split = c.gegl_node_new_child(node, "operation", "gegl:split-preview", @as(?*anyopaque, null));

    if (split == null) {
        std.debug.print("gegl:split-preview NOT found\n", .{});
        return error.NotFound;
    } else {
        std.debug.print("gegl:split-preview found\n", .{});
    }
}
