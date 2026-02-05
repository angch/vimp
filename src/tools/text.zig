const std = @import("std");
const ToolInterface = @import("interface.zig").ToolInterface;
const Engine = @import("../engine.zig").Engine;
const c = @import("../c.zig").c;
const TextDialog = @import("../widgets/text_dialog.zig");

pub const TextTool = struct {
    allocator: std.mem.Allocator,
    parent_window: ?*c.GtkWindow,
    on_complete: ?*const fn() void, // To refresh UI

    pub fn create(allocator: std.mem.Allocator, parent_window: ?*c.GtkWindow, on_complete: ?*const fn() void) !*TextTool {
        const self = try allocator.create(TextTool);
        self.* = .{
            .allocator = allocator,
            .parent_window = parent_window,
            .on_complete = on_complete,
        };
        return self;
    }

    pub fn interface(self: *TextTool) ToolInterface {
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
        _ = engine;
        _ = x;
        _ = y;
        _ = button;
        _ = modifiers;
    }

    fn update(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        _ = ptr;
        _ = engine;
        _ = x;
        _ = y;
        _ = modifiers;
    }

    const TextContext = struct {
        x: i32,
        y: i32,
        tool: *TextTool,
        engine: *Engine,
    };

    fn destroy_text_context(data: ?*anyopaque) void {
        const ctx: *TextContext = @ptrCast(@alignCast(data));
        std.heap.c_allocator.destroy(ctx);
    }

    fn on_text_insert(user_data: ?*anyopaque, text: [:0]const u8, size: i32) void {
        const ctx: *TextContext = @ptrCast(@alignCast(user_data));

        ctx.engine.drawText(text, ctx.x, ctx.y, size) catch |err| {
            std.debug.print("Failed to draw text: {}\n", .{err});
        };

        if (ctx.tool.on_complete) |cb| {
            cb();
        }
    }

    fn end(ptr: *anyopaque, engine: *Engine, x: f64, y: f64, modifiers: u32) void {
        const self: *TextTool = @ptrCast(@alignCast(ptr));
        _ = modifiers;

        const ix: i32 = @intFromFloat(x);
        const iy: i32 = @intFromFloat(y);

        if (std.heap.c_allocator.create(TextContext)) |ctx| {
            ctx.* = .{
                .x = ix,
                .y = iy,
                .tool = self,
                .engine = engine,
            };

            TextDialog.showTextDialog(self.parent_window, engine.font_size, &on_text_insert, ctx, &destroy_text_context) catch |err| {
                std.debug.print("Failed to show text dialog: {}\n", .{err});
                std.heap.c_allocator.destroy(ctx);
            };
        } else |_| {}
    }

    fn drawOverlay(ptr: *anyopaque, cr: *c.cairo_t, scale: f64, view_x: f64, view_y: f64) void {
        _ = ptr;
        _ = cr;
        _ = scale;
        _ = view_x;
        _ = view_y;
    }

    fn destroy(ptr: *anyopaque, allocator: std.mem.Allocator) void {
        const self: *TextTool = @ptrCast(@alignCast(ptr));
        allocator.destroy(self);
    }
};
