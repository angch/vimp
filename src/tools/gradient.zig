const std = @import("std");
const ToolInterface = @import("interface.zig").ToolInterface;
const Engine = @import("../engine.zig").Engine;
const c = @import("../c.zig").c;

pub const GradientTool = struct {
    allocator: std.mem.Allocator,
    start_x: f64,
    start_y: f64,

    pub fn create(allocator: std.mem.Allocator) !*GradientTool {
        const self = try allocator.create(GradientTool);
        self.* = .{
            .allocator = allocator,
            .start_x = 0,
            .start_y = 0,
        };
        return self;
    }

    pub fn interface(self: *GradientTool) ToolInterface {
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

    fn start(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, button: u32, modifiers: u32) void {
        const self: *GradientTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;
        if (button != 1) return;
        self.start_x = x;
        self.start_y = y;
        _ = engine;
    }

    fn update(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        const self: *GradientTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;
        const sx: c_int = @intFromFloat(self.start_x);
        const sy: c_int = @intFromFloat(self.start_y);
        const ex: c_int = @intFromFloat(x);
        const ey: c_int = @intFromFloat(y);

        engine.setShapePreview(sx, sy, 0, 0, 1, false);
        if (engine.preview_shape) |*s| {
            s.type = .line;
            s.x2 = ex;
            s.y2 = ey;
        }
    }

    fn end(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        const self: *GradientTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;
        const sx: c_int = @intFromFloat(self.start_x);
        const sy: c_int = @intFromFloat(self.start_y);
        const ex: c_int = @intFromFloat(x);
        const ey: c_int = @intFromFloat(y);

        engine.beginTransaction();
        engine.drawGradient(sx, sy, ex, ey) catch {};
        engine.commitTransaction();
        engine.clearShapePreview();
    }

    fn drawOverlay(ptr: *anyopaque, cr: *c.cairo_t, scale: f64, view_x: f64, view_y: f64) void {
        _ = ptr;
        _ = cr;
        _ = scale;
        _ = view_x;
        _ = view_y;
    }

    fn destroy(ptr: *anyopaque, allocator: std.mem.Allocator) void {
        const self: *GradientTool = @ptrCast(@alignCast(ptr));
        allocator.destroy(self);
    }
};
