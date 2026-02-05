const std = @import("std");
const ToolInterface = @import("interface.zig").ToolInterface;
const Engine = @import("../engine.zig").Engine;
const CanvasUtils = @import("../canvas_utils.zig");
const c = @import("../c.zig").c;

pub const LineTool = struct {
    allocator: std.mem.Allocator,
    start_x: f64,
    start_y: f64,
    active_button: u32,

    pub fn create(allocator: std.mem.Allocator) !*LineTool {
        const self = try allocator.create(LineTool);
        self.* = .{
            .allocator = allocator,
            .start_x = 0,
            .start_y = 0,
            .active_button = 0,
        };
        return self;
    }

    pub fn interface(self: *LineTool) ToolInterface {
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
        engine.setMode(.paint);
        engine.setBrushType(.circle);
    }

    fn deactivate(ptr: *anyopaque, engine: *Engine) void {
        _ = ptr;
        _ = engine;
    }

    fn start(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, button: u32, modifiers: u32) void {
        const self: *LineTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;
        self.start_x = x;
        self.start_y = y;
        self.active_button = button;
        _ = engine;
    }

    fn update(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        const self: *LineTool = @ptrCast(@alignCast(ptr));
        var end_x = x;
        var end_y = y;

        if ((modifiers & c.GDK_SHIFT_MASK) != 0) {
            const snapped = CanvasUtils.snapAngle(self.start_x, self.start_y, x, y, 45.0);
            end_x = snapped.x;
            end_y = snapped.y;
        }

        const sx: c_int = @intFromFloat(self.start_x);
        const sy: c_int = @intFromFloat(self.start_y);
        const ex: c_int = @intFromFloat(end_x);
        const ey: c_int = @intFromFloat(end_y);

        engine.setShapePreview(sx, sy, 0, 0, 1, false);
        if (engine.preview_shape) |*s| {
            s.type = .line;
            s.x2 = ex;
            s.y2 = ey;
        }
    }

    fn end(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        const self: *LineTool = @ptrCast(@alignCast(ptr));
        var end_x = x;
        var end_y = y;

        if ((modifiers & c.GDK_SHIFT_MASK) != 0) {
            const snapped = CanvasUtils.snapAngle(self.start_x, self.start_y, x, y, 45.0);
            end_x = snapped.x;
            end_y = snapped.y;
        }

        const sx: c_int = @intFromFloat(self.start_x);
        const sy: c_int = @intFromFloat(self.start_y);
        const ex: c_int = @intFromFloat(end_x);
        const ey: c_int = @intFromFloat(end_y);

        engine.beginTransaction();

        const original_fg = engine.fg_color;
        if (self.active_button == 3) {
            engine.setFgColor(engine.bg_color[0], engine.bg_color[1], engine.bg_color[2], engine.bg_color[3]);
        }

        engine.drawLine(sx, sy, ex, ey) catch {};

        if (self.active_button == 3) {
            engine.setFgColor(original_fg[0], original_fg[1], original_fg[2], original_fg[3]);
        }

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
        const self: *LineTool = @ptrCast(@alignCast(ptr));
        allocator.destroy(self);
    }
};
