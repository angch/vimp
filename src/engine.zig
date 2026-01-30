const std = @import("std");
const c = @import("c.zig").c;

pub const Engine = struct {
    pub const Mode = enum {
        paint,
        erase,
        fill,
        airbrush,
    };

    pub const BrushType = enum {
        square,
        circle,
    };

    pub const SelectionMode = enum {
        rectangle,
        ellipse,
    };

    pub const Layer = struct {
        buffer: *c.GeglBuffer,
        source_node: *c.GeglNode,
        visible: bool = true,
        locked: bool = false,
        name: [64]u8 = undefined,
    };

    graph: ?*c.GeglNode = null,
    output_node: ?*c.GeglNode = null,
    layers: std.ArrayList(Layer) = undefined,
    active_layer_idx: usize = 0,

    base_node: ?*c.GeglNode = null,
    composition_nodes: std.ArrayList(*c.GeglNode) = undefined,

    canvas_width: c_int = 800,
    canvas_height: c_int = 600,
    fg_color: [4]u8 = .{ 0, 0, 0, 255 },
    brush_size: c_int = 3,
    mode: Mode = .paint,
    brush_type: BrushType = .square,
    selection: ?c.GeglRectangle = null,
    selection_mode: SelectionMode = .rectangle,

    // GEGL is not thread-safe for init/exit, and tests run in parallel.
    // We must serialize access to the GEGL global state.
    var gegl_mutex = std.Thread.Mutex{};

    pub fn init(self: *Engine) void {
        gegl_mutex.lock();
        // Accept null args for generic initialization
        c.gegl_init(null, null);
        self.layers = std.ArrayList(Layer){};
        self.composition_nodes = std.ArrayList(*c.GeglNode){};
    }

    pub fn deinit(self: *Engine) void {
        self.composition_nodes.deinit(std.heap.c_allocator);
        for (self.layers.items) |layer| {
            c.g_object_unref(layer.buffer);
            // nodes are owned by the graph generally, but if they are not added to graph yet?
            // "gegl_node_new_child" adds it to graph.
            // If we keep references to them in Layer, we might need to unref them if we own a ref.
            // But usually GEGL graph destruction handles children.
            // However, we might need to be careful.
            // For now, let's assume graph handles nodes.
        }
        self.layers.deinit(std.heap.c_allocator);

        if (self.graph) |g| {
            c.g_object_unref(g);
        }
        // c.gegl_exit();
        gegl_mutex.unlock();
    }

    pub fn setupGraph(self: *Engine) void {
        // Create the main graph container
        self.graph = c.gegl_node_new();

        const bg_color = c.gegl_color_new("rgb(0.9, 0.9, 0.9)");

        // Background color node
        const bg_node = c.gegl_node_new_child(self.graph, "operation", "gegl:color", "value", bg_color, @as(?*anyopaque, null));

        // A crop node to give the background finite dimensions
        const bg_crop = c.gegl_node_new_child(self.graph, "operation", "gegl:crop", "width", @as(f64, 800.0), "height", @as(f64, 600.0), @as(?*anyopaque, null));

        _ = c.gegl_node_link_many(bg_node, bg_crop, @as(?*anyopaque, null));

        self.base_node = bg_crop;

        // Add initial layer
        self.addLayer("Background") catch |err| {
            std.debug.print("Failed to add initial layer: {}\n", .{err});
        };
    }

    pub fn rebuildGraph(self: *Engine) void {
        // 1. Clear old composition chain (but don't destroy layer source nodes!)
        // The composition nodes are the 'gegl:over' nodes connecting layers.
        // We need to unlink them or destroy them. Since we created them, we can destroy them?
        // Wait, if they are children of 'graph', destroying graph destroys them.
        // But we are not destroying graph.
        // gegl_node_process works on the graph.

        // We stored the 'over' nodes in composition_nodes.
        // Let's just destroy them? But they are linked.
        // Removing them from graph should suffice?
        // gegl_node_remove_child(graph, node)?
        // Or simply unref if they are not added to graph?
        // 'gegl_node_new_child' adds them to graph.
        // So we should 'gegl_node_remove_child'? Or just disconnect?

        // Let's assume creating new nodes is cheap enough, but we should clean up old ones.
        // gegl_node_disconnect(node, "input")?

        // Actually, let's just create new ones and let the old ones drift?
        // No, that leaks memory and clutters graph.
        // We should destroy the old 'over' nodes.

        // NOTE: In C, we would do g_object_unref?
        // If gegl_node_new_child was used, the parent holds a ref.
        // So we need to remove from parent?
        // c.gegl_node_remove_child(self.graph, node);

        // Since we don't have gegl_node_remove_child in C bindings easily visible here (it exists in GEGL),
        // let's try to just build new ones and update output_node.
        // But over time this will grow infinite.
        // I should find a way to remove them.
        // 'c.gegl_node_remove_child' might not be in my c.zig?
        // Check c.zig? Assuming standard GEGL API.

        // Let's assume I can reuse the nodes? No, the number of nodes changes.
        // I will attempt to remove them.
        // If c.gegl_node_remove_child is not available, I might need to add it or use g_object_run_dispose?

        // For now, I'll rely on g_object_unref if I can remove them from graph.
        // But wait, gegl_node_new_child adds reference?

        // Strategy: Just unlink everything and overwrite output_node?
        // The old nodes will still be in the graph.

        // Let's look at c.zig if possible.
        // Assuming c.gegl_node_remove_child works if bound.

        for (self.composition_nodes.items) |node| {
             _ = c.gegl_node_remove_child(self.graph, node);
             // And unref? remove_child usually drops the parent's ref.
             // If we held a ref in ArrayList (we didn't explicitly ref, just stored pointer),
             // then we might be dangling if remove_child frees it.
             // But we probably want to ensure it's gone.
        }
        self.composition_nodes.clearRetainingCapacity();

        var current_input = self.base_node;

        for (self.layers.items) |layer| {
            if (!layer.visible) continue;

            if (c.gegl_node_new_child(self.graph, "operation", "gegl:over", @as(?*anyopaque, null))) |over_node| {
                _ = c.gegl_node_connect(over_node, "input", current_input, "output");
                _ = c.gegl_node_connect(over_node, "aux", layer.source_node, "output");

                self.composition_nodes.append(std.heap.c_allocator, over_node) catch {};
                current_input = over_node;
            }
        }

        self.output_node = current_input;
    }

    pub fn addLayer(self: *Engine, name: []const u8) !void {
        const extent = c.GeglRectangle{ .x = 0, .y = 0, .width = self.canvas_width, .height = self.canvas_height };
        const format = c.babl_format("R'G'B'A u8");
        const buffer = c.gegl_buffer_new(&extent, format) orelse return error.GeglBufferFailed;

        const source_node = c.gegl_node_new_child(self.graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null)) orelse return error.GeglNodeFailed;

        var layer = Layer{
            .buffer = buffer,
            .source_node = source_node,
            .visible = true,
            .locked = false,
        };
        // Copy name
        const len = @min(name.len, layer.name.len - 1);
        @memcpy(layer.name[0..len], name[0..len]);
        layer.name[len] = 0; // Null terminate

        try self.layers.append(std.heap.c_allocator, layer);
        self.active_layer_idx = self.layers.items.len - 1;

        self.rebuildGraph();
    }

    pub fn removeLayer(self: *Engine, index: usize) void {
        if (index >= self.layers.items.len) return;

        // If removing last layer, be careful?
        // We should probably ensure at least one layer? Or allow empty?
        // Allow empty for flexibility, but app might misbehave.

        const layer = self.layers.orderedRemove(index);

        // Clean up
        _ = c.gegl_node_remove_child(self.graph, layer.source_node);
        c.g_object_unref(layer.buffer);

        // Update active index
        if (self.active_layer_idx >= self.layers.items.len) {
            if (self.layers.items.len > 0) {
                self.active_layer_idx = self.layers.items.len - 1;
            } else {
                self.active_layer_idx = 0; // Or invalid
            }
        }

        self.rebuildGraph();
    }

    pub fn reorderLayer(self: *Engine, from: usize, to: usize) void {
        if (from >= self.layers.items.len or to >= self.layers.items.len) return;
        if (from == to) return;

        const layer = self.layers.orderedRemove(from);
        self.layers.insert(std.heap.c_allocator, to, layer) catch {
            // Put it back?
            // This shouldn't fail if capacity is enough, but insert might alloc.
            // If it fails, we lost the layer?
            // Let's assume panic on OOM for now or handle better.
            // Pushing back to end is safer if insert fails?
             self.layers.append(std.heap.c_allocator, layer) catch {};
             return;
        };

        // Update active index if it moved
        if (self.active_layer_idx == from) {
            self.active_layer_idx = to;
        } else if (from < self.active_layer_idx and to >= self.active_layer_idx) {
            self.active_layer_idx -= 1;
        } else if (from > self.active_layer_idx and to <= self.active_layer_idx) {
            self.active_layer_idx += 1;
        }

        self.rebuildGraph();
    }

    pub fn setActiveLayer(self: *Engine, index: usize) void {
        if (index < self.layers.items.len) {
            self.active_layer_idx = index;
        }
    }

    pub fn toggleLayerVisibility(self: *Engine, index: usize) void {
        if (index < self.layers.items.len) {
            self.layers.items[index].visible = !self.layers.items[index].visible;
            self.rebuildGraph();
        }
    }

    pub fn toggleLayerLock(self: *Engine, index: usize) void {
        if (index < self.layers.items.len) {
            self.layers.items[index].locked = !self.layers.items[index].locked;
        }
    }

    fn isPointInSelection(self: *Engine, x: c_int, y: c_int) bool {
        if (self.selection) |sel| {
            if (x < sel.x or x >= sel.x + sel.width or y < sel.y or y >= sel.y + sel.height) return false;

            if (self.selection_mode == .ellipse) {
                const cx = @as(f64, @floatFromInt(sel.x)) + @as(f64, @floatFromInt(sel.width)) / 2.0;
                const cy = @as(f64, @floatFromInt(sel.y)) + @as(f64, @floatFromInt(sel.height)) / 2.0;
                const rx = @as(f64, @floatFromInt(sel.width)) / 2.0;
                const ry = @as(f64, @floatFromInt(sel.height)) / 2.0;
                const dx_p = @as(f64, @floatFromInt(x)) + 0.5 - cx;
                const dy_p = @as(f64, @floatFromInt(y)) + 0.5 - cy;

                if ((dx_p * dx_p) / (rx * rx) + (dy_p * dy_p) / (ry * ry) > 1.0) return false;
            }
        }
        return true;
    }

    pub fn paintStroke(self: *Engine, x0: f64, y0: f64, x1: f64, y1: f64, pressure: f64) void {
        if (self.active_layer_idx >= self.layers.items.len) return;
        const layer = &self.layers.items[self.active_layer_idx];

        if (!layer.visible or layer.locked) return;

        const buf = layer.buffer;

        // Draw a simple line by setting pixels along the path
        // Using Bresenham-style drawing for simplicity
        const brush_size = self.brush_size;
        const format = c.babl_format("R'G'B'A u8");

        // Use selected foreground color, or transparent if erasing
        var pixel: [4]u8 = undefined;
        if (self.mode == .erase) {
            pixel = .{ 0, 0, 0, 0 };
        } else {
            pixel = self.fg_color;
            if (self.mode == .airbrush) {
                // Modulate alpha by pressure
                // pixel[3] is u8 (0-255)
                const alpha: f64 = @as(f64, @floatFromInt(pixel[3]));
                const new_alpha: u8 = @intFromFloat(alpha * pressure);
                pixel[3] = new_alpha;
            }
        }

        // Simple line drawing using interpolation
        const dx = x1 - x0;
        const dy = y1 - y0;
        const dist = @sqrt(dx * dx + dy * dy);
        const steps: usize = @max(1, @as(usize, @intFromFloat(dist)));

        for (0..steps + 1) |i| {
            const t: f64 = if (steps == 0) 0.0 else @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps));
            const x: c_int = @intFromFloat(x0 + dx * t);
            const y: c_int = @intFromFloat(y0 + dy * t);

            // Paint a small brush
            const half = @divFloor(brush_size, 2);
            const radius_sq = if (self.brush_type == .circle)
                std.math.pow(f64, @as(f64, @floatFromInt(brush_size)) / 2.0, 2.0)
            else
                0;

            var by: c_int = -half;
            while (by <= half) : (by += 1) {
                var bx: c_int = -half;
                while (bx <= half) : (bx += 1) {
                    // Check shape
                    if (self.brush_type == .circle) {
                        const dist_sq = @as(f64, @floatFromInt(bx * bx + by * by));
                        if (dist_sq > radius_sq) continue;
                    }

                    const px = x + bx;
                    const py = y + by;

                    if (!self.isPointInSelection(px, py)) continue;

                    if (px >= 0 and py >= 0 and px < self.canvas_width and py < self.canvas_height) {
                        const rect = c.GeglRectangle{ .x = px, .y = py, .width = 1, .height = 1 };
                        c.gegl_buffer_set(buf, &rect, 0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE);
                    }
                }
            }
        }
    }

    pub fn bucketFill(self: *Engine, start_x: f64, start_y: f64) !void {
        if (self.active_layer_idx >= self.layers.items.len) return;
        const layer = &self.layers.items[self.active_layer_idx];

        if (!layer.visible or layer.locked) return;

        const buf = layer.buffer;

        const w: usize = @intCast(self.canvas_width);
        const h: usize = @intCast(self.canvas_height);
        const x: c_int = @intFromFloat(start_x);
        const y: c_int = @intFromFloat(start_y);

        if (x < 0 or x >= self.canvas_width or y < 0 or y >= self.canvas_height) return;

        if (!self.isPointInSelection(x, y)) return;

        // 1. Read entire buffer
        // Allocation: 800 * 600 * 4 = 1.9 MB approx
        const allocator = std.heap.c_allocator; // Use C allocator for simplicity with large buffer
        const buffer_size = w * h * 4;
        const pixels = try allocator.alloc(u8, buffer_size);
        defer allocator.free(pixels);

        const rect = c.GeglRectangle{ .x = 0, .y = 0, .width = self.canvas_width, .height = self.canvas_height };
        const format = c.babl_format("R'G'B'A u8");
        // Rowstride must be correct
        const rowstride: c_int = self.canvas_width * 4;
        c.gegl_buffer_get(buf, &rect, 1.0, format, pixels.ptr, rowstride, c.GEGL_ABYSS_NONE);

        // 2. Identify Target Color
        const idx: usize = (@as(usize, @intCast(y)) * w + @as(usize, @intCast(x))) * 4;
        const target_color: [4]u8 = pixels[idx..][0..4].*;
        const fill_color: [4]u8 = self.fg_color;

        // If target matches fill, nothing to do
        if (std.mem.eql(u8, &target_color, &fill_color)) return;

        // 3. Setup Flood Fill (BFS)
        const Point = struct { x: c_int, y: c_int };
        var queue = std.ArrayList(Point){};
        defer queue.deinit(allocator);

        try queue.append(allocator, .{ .x = x, .y = y });

        var min_x = x;
        var max_x = x;
        var min_y = y;
        var max_y = y;

        while (queue.items.len > 0) {
            const p = queue.pop().?;
            const px = p.x;
            const py = p.y;

            if (px < 0 or px >= self.canvas_width or py < 0 or py >= self.canvas_height) continue;

            if (!self.isPointInSelection(px, py)) continue;

            const p_idx: usize = (@as(usize, @intCast(py)) * w + @as(usize, @intCast(px))) * 4;
            const current_pixel = pixels[p_idx..][0..4];

            // Check if matches target
            if (!std.mem.eql(u8, current_pixel, &target_color)) continue;

            // Fill
            @memcpy(current_pixel, &fill_color);

            // Update dirty bounds
            if (px < min_x) min_x = px;
            if (px > max_x) max_x = px;
            if (py < min_y) min_y = py;
            if (py > max_y) max_y = py;

            // Neighbors
            try queue.append(allocator, .{ .x = px + 1, .y = py });
            try queue.append(allocator, .{ .x = px - 1, .y = py });
            try queue.append(allocator, .{ .x = px, .y = py + 1 });
            try queue.append(allocator, .{ .x = px, .y = py - 1 });
        }

        // 4. Write back buffer (Only dirty rect)
        const rect_w = max_x - min_x + 1;
        const rect_h = max_y - min_y + 1;
        const dirty_rect = c.GeglRectangle{ .x = min_x, .y = min_y, .width = rect_w, .height = rect_h };

        const offset = (@as(usize, @intCast(min_y)) * w + @as(usize, @intCast(min_x))) * 4;
        c.gegl_buffer_set(buf, &dirty_rect, 0, format, pixels.ptr + offset, rowstride);
    }

    pub fn setFgColor(self: *Engine, r: u8, g: u8, b: u8, a: u8) void {
        self.fg_color = .{ r, g, b, a };
    }

    pub fn setBrushSize(self: *Engine, size: c_int) void {
        self.brush_size = size;
    }

    pub fn setMode(self: *Engine, mode: Mode) void {
        self.mode = mode;
    }

    pub fn setBrushType(self: *Engine, brush_type: BrushType) void {
        self.brush_type = brush_type;
    }

    pub fn setSelectionMode(self: *Engine, mode: SelectionMode) void {
        self.selection_mode = mode;
    }

    pub fn setSelection(self: *Engine, x: c_int, y: c_int, w: c_int, h: c_int) void {
        self.selection = c.GeglRectangle{ .x = x, .y = y, .width = w, .height = h };
    }

    pub fn clearSelection(self: *Engine) void {
        self.selection = null;
    }

    pub fn blit(self: *Engine, width: c_int, height: c_int, ptr: [*]u8, stride: c_int) void {
        self.blitView(width, height, ptr, stride, 1.0, 0.0, 0.0);
    }

    pub fn blitView(self: *Engine, width: c_int, height: c_int, ptr: [*]u8, stride: c_int, scale: f64, view_x: f64, view_y: f64) void {
        if (self.output_node) |node| {
            const rect = c.GeglRectangle{ .x = @intFromFloat(view_x), .y = @intFromFloat(view_y), .width = width, .height = height };
            const format = c.babl_format("cairo-ARGB32");

            c.gegl_node_blit(node, scale, &rect, format, ptr, stride, c.GEGL_BLIT_DEFAULT);
        }
    }
};

