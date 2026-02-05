const std = @import("std");
const ToolInterface = @import("interface.zig").ToolInterface;
const Engine = @import("../engine.zig").Engine;
const c = @import("../c.zig").c;

pub const ColorPickerTool = struct {
    allocator: std.mem.Allocator,
    on_pick: ?*const fn(color: [4]u8) void,

    pub fn create(allocator: std.mem.Allocator, on_pick: ?*const fn(color: [4]u8) void) !*ColorPickerTool {
        const self = try allocator.create(ColorPickerTool);
        self.* = .{
            .allocator = allocator,
            .on_pick = on_pick,
        };
        return self;
    }

    pub fn interface(self: *ColorPickerTool) ToolInterface {
        return ToolInterface{
            .ptr = self,
            .activateFn = activate,
            .deactivateFn = deactivate,
            .startFn = start,
            .updateFn = update,
            .endFn = end,
            .motionFn = null,
            .drawOverlayFn = drawOverlay,
            .destroyFn = destroy,
        };
    }

    fn activate(ptr: *anyopaque, engine: *Engine) void {
        _ = ptr;
        _ = engine;
    }

    fn deactivate(ptr: *anyopaque, engine: *Engine) void {
        _ = ptr;
        _ = engine;
    }

    fn pick(self: *ColorPickerTool, engine: *Engine, x: f64, y: f64) void {
        const cx: i32 = @intFromFloat(x);
        const cy: i32 = @intFromFloat(y);
        if (engine.pickColor(cx, cy)) |color| {
            engine.setFgColor(color[0], color[1], color[2], color[3]);
            if (self.on_pick) |cb| cb(color);
        } else |_| {}
    }

    fn start(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, button: u32, modifiers: u32) void {
        const self: *ColorPickerTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;
        if (button != 1) return;
        self.pick(engine, x, y);
    }

    fn update(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        const self: *ColorPickerTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;
        self.pick(engine, x, y);
    }

    fn end(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        _ = ptr;
        _ = engine;
        _ = x;
        _ = y;
        _ = modifiers;
    }

    fn drawOverlay(ptr: *anyopaque, cr: *c.cairo_t, scale: f64, view_x: f64, view_y: f64) void {
        _ = ptr;
        _ = cr;
        _ = scale;
        _ = view_x;
        _ = view_y;
    }

    fn destroy(ptr: *anyopaque, allocator: std.mem.Allocator) void {
        const self: *ColorPickerTool = @ptrCast(@alignCast(ptr));
        allocator.destroy(self);
    }
};
