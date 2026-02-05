const std = @import("std");
const ToolInterface = @import("interface.zig").ToolInterface;
const Engine = @import("../engine.zig").Engine;
const c = @import("../c.zig").c;

pub const RoundedRectShapeTool = struct {
    allocator: std.mem.Allocator,
    start_x: f64,
    start_y: f64,

    pub fn create(allocator: std.mem.Allocator) !*RoundedRectShapeTool {
        const self = try allocator.create(RoundedRectShapeTool);
        self.* = .{
            .allocator = allocator,
            .start_x = 0,
            .start_y = 0,
        };
        return self;
    }

    pub fn interface(self: *RoundedRectShapeTool) ToolInterface {
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
        const self: *RoundedRectShapeTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;
        if (button != 1) return;
        self.start_x = x;
        self.start_y = y;
        _ = engine;
    }

    fn update(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        const self: *RoundedRectShapeTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;
        const min_x = @min(self.start_x, x);
        const min_y = @min(self.start_y, y);
        const w = @abs(x - self.start_x);
        const h = @abs(y - self.start_y);

        engine.setShapePreview(
            @intFromFloat(min_x),
            @intFromFloat(min_y),
            @intFromFloat(w),
            @intFromFloat(h),
            engine.brush_size,
            engine.brush_filled
        );
        if (engine.preview_shape) |*s| {
            s.type = .rounded_rectangle;
            s.radius = 20;
        }
    }

    fn end(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        const self: *RoundedRectShapeTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;
        const min_x = @min(self.start_x, x);
        const min_y = @min(self.start_y, y);
        const w = @abs(x - self.start_x);
        const h = @abs(y - self.start_y);

        engine.beginTransaction();
        engine.drawRoundedRectangle(
            @intFromFloat(min_x),
            @intFromFloat(min_y),
            @intFromFloat(w),
            @intFromFloat(h),
            20,
            engine.brush_size,
            engine.brush_filled
        ) catch {};
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
        const self: *RoundedRectShapeTool = @ptrCast(@alignCast(ptr));
        allocator.destroy(self);
    }
};