// TESTS COMMENTED OUT temporarily to allow build

test "Engine paint color" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // Set color to RED
    engine.setFgColor(255, 0, 0, 255);

    // Draw a single point/small line at 100,100
    engine.paintStroke(100, 100, 100, 100, 1.0);

    // Read back pixel
    if (engine.layers.items.len > 0) {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 100, .y = 100, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);

        try std.testing.expectEqual(pixel[0], 255);
        try std.testing.expectEqual(pixel[1], 0);
        try std.testing.expectEqual(pixel[2], 0);
        try std.testing.expectEqual(pixel[3], 255);
    } else {
        return error.NoLayer;
    }
}

test "Engine multiple layers" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // Layer 1 (Background) is index 0.
    // Add Layer 2.
    try engine.addLayer("Layer 2");
    // active layer should be 1.
    try std.testing.expectEqual(engine.active_layer_idx, 1);

    // Paint BLUE on Layer 2 at 100,100
    engine.setFgColor(0, 0, 255, 255);
    engine.paintStroke(100, 100, 100, 100, 1.0);

    // Switch to Layer 1
    engine.setActiveLayer(0);
    // Paint RED on Layer 1 at 100,100
    engine.setFgColor(255, 0, 0, 255);
    engine.paintStroke(100, 100, 100, 100, 1.0); // This writes to Layer 1

    // Verify Layer 2 is Blue
    {
        const buf = engine.layers.items[1].buffer;
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 100, .y = 100, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[2], 255); // Blue
    }

    // Verify Layer 1 is Red
    {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 100, .y = 100, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 255); // Red
    }
}

