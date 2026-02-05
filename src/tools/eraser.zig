const std = @import("std");
const ToolInterface = @import("interface.zig").ToolInterface;
const Engine = @import("../engine.zig").Engine;
const c = @import("../c.zig").c;

pub const EraserTool = struct {
    allocator: std.mem.Allocator,
    last_x: f64,
    last_y: f64,

    pub fn create(allocator: std.mem.Allocator) !*EraserTool {
        const self = try allocator.create(EraserTool);
        self.* = .{
            .allocator = allocator,
            .last_x = 0,
            .last_y = 0,
        };
        return self;
    }

    pub fn interface(self: *EraserTool) ToolInterface {
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
        engine.setMode(.erase);
        engine.setBrushType(.square);
    }

    fn deactivate(ptr: *anyopaque, engine: *Engine) void {
        _ = ptr;
        _ = engine;
    }

    fn start(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, button: u32, modifiers: u32) void {
        const self: *EraserTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;
        _ = button;
        self.last_x = x;
        self.last_y = y;

        engine.beginTransaction();
        engine.paintStroke(x, y, x, y, 1.0);
    }

    fn update(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        const self: *EraserTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;
        engine.paintStroke(self.last_x, self.last_y, x, y, 1.0);
        self.last_x = x;
        self.last_y = y;
    }

    fn end(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        _ = ptr;
        _ = x;
        _ = y;
        _ = modifiers;
        engine.commitTransaction();
    }

    fn drawOverlay(ptr: *anyopaque, cr: *c.cairo_t, scale: f64, view_x: f64, view_y: f64) void {
        _ = ptr;
        _ = cr;
        _ = scale;
        _ = view_x;
        _ = view_y;
    }

    fn destroy(ptr: *anyopaque, allocator: std.mem.Allocator) void {
        const self: *EraserTool = @ptrCast(@alignCast(ptr));
        allocator.destroy(self);
    }
};
