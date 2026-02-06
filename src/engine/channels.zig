const std = @import("std");
const c = @import("../c.zig").c;

pub const Channel = struct {
    buffer: *c.GeglBuffer,
    name: [64]u8 = undefined,
    visible: bool = true,
    color: [3]u8 = .{ 0, 0, 0 },
    opacity: f64 = 0.5,
};

pub const Channels = struct {
    list: std.ArrayList(Channel) = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Channels {
        return .{
            .list = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Channels) void {
        for (self.list.items) |channel| {
            c.g_object_unref(channel.buffer);
        }
        self.list.deinit(self.allocator);
    }

    pub fn add(self: *Channels, buffer: *c.GeglBuffer, name: []const u8, visible: bool, color: [3]u8, opacity: f64) !void {
        var channel = Channel{
            .buffer = buffer,
            .visible = visible,
            .color = color,
            .opacity = opacity,
        };
        const len = @min(name.len, channel.name.len - 1);
        @memcpy(channel.name[0..len], name[0..len]);
        channel.name[len] = 0;

        try self.list.append(self.allocator, channel);
    }

    pub fn count(self: *Channels) usize {
        return self.list.items.len;
    }
};
