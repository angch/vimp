const std = @import("std");
const c = @import("c.zig").c;

pub const Engine = struct {
    graph: ?*c.GeglNode = null,

    pub fn init(self: *Engine) void {
        _ = self;
        // Accept null args for generic initialization
        c.gegl_init(null, null);
    }

    pub fn deinit(self: *Engine) void {
        if (self.graph) |g| {
            c.g_object_unref(g);
        }
        c.gegl_exit();
    }

    pub fn setupGraph(self: *Engine) void {
        // Create the main graph container
        self.graph = c.gegl_node_new();

        const color = c.gegl_color_new("rgb(0.9, 0.9, 0.9)");

        // Safer to construct node then set properties if varargs is tricky,
        // but let's try the standard convenience function.
        // We cast the sentinel to ?*anyopaque (aka NULL)
        const bg_node = c.gegl_node_new_child(self.graph, "operation", "gegl:color", "value", color, @as(?*anyopaque, null));

        // A crop node to give it finite dimensions
        const crop_node = c.gegl_node_new_child(self.graph, "operation", "gegl:crop", "width", @as(f64, 800.0), "height", @as(f64, 600.0), @as(?*anyopaque, null));

        _ = c.gegl_node_link_many(bg_node, crop_node, @as(?*anyopaque, null));
    }
};
