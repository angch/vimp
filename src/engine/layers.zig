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
