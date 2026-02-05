const std = @import("std");
const Engine = @import("../engine.zig").Engine;
const c = @import("../c.zig").c;

pub const ToolInterface = struct {
    ptr: *anyopaque,
    activateFn: *const fn(ptr: *anyopaque, engine: *Engine) void,
    deactivateFn: *const fn(ptr: *anyopaque, engine: *Engine) void,
    startFn: *const fn(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, button: u32, modifiers: u32) void,
    updateFn: *const fn(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void,
    endFn: *const fn(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void,
    motionFn: ?*const fn(ptr: *anyopaque, engine: *Engine, x: f64, y: f64) void,
    drawOverlayFn: *const fn(ptr: *anyopaque, cr: *c.cairo_t, scale: f64, view_x: f64, view_y: f64) void,
    destroyFn: *const fn(ptr: *anyopaque, allocator: std.mem.Allocator) void,

    pub fn activate(self: ToolInterface, engine: *Engine) void {
        self.activateFn(self.ptr, engine);
    }
    pub fn deactivate(self: ToolInterface, engine: *Engine) void {
        self.deactivateFn(self.ptr, engine);
    }
    pub fn start(self: ToolInterface, engine: *Engine, x: f64, y: f64, button: u32, modifiers: u32) void {
        self.startFn(self.ptr, engine, x, y, button, modifiers);
    }
    pub fn update(self: ToolInterface, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        self.updateFn(self.ptr, engine, x, y, modifiers);
    }
    pub fn end(self: ToolInterface, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        self.endFn(self.ptr, engine, x, y, modifiers);
    }
    pub fn motion(self: ToolInterface, engine: *Engine, x: f64, y: f64) void {
        if (self.motionFn) |fn_ptr| {
            fn_ptr(self.ptr, engine, x, y);
        }
    }
    pub fn drawOverlay(self: ToolInterface, cr: *c.cairo_t, scale: f64, view_x: f64, view_y: f64) void {
        self.drawOverlayFn(self.ptr, cr, scale, view_x, view_y);
    }
    pub fn destroy(self: ToolInterface, allocator: std.mem.Allocator) void {
        self.destroyFn(self.ptr, allocator);
    }
};
