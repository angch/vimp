const std = @import("std");
const c = @import("../c.zig").c;

pub const Layer = struct {
    buffer: *c.GeglBuffer,
    source_node: *c.GeglNode,
    visible: bool = true,
    locked: bool = false,
    name: [64]u8 = undefined,
};

pub const LayerSnapshot = struct {
    buffer: *c.GeglBuffer, // Strong reference
    name: [64]u8,
    visible: bool,
    locked: bool,

    pub fn deinit(self: *LayerSnapshot) void {
        c.g_object_unref(self.buffer);
    }
};

pub const LayerCommand = union(enum) {
    add: struct {
        index: usize,
        snapshot: ?LayerSnapshot = null,
    },
    remove: struct {
        index: usize,
        snapshot: ?LayerSnapshot = null,
    },
    reorder: struct {
        from: usize,
        to: usize,
    },
    visibility: struct {
        index: usize,
    },
    lock: struct {
        index: usize,
    },

    pub fn deinit(self: *LayerCommand) void {
        switch (self.*) {
            .add => |*cmd| {
                if (cmd.snapshot) |*s| s.deinit();
            },
            .remove => |*cmd| {
                if (cmd.snapshot) |*s| s.deinit();
            },
            else => {},
        }
    }
};

pub const LayerMetadata = struct {
    name: []const u8,
    visible: bool,
    locked: bool,
    filename: []const u8,
};

pub const Layers = struct {
    list: std.ArrayList(Layer),
    active_index: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Layers {
        return .{
            .list = std.ArrayList(Layer){},
            .allocator = allocator,
            .active_index = 0,
        };
    }

    pub fn deinit(self: *Layers) void {
        for (self.list.items) |layer| {
            c.g_object_unref(layer.buffer);
        }
        self.list.deinit(self.allocator);
    }

    pub fn add(self: *Layers, graph: ?*c.GeglNode, buffer: *c.GeglBuffer, name: []const u8, visible: bool, locked: bool, index: usize) !void {
        const source_node = c.gegl_node_new_child(graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null));
        if (source_node == null) return error.GeglNodeFailed;

        var layer = Layer{
            .buffer = buffer,
            .source_node = source_node.?,
            .visible = visible,
            .locked = locked,
        };
        const len = @min(name.len, layer.name.len - 1);
        @memcpy(layer.name[0..len], name[0..len]);
        layer.name[len] = 0;

        try self.list.insert(self.allocator, index, layer);
        self.active_index = index;
    }

    pub fn remove(self: *Layers, graph: ?*c.GeglNode, index: usize) LayerSnapshot {
        const layer = self.list.orderedRemove(index);
        _ = c.gegl_node_remove_child(graph, layer.source_node);

        if (self.active_index >= self.list.items.len) {
            if (self.list.items.len > 0) {
                self.active_index = self.list.items.len - 1;
            } else {
                self.active_index = 0;
            }
        }

        return LayerSnapshot{
            .buffer = layer.buffer,
            .name = layer.name,
            .visible = layer.visible,
            .locked = layer.locked,
        };
    }

    pub fn reorder(self: *Layers, from: usize, to: usize) !void {
        if (from >= self.list.items.len or to >= self.list.items.len) return;
        if (from == to) return;

        const layer = self.list.orderedRemove(from);
        try self.list.insert(self.allocator, to, layer);

        if (self.active_index == from) {
            self.active_index = to;
        } else if (from < self.active_index and to >= self.active_index) {
            self.active_index -= 1;
        } else if (from > self.active_index and to <= self.active_index) {
            self.active_index += 1;
        }
    }

    pub fn setActive(self: *Layers, index: usize) void {
        if (index < self.list.items.len) {
            self.active_index = index;
        }
    }

    pub fn toggleVisibility(self: *Layers, index: usize) void {
        if (index < self.list.items.len) {
            self.list.items[index].visible = !self.list.items[index].visible;
        }
    }

    pub fn toggleLock(self: *Layers, index: usize) void {
        if (index < self.list.items.len) {
            self.list.items[index].locked = !self.list.items[index].locked;
        }
    }

    pub fn getActive(self: *Layers) ?*Layer {
        if (self.active_index < self.list.items.len) {
            return &self.list.items[self.active_index];
        }
        return null;
    }

    pub fn get(self: *Layers, index: usize) ?*Layer {
        if (index < self.list.items.len) {
            return &self.list.items[index];
        }
        return null;
    }

    pub fn count(self: *Layers) usize {
        return self.list.items.len;
    }
};

test "Layers management" {
    c.gegl_init(null, null);

    var layers = Layers.init(std.testing.allocator);
    defer layers.deinit();

    const extent = c.GeglRectangle{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const format = c.babl_format("R'G'B'A u8");

    // Create buffers
    const buffer1 = c.gegl_buffer_new(&extent, format).?;
    const buffer2 = c.gegl_buffer_new(&extent, format).?;

    const graph = c.gegl_node_new();
    defer c.g_object_unref(graph);

    // Add Layer 1
    try layers.add(graph, buffer1, "Layer 1", true, false, 0);
    try std.testing.expectEqual(layers.count(), 1);
    try std.testing.expectEqual(layers.active_index, 0);

    // Add Layer 2
    try layers.add(graph, buffer2, "Layer 2", true, false, 1);
    try std.testing.expectEqual(layers.count(), 2);
    try std.testing.expectEqual(layers.active_index, 1);

    // Verify order
    {
        const l0 = layers.get(0).?;
        const l1 = layers.get(1).?;
        try std.testing.expectEqualStrings("Layer 1", std.mem.span(@as([*:0]const u8, @ptrCast(&l0.name))));
        try std.testing.expectEqualStrings("Layer 2", std.mem.span(@as([*:0]const u8, @ptrCast(&l1.name))));
    }

    // Reorder: Move Layer 1 (index 0) to index 1
    try layers.reorder(0, 1);
    // Expected: [Layer 2, Layer 1]

    {
        const l0 = layers.get(0).?;
        const l1 = layers.get(1).?;
        try std.testing.expectEqualStrings("Layer 2", std.mem.span(@as([*:0]const u8, @ptrCast(&l0.name))));
        try std.testing.expectEqualStrings("Layer 1", std.mem.span(@as([*:0]const u8, @ptrCast(&l1.name))));
    }

    // Active layer was Layer 2 (index 1 before). Now Layer 2 is index 0.
    // active_index should be 0.
    try std.testing.expectEqual(layers.active_index, 0);

    // Remove Layer 2 (index 0)
    var snapshot = layers.remove(graph, 0);
    snapshot.deinit();

    try std.testing.expectEqual(layers.count(), 1);
    try std.testing.expectEqual(layers.active_index, 0); // Should point to Layer 1 (now at 0)

    {
        const l0 = layers.get(0).?;
        try std.testing.expectEqualStrings("Layer 1", std.mem.span(@as([*:0]const u8, @ptrCast(&l0.name))));
    }
}
