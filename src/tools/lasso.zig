const std = @import("std");
const ToolInterface = @import("interface.zig").ToolInterface;
const Engine = @import("../engine.zig").Engine;
const c = @import("../c.zig").c;

pub const LassoTool = struct {
    allocator: std.mem.Allocator,
    points: std.ArrayListUnmanaged(Engine.Point),

    start_x: f64,
    start_y: f64,
    is_moving: bool,

    pub fn create(allocator: std.mem.Allocator) !*LassoTool {
        const self = try allocator.create(LassoTool);
        self.* = .{
            .allocator = allocator,
            .points = .{},
            .start_x = 0,
            .start_y = 0,
            .is_moving = false,
        };
        return self;
    }

    pub fn interface(self: *LassoTool) ToolInterface {
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
        engine.setSelectionMode(.lasso);
    }

    fn deactivate(ptr: *anyopaque, engine: *Engine) void {
        const self: *LassoTool = @ptrCast(@alignCast(ptr));
        self.points.deinit(self.allocator);
        _ = engine;
    }

    fn start(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, button: u32, modifiers: u32) void {
        const self: *LassoTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;
        if (button != 1) return;

        self.start_x = x;
        self.start_y = y;
        self.is_moving = false;

        const ix: i32 = @intFromFloat(x);
        const iy: i32 = @intFromFloat(y);

        if (engine.selection.rect != null and engine.isPointInSelection(ix, iy)) {
            engine.beginMoveSelection(x, y) catch return;
            self.is_moving = true;
        } else {
            engine.beginSelection();
            engine.clearSelection();
            self.points.clearRetainingCapacity();
            self.points.append(self.allocator, .{ .x = x, .y = y }) catch {};
        }
    }

    fn update(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        const self: *LassoTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;

        if (self.is_moving) {
            const dx = x - self.start_x;
            const dy = y - self.start_y;
            engine.updateMoveSelection(dx, dy);
        } else {
            self.points.append(self.allocator, .{ .x = x, .y = y }) catch {};
            engine.setShapePreviewPolygon(self.points.items, 1, false);
        }
    }

    fn end(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        const self: *LassoTool = @ptrCast(@alignCast(ptr));
        _ = x;
        _ = y;
        _ = modifiers;

        if (self.is_moving) {
            engine.commitMoveSelection() catch {};
            self.is_moving = false;
        } else {
            engine.setSelectionLasso(self.points.items);
            engine.commitTransaction();
            engine.clearShapePreview();
            self.points.clearRetainingCapacity();
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
        const self: *LassoTool = @ptrCast(@alignCast(ptr));
        self.points.deinit(allocator);
        allocator.destroy(self);
    }
};
