const std = @import("std");
const ToolInterface = @import("interface.zig").ToolInterface;
const Engine = @import("../engine.zig").Engine;
const c = @import("../c.zig").c;

pub const BucketFillTool = struct {
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator) !*BucketFillTool {
        const self = try allocator.create(BucketFillTool);
        self.* = .{
            .allocator = allocator,
        };
        return self;
    }

    pub fn interface(self: *BucketFillTool) ToolInterface {
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
        _ = ptr;
        _ = modifiers;
        engine.beginTransaction();
        if (button == 3) { // BG
            engine.bucketFillWithColor(x, y, engine.bg_color) catch |err| {
                std.debug.print("Bucket fill failed: {}\n", .{err});
            };
        } else { // FG
            engine.bucketFill(x, y) catch |err| {
                std.debug.print("Bucket fill failed: {}\n", .{err});
            };
        }
        engine.commitTransaction();
    }

    fn update(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        _ = ptr;
        _ = engine;
        _ = x;
        _ = y;
        _ = modifiers;
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
        const self: *BucketFillTool = @ptrCast(@alignCast(ptr));
        allocator.destroy(self);
    }
};
