const std = @import("std");
const ToolInterface = @import("interface.zig").ToolInterface;
const Engine = @import("../engine.zig").Engine;
const c = @import("../c.zig").c;

pub const PolygonTool = struct {
    allocator: std.mem.Allocator,
    points: std.ArrayListUnmanaged(Engine.Point),
    active: bool,

    pub fn create(allocator: std.mem.Allocator) !*PolygonTool {
        const self = try allocator.create(PolygonTool);
        self.* = .{
            .allocator = allocator,
            .points = .{},
            .active = false,
        };
        return self;
    }

    pub fn interface(self: *PolygonTool) ToolInterface {
        return ToolInterface{
            .ptr = self,
            .activateFn = activate,
            .deactivateFn = deactivate,
            .startFn = start,
            .updateFn = update,
            .endFn = end,
            .motionFn = motion,
            .drawOverlayFn = drawOverlay,
            .destroyFn = destroy,
        };
    }

    fn activate(ptr: *anyopaque, engine: *Engine) void {
        const self: *PolygonTool = @ptrCast(@alignCast(ptr));
        engine.setMode(.paint);
        engine.setBrushType(.circle);
        self.active = false;
        self.points.clearRetainingCapacity();
    }

    fn deactivate(ptr: *anyopaque, engine: *Engine) void {
        const self: *PolygonTool = @ptrCast(@alignCast(ptr));
        self.points.deinit(self.allocator);
        _ = engine;
    }

    fn start(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, button: u32, modifiers: u32) void {
        const self: *PolygonTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;
        if (button != 1) return;

        if (!self.active) {
            self.points.clearRetainingCapacity();
            self.points.append(self.allocator, .{ .x = x, .y = y }) catch {};
            self.active = true;
        } else {
            // Check closure
            if (self.points.items.len > 0) {
                const first = self.points.items[0];
                const dx = x - first.x;
                const dy = y - first.y;
                // Threshold 5.0 (world units)
                if (dx * dx + dy * dy < 25.0) {
                    engine.beginTransaction();
                    engine.drawPolygon(self.points.items, engine.brush_size, false) catch {};
                    engine.commitTransaction();
                    engine.clearShapePreview();
                    self.active = false;
                    self.points.clearRetainingCapacity();
                    return;
                }
            }
            self.points.append(self.allocator, .{ .x = x, .y = y }) catch {};
        }
    }

    fn update(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        const self: *PolygonTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;

        if (self.active) {
             // We need to show preview from last confirmed point to current mouse pos.
             // We can use `setShapePreviewPolygon`.
             // We need to temporarily append current point.
             self.points.append(self.allocator, .{ .x = x, .y = y }) catch return;
             engine.setShapePreviewPolygon(self.points.items, engine.brush_size, false);
             _ = self.points.pop();
        }
    }

    fn end(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        _ = ptr;
        _ = engine;
        _ = x;
        _ = y;
        _ = modifiers;
    }

    fn motion(ptr: *anyopaque, engine: *Engine, x: f64, y: f64) void {
        const self: *PolygonTool = @ptrCast(@alignCast(ptr));
        if (self.active) {
             self.points.append(self.allocator, .{ .x = x, .y = y }) catch return;
             engine.setShapePreviewPolygon(self.points.items, engine.brush_size, false);
             _ = self.points.pop();
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
        const self: *PolygonTool = @ptrCast(@alignCast(ptr));
        self.points.deinit(allocator);
        allocator.destroy(self);
    }
};
