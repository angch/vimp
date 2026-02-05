const std = @import("std");
const c = @import("../c.zig").c;
const LayersMod = @import("layers.zig");
const Types = @import("types.zig");

pub const PaintCommand = struct {
    layer_idx: usize,
    before: *c.GeglBuffer,
    after: ?*c.GeglBuffer = null,

    pub fn deinit(self: *PaintCommand) void {
        c.g_object_unref(self.before);
        if (self.after) |a| c.g_object_unref(a);
    }
};

pub const SelectionCommand = struct {
    before: ?c.GeglRectangle,
    before_mode: Types.SelectionMode,
    after: ?c.GeglRectangle = null,
    after_mode: Types.SelectionMode = .rectangle,
    before_points: ?[]Types.Point = null,
    after_points: ?[]Types.Point = null,

    pub fn deinit(self: *SelectionCommand) void {
        if (self.before_points) |p| std.heap.c_allocator.free(p);
        if (self.after_points) |p| std.heap.c_allocator.free(p);
    }
};

pub const CanvasSizeCommand = struct {
    before_width: c_int,
    before_height: c_int,
    after_width: c_int,
    after_height: c_int,
};

pub const Command = union(enum) {
    paint: PaintCommand,
    transform: PaintCommand,
    layer: LayersMod.LayerCommand,
    selection: SelectionCommand,
    canvas_size: CanvasSizeCommand,

    pub fn description(self: Command) [:0]const u8 {
        switch (self) {
            .paint => return "Paint Stroke",
            .transform => return "Transform Layer",
            .layer => |l_cmd| switch (l_cmd) {
                .add => return "Add Layer",
                .remove => return "Remove Layer",
                .reorder => return "Reorder Layer",
                .visibility => return "Toggle Visibility",
                .lock => return "Toggle Lock",
            },
            .selection => return "Selection Change",
            .canvas_size => return "Resize Canvas",
        }
    }

    pub fn deinit(self: *Command) void {
        switch (self.*) {
            .paint => |*cmd| cmd.deinit(),
            .transform => |*cmd| cmd.deinit(),
            .layer => |*cmd| cmd.deinit(),
            .selection => |*cmd| cmd.deinit(),
            .canvas_size => {},
        }
    }
};

pub const History = struct {
    allocator: std.mem.Allocator,
    undo_stack: std.ArrayListUnmanaged(Command),
    redo_stack: std.ArrayListUnmanaged(Command),

    pub fn init(allocator: std.mem.Allocator) History {
        return .{
            .allocator = allocator,
            .undo_stack = .{},
            .redo_stack = .{},
        };
    }

    pub fn deinit(self: *History) void {
        for (self.undo_stack.items) |*cmd| cmd.deinit();
        self.undo_stack.deinit(self.allocator);
        for (self.redo_stack.items) |*cmd| cmd.deinit();
        self.redo_stack.deinit(self.allocator);
    }

    pub fn push(self: *History, cmd: Command) !void {
        try self.undo_stack.append(self.allocator, cmd);
        self.clearRedo();
    }

    pub fn pushUndo(self: *History, cmd: Command) !void {
        try self.undo_stack.append(self.allocator, cmd);
    }

    pub fn pushRedo(self: *History, cmd: Command) !void {
        try self.redo_stack.append(self.allocator, cmd);
    }

    pub fn popUndo(self: *History) ?Command {
        if (self.undo_stack.items.len == 0) return null;
        return self.undo_stack.pop();
    }

    pub fn popRedo(self: *History) ?Command {
        if (self.redo_stack.items.len == 0) return null;
        return self.redo_stack.pop();
    }

    pub fn clearRedo(self: *History) void {
        for (self.redo_stack.items) |*cmd| cmd.deinit();
        self.redo_stack.clearRetainingCapacity();
    }
};
