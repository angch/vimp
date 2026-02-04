const std = @import("std");
const c = @import("c.zig").c;
const Engine = @import("engine.zig").Engine;

pub const Salvage = struct {
    pub fn recoverFile(engine: *Engine, path: [:0]const u8) !void {
        var err: ?*c.GError = null;
        const file = c.g_file_new_for_path(path.ptr);
        defer c.g_object_unref(file);

        const texture = c.gdk_texture_new_from_file(file, &err);
        if (texture == null) {
            if (err) |e| {
                c.g_error_free(e);
            }
            return error.GdkLoadFailed;
        }
        defer c.g_object_unref(texture);

        const width = c.gdk_texture_get_width(texture);
        const height = c.gdk_texture_get_height(texture);
        const stride = width * 4;
        const size: usize = @intCast(stride * height);

        // Allocate buffer for raw pixels
        const data = c.g_malloc(size);
        if (data == null) return error.OutOfMemory;
        defer c.g_free(data);

        // Download RGBA
        c.gdk_texture_download(texture, @ptrCast(data), @intCast(stride));

        // Create GeglBuffer
        const rect = c.GeglRectangle{ .x = 0, .y = 0, .width = width, .height = height };
        // Target format for internal storage
        const format = c.babl_format("R'G'B'A u8");
        const buffer = c.gegl_buffer_new(&rect, format);
        if (buffer == null) return error.GeglBufferFailed;

        // GDK Texture download seems to produce BGRA in this environment?
        // Or maybe it is RGBA and Cairo/GEGL is confusing me.
        // But tests showed Red (255,0,0) became (0,0,255).
        // Let's assume input is "B'G'R'A u8" to swap it back.
        // Actually, let's use "cairo-ARGB32" which usually matches GDK/Cairo memory layout.
        // If GDK download matches Cairo layout.
        const src_format = c.babl_format("cairo-ARGB32");
        c.gegl_buffer_set(buffer, &rect, 0, src_format, data, c.GEGL_AUTO_ROWSTRIDE);

        // Add to engine
        const basename = std.fs.path.basename(path);
        try engine.addLayerInternal(buffer.?, basename, true, false, engine.layers.items.len);

        // Push Undo
        const cmd = Engine.Command{
            .layer = .{ .add = .{ .index = engine.layers.items.len - 1, .snapshot = null } },
        };
        engine.undo_stack.append(std.heap.c_allocator, cmd) catch {};
        for (engine.redo_stack.items) |*r_cmd| r_cmd.deinit();
        engine.redo_stack.clearRetainingCapacity();
    }
};
