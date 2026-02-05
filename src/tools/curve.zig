const std = @import("std");
const ToolInterface = @import("interface.zig").ToolInterface;
const Engine = @import("../engine.zig").Engine;
const c = @import("../c.zig").c;

const Point = struct { x: f64, y: f64 };

pub const CurveTool = struct {
    allocator: std.mem.Allocator,
    phase: i32,
    p1: Point,
    p2: Point,
    p3: Point,
    p4: Point,
    active_button: u32,

    pub fn create(allocator: std.mem.Allocator) !*CurveTool {
        const self = try allocator.create(CurveTool);
        self.* = .{
            .allocator = allocator,
            .phase = 0,
            .p1 = .{ .x = 0, .y = 0 },
            .p2 = .{ .x = 0, .y = 0 },
            .p3 = .{ .x = 0, .y = 0 },
            .p4 = .{ .x = 0, .y = 0 },
            .active_button = 0,
        };
        return self;
    }

    pub fn interface(self: *CurveTool) ToolInterface {
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
        const self: *CurveTool = @ptrCast(@alignCast(ptr));
        engine.setMode(.paint);
        engine.setBrushType(.circle);
        self.phase = 0;
    }

    fn deactivate(ptr: *anyopaque, engine: *Engine) void {
        _ = ptr;
        _ = engine;
    }

    fn start(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, button: u32, modifiers: u32) void {
        const self: *CurveTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;
        // Curve tool uses subsequent drags for phases.
        // Phase 0: Start of Line.
        // Phase 1: Start of Bend 1.
        // Phase 2: Start of Bend 2.

        self.active_button = button; // Store button for color choice at commit time

        if (self.phase == 0) {
            self.p1.x = x;
            self.p1.y = y;
        }
        _ = engine;
    }

    fn update(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        const self: *CurveTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;

        if (self.phase == 0) {
            // Dragging line endpoint
            self.p4.x = x;
            self.p4.y = y;
            // CP1, CP2 follow line for now
            self.p2 = self.p1;
            self.p3 = self.p4;
        } else if (self.phase == 1) {
            // Dragging CP1
            self.p2.x = x;
            self.p2.y = y;
        } else if (self.phase == 2) {
            // Dragging CP2
            self.p3.x = x;
            self.p3.y = y;
        }

        const sx: c_int = @intFromFloat(self.p1.x);
        const sy: c_int = @intFromFloat(self.p1.y);
        const ex: c_int = @intFromFloat(self.p4.x);
        const ey: c_int = @intFromFloat(self.p4.y);
        const cx1: c_int = @intFromFloat(self.p2.x);
        const cy1: c_int = @intFromFloat(self.p2.y);
        const cx2: c_int = @intFromFloat(self.p3.x);
        const cy2: c_int = @intFromFloat(self.p3.y);

        engine.setShapePreview(sx, sy, 0, 0, 1, false);
        if (engine.preview_shape) |*s| {
            s.type = .curve;
            s.x2 = ex;
            s.y2 = ey;
            s.cx1 = cx1;
            s.cy1 = cy1;
            s.cx2 = cx2;
            s.cy2 = cy2;
        }
    }

    fn end(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        const self: *CurveTool = @ptrCast(@alignCast(ptr));
        _ = x;
        _ = y;
        _ = modifiers;

        if (self.phase == 0) {
            self.phase = 1;
        } else if (self.phase == 1) {
            self.phase = 2;
        } else if (self.phase == 2) {
            // Commit
            const sx: c_int = @intFromFloat(self.p1.x);
            const sy: c_int = @intFromFloat(self.p1.y);
            const ex: c_int = @intFromFloat(self.p4.x);
            const ey: c_int = @intFromFloat(self.p4.y);
            const cx1: c_int = @intFromFloat(self.p2.x);
            const cy1: c_int = @intFromFloat(self.p2.y);
            const cx2: c_int = @intFromFloat(self.p3.x);
            const cy2: c_int = @intFromFloat(self.p3.y);

            engine.beginTransaction();
            const original_fg = engine.fg_color;
            if (self.active_button == 3) {
                engine.setFgColor(engine.bg_color[0], engine.bg_color[1], engine.bg_color[2], engine.bg_color[3]);
            }

            engine.drawCurve(sx, sy, ex, ey, cx1, cy1, cx2, cy2) catch {};

            if (self.active_button == 3) {
                engine.setFgColor(original_fg[0], original_fg[1], original_fg[2], original_fg[3]);
            }
            engine.commitTransaction();
            engine.clearShapePreview();
            self.phase = 0;
        }
    }

    fn drawOverlay(ptr: *anyopaque, cr: *c.cairo_t, scale: f64, view_x: f64, view_y: f64) void {
        _ = ptr;
        _ = cr;
        _ = scale;
        _ = view_x;
        _ = view_y;
    }

    fn destroy(ptr: *anyopaque, allocator: std.mem.Allocator) void {
        const self: *CurveTool = @ptrCast(@alignCast(ptr));
        allocator.destroy(self);
    }
};