test "Engine layer visibility" {
    // This test requires rendering the graph, which might be tricky in headless test environment
    // if plugins are not loaded correctly. But 'gegl:over' is core.
    // Let's try to blitView to a buffer.

    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // Layer 1: Red at 100,100
    engine.setActiveLayer(0);
    engine.setFgColor(255, 0, 0, 255);
    engine.paintStroke(100, 100, 100, 100, 1.0);

    // Layer 2: Blue at 100,100 (Covering Red)
    try engine.addLayer("Layer 2");
    engine.setFgColor(0, 0, 255, 255);
    engine.paintStroke(100, 100, 100, 100, 1.0);

    // Render 1x1 pixel at 100,100.
    var pixel: [4]u8 = undefined;

    // Helper to render
    const render = struct {
        fn func(e: *Engine, p: *[4]u8) void {
            // View x=100, y=100. Width=1, Height=1. Scale=1.0.
            // Stride=4.
            e.blitView(1, 1, p, 4, 1.0, 100.0, 100.0);
        }
    }.func;

    // 1. Both Visible -> Should be Blue
    render(&engine, &pixel);
    // Cairo ARGB32: B G R A (Little Endian)
    // Blue: 255, 0, 0, 255 -> B=255, G=0, R=0, A=255.
    // Memory: 255, 0, 0, 255.
    // Wait, let's just check raw values. Blue should be dominant.
    // If Blue is on top, pixel[0] (B) should be 255.
    // Note: babl format "cairo-ARGB32" in blitView.
    try std.testing.expect(pixel[0] > 200); // Blue
    try std.testing.expect(pixel[2] < 50);  // Red

    // 2. Hide Layer 2 -> Should be Red
    engine.toggleLayerVisibility(1);
    render(&engine, &pixel);
    try std.testing.expect(pixel[2] > 200); // Red
    try std.testing.expect(pixel[0] < 50);  // Blue
}

