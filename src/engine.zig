const std = @import("std");
const c = @import("c.zig").c;

pub const Engine = struct {
    graph: ?*c.GeglNode = null,
    output_node: ?*c.GeglNode = null,
    paint_buffer: ?*c.GeglBuffer = null,
    buffer_node: ?*c.GeglNode = null,
    canvas_width: c_int = 800,
    canvas_height: c_int = 600,
    fg_color: [4]u8 = .{ 0, 0, 0, 255 },
    brush_size: c_int = 3,

    pub fn init(self: *Engine) void {
        _ = self;
        // Accept null args for generic initialization
        c.gegl_init(null, null);
    }

    pub fn deinit(self: *Engine) void {
        if (self.paint_buffer) |buf| {
            c.g_object_unref(buf);
        }
        if (self.graph) |g| {
            c.g_object_unref(g);
        }
        c.gegl_exit();
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

        // Create a paint buffer (RGBA, transparent initially)
        const extent = c.GeglRectangle{ .x = 0, .y = 0, .width = self.canvas_width, .height = self.canvas_height };
        const format = c.babl_format("R'G'B'A u8");
        self.paint_buffer = c.gegl_buffer_new(&extent, format);

        // Node to read from paint buffer
        self.buffer_node = c.gegl_node_new_child(self.graph, "operation", "gegl:buffer-source", "buffer", self.paint_buffer, @as(?*anyopaque, null));

        // Composite paint layer over background using gegl:over
        const over_node = c.gegl_node_new_child(self.graph, "operation", "gegl:over", @as(?*anyopaque, null));

        // Connect: bg_crop -> over_node (input), buffer_node -> over_node (aux)
        _ = c.gegl_node_connect(over_node, "input", bg_crop, "output");
        _ = c.gegl_node_connect(over_node, "aux", self.buffer_node, "output");

        self.output_node = over_node;
    }

    pub fn paintStroke(self: *Engine, x0: f64, y0: f64, x1: f64, y1: f64) void {
        if (self.paint_buffer == null) return;

        const buf = self.paint_buffer.?;

        // Draw a simple line by setting pixels along the path
        // Using Bresenham-style drawing for simplicity
        const brush_size = self.brush_size;
        const format = c.babl_format("R'G'B'A u8");

        // Use selected foreground color
        var pixel: [4]u8 = self.fg_color;

        // Simple line drawing using interpolation
        const dx = x1 - x0;
        const dy = y1 - y0;
        const dist = @sqrt(dx * dx + dy * dy);
        const steps: usize = @max(1, @as(usize, @intFromFloat(dist)));

        for (0..steps + 1) |i| {
            const t: f64 = if (steps == 0) 0.0 else @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps));
            const x: c_int = @intFromFloat(x0 + dx * t);
            const y: c_int = @intFromFloat(y0 + dy * t);

            // Paint a small square brush
            const half = @divFloor(brush_size, 2);
            var by: c_int = -half;
            while (by <= half) : (by += 1) {
                var bx: c_int = -half;
                while (bx <= half) : (bx += 1) {
                    const px = x + bx;
                    const py = y + by;
                    if (px >= 0 and py >= 0 and px < self.canvas_width and py < self.canvas_height) {
                        const rect = c.GeglRectangle{ .x = px, .y = py, .width = 1, .height = 1 };
                        c.gegl_buffer_set(buf, &rect, 0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE);
                    }
                }
            }
        }
    }

    pub fn setFgColor(self: *Engine, r: u8, g: u8, b: u8, a: u8) void {
        self.fg_color = .{ r, g, b, a };
    }

    pub fn setBrushSize(self: *Engine, size: c_int) void {
        self.brush_size = size;
    }

    pub fn blit(self: *Engine, width: c_int, height: c_int, ptr: [*]u8, stride: c_int) void {
        if (self.output_node) |node| {
            const rect = c.GeglRectangle{ .x = 0, .y = 0, .width = width, .height = height };
            const format = c.babl_format("cairo-ARGB32");

            c.gegl_node_blit(node, 1.0, &rect, format, ptr, stride, c.GEGL_BLIT_DEFAULT);
        }
    }
};

test "Engine paint color" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // Set color to RED
    engine.setFgColor(255, 0, 0, 255);

    // Draw a single point/small line at 100,100
    engine.paintStroke(100, 100, 100, 100);

    // Read back pixel
    if (engine.paint_buffer) |buf| {
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 100, .y = 100, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);

        // Expect RED: 255, 0, 0, 255
        // std.testing.expectEqual is strict with types, use manual check or slice
        try std.testing.expectEqual(pixel[0], 255);
        try std.testing.expectEqual(pixel[1], 0);
        try std.testing.expectEqual(pixel[2], 0);
        try std.testing.expectEqual(pixel[3], 255);
    } else {
        return error.NoBuffer;
    }
}

test "Engine brush size" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    engine.setFgColor(255, 255, 255, 255); // White for visibility

    // 1. Large Brush (Size 5)
    engine.setBrushSize(5);
    engine.paintStroke(100, 100, 100, 100);

    // Center is 100,100.
    // Half is 2. Range: 98..102.
    // Pixel at 102, 102 should be painted.
    if (engine.paint_buffer) |buf| {
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 102, .y = 102, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 255);
    }

    // 2. Small Brush (Size 1)
    engine.setBrushSize(1);
    engine.paintStroke(200, 200, 200, 200);

    // Center 200,200.
    // Half 0. Range: 200..200.
    // Pixel at 201, 200 should NOT be painted (it should be 0 or transparent).
    if (engine.paint_buffer) |buf| {
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 201, .y = 200, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        // Expect empty/black (since buffer init is empty)
        try std.testing.expectEqual(pixel[0], 0);
        try std.testing.expectEqual(pixel[3], 0);
    }
}
