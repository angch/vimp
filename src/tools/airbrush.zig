const std = @import("std");
const ToolInterface = @import("interface.zig").ToolInterface;
const Engine = @import("../engine.zig").Engine;
const c = @import("../c.zig").c;

pub const AirbrushTool = struct {
    allocator: std.mem.Allocator,
    last_x: f64,
    last_y: f64,
    active_button: u32,

    pub fn create(allocator: std.mem.Allocator) !*AirbrushTool {
        const self = try allocator.create(AirbrushTool);
        self.* = .{
            .allocator = allocator,
            .last_x = 0,
            .last_y = 0,
            .active_button = 0,
        };
        return self;
    }

    pub fn interface(self: *AirbrushTool) ToolInterface {
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
        engine.setMode(.airbrush);
        engine.setBrushType(.circle);
    }

    fn deactivate(ptr: *anyopaque, engine: *Engine) void {
        _ = ptr;
        _ = engine;
    }

    fn start(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, button: u32, modifiers: u32) void {
        const self: *AirbrushTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;
        self.last_x = x;
        self.last_y = y;
        self.active_button = button;

        engine.beginTransaction();

        if (button == 3) {
            engine.paintStrokeWithColor(x, y, x, y, 1.0, engine.bg_color);
        } else {
            engine.paintStroke(x, y, x, y, 1.0);
        }
    }

    fn update(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        const self: *AirbrushTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;

        if (self.active_button == 3) {
            engine.paintStrokeWithColor(self.last_x, self.last_y, x, y, 1.0, engine.bg_color);
        } else {
            engine.paintStroke(self.last_x, self.last_y, x, y, 1.0);
        }

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
        const self: *AirbrushTool = @ptrCast(@alignCast(ptr));
        allocator.destroy(self);
    }
};