test "Engine brush size" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    engine.setFgColor(255, 255, 255, 255); // White for visibility

    // 1. Large Brush (Size 5)
    engine.setBrushSize(5);
    engine.paintStroke(100, 100, 100, 100, 1.0);

    if (engine.layers.items.len > 0) {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 102, .y = 102, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 255);
    } else {
        return error.NoLayer;
    }
}

test "Engine eraser" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    engine.setFgColor(255, 0, 0, 255); // Red

    // 1. Paint Red at 50,50
    engine.paintStroke(50, 50, 50, 50, 1.0);

    if (engine.layers.items.len > 0) {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 50, .y = 50, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 255);
        try std.testing.expectEqual(pixel[3], 255);

        // 2. Switch to Erase
        engine.setMode(.erase);
        // 3. Erase at 50,50
        engine.paintStroke(50, 50, 50, 50, 1.0);

        var pixel2: [4]u8 = .{ 255, 255, 255, 255 };
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel2, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);

        try std.testing.expectEqual(pixel2[0], 0);
        try std.testing.expectEqual(pixel2[3], 0);
    }
}

test "Engine bucket fill" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    engine.setFgColor(255, 0, 0, 255); // Red

    // 1. Paint a closed box
    engine.setBrushSize(1);
    engine.paintStroke(10, 10, 30, 10, 1.0);
    engine.paintStroke(10, 30, 30, 30, 1.0);
    engine.paintStroke(10, 10, 10, 30, 1.0);
    engine.paintStroke(30, 10, 30, 30, 1.0);

    // 2. Fill inside with BLUE
    engine.setFgColor(0, 0, 255, 255);
    try engine.bucketFill(20, 20);

    if (engine.layers.items.len > 0) {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = undefined;
        var rect = c.GeglRectangle{ .x = 20, .y = 20, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);

        // Assert Blue
        try std.testing.expectEqual(pixel[2], 255);
        try std.testing.expectEqual(pixel[3], 255);
    }
}

test "Engine brush shapes" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    engine.setFgColor(255, 255, 255, 255);

    engine.setBrushSize(5);

    // 1. Square (Default)
    engine.paintStroke(100, 100, 100, 100, 1.0);

    if (engine.layers.items.len > 0) {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 102, .y = 102, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 255);

        // 2. Circle
        engine.setBrushType(.circle);
        engine.paintStroke(200, 200, 200, 200, 1.0);

        var rect2 = c.GeglRectangle{ .x = 202, .y = 202, .width = 1, .height = 1 };
        c.gegl_buffer_get(buf, &rect2, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        // Should be unpainted (0)
        try std.testing.expectEqual(pixel[0], 0);
    }
}

test "Engine selection clipping" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    engine.setFgColor(255, 255, 255, 255);

    engine.setSelection(10, 10, 10, 10);

    // 1. Paint inside
    engine.paintStroke(15, 15, 15, 15, 1.0);
    if (engine.layers.items.len > 0) {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 15, .y = 15, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 255);

        // 2. Paint outside
        engine.paintStroke(5, 5, 5, 5, 1.0);
        var rect2 = c.GeglRectangle{ .x = 5, .y = 5, .width = 1, .height = 1 };
        c.gegl_buffer_get(buf, &rect2, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 0);
    }
}
