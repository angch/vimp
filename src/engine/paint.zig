const std = @import("std");
const c = @import("../c.zig").c;
const Types = @import("types.zig");
const Point = Types.Point;
const PaintContext = Types.PaintContext;
const BrushOptions = Types.BrushOptions;

pub fn isPointInSelection(ctx: PaintContext, x: c_int, y: c_int) bool {
    if (ctx.selection) |sel| {
        if (x < sel.x or x >= sel.x + sel.width or y < sel.y or y >= sel.y + sel.height) return false;

        if (ctx.selection_mode == .ellipse) {
            const dx_p = @as(f64, @floatFromInt(x)) + 0.5 - ctx.sel_cx;
            const dy_p = @as(f64, @floatFromInt(y)) + 0.5 - ctx.sel_cy;

            if ((dx_p * dx_p) * ctx.sel_inv_rx_sq + (dy_p * dy_p) * ctx.sel_inv_ry_sq > 1.0) return false;
        } else if (ctx.selection_mode == .lasso) {
            // Ray Casting Algorithm (Even-Odd Rule)
            const px = @as(f64, @floatFromInt(x)) + 0.5;
            const py = @as(f64, @floatFromInt(y)) + 0.5;
            var inside = false;
            const points = ctx.selection_points;
            var j = points.len - 1;
            for (points, 0..) |pi, i| {
                const pj = points[j];
                if (((pi.y > py) != (pj.y > py)) and
                    (px < (pj.x - pi.x) * (py - pi.y) / (pj.y - pi.y) + pi.x))
                {
                    inside = !inside;
                }
                j = i;
            }
            return inside;
        }
    }
    return true;
}

pub fn paintStroke(ctx: PaintContext, opts: BrushOptions, x0: f64, y0: f64, x1: f64, y1: f64) void {
    const buf = ctx.buffer;
    const brush_size = opts.size;
    const format = c.babl_format("R'G'B'A u8");

    // Use selected foreground color, or transparent if erasing
    var pixel: [4]u8 = undefined;
    if (opts.mode == .erase) {
        pixel = .{ 0, 0, 0, 0 };
    } else {
        pixel = opts.color;

        // Apply Opacity
        var alpha: f64 = @as(f64, @floatFromInt(pixel[3])) * opts.opacity;

        if (opts.mode == .airbrush) {
            // Modulate alpha by pressure
            alpha *= opts.pressure;
        }

        pixel[3] = @intFromFloat(alpha);
    }

    // Simple line drawing using interpolation
    const dx = x1 - x0;
    const dy = y1 - y0;
    const dist = @sqrt(dx * dx + dy * dy);
    const steps: usize = @max(1, @as(usize, @intFromFloat(dist)));

    // Paint a small brush
    const half = @divFloor(brush_size, 2);
    const radius_sq = if (opts.type == .circle)
        std.math.pow(f64, @as(f64, @floatFromInt(brush_size)) / 2.0, 2.0)
    else
        0;

    for (0..steps + 1) |i| {
        const t: f64 = if (steps == 0) 0.0 else @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps));
        const x: c_int = @intFromFloat(x0 + dx * t);
        const y: c_int = @intFromFloat(y0 + dy * t);

        if (opts.mode == .airbrush) {
            const random = std.crypto.random;
            const r = @as(f64, @floatFromInt(brush_size)) / 2.0;
            // Density: Paint roughly 10% of area per step multiplied by pressure
            // Area = pi * r^2
            const area = std.math.pi * r * r;
            const count_f = area * 0.1 * opts.pressure;
            const count: usize = @max(1, @as(usize, @intFromFloat(count_f)));

            for (0..count) |_| {
                const theta = random.float(f64) * 2.0 * std.math.pi;
                const rad = r * @sqrt(random.float(f64));

                const rx = rad * @cos(theta);
                const ry = rad * @sin(theta);

                const px: c_int = @intFromFloat(@as(f64, @floatFromInt(x)) + rx);
                const py: c_int = @intFromFloat(@as(f64, @floatFromInt(y)) + ry);

                if (!isPointInSelection(ctx, px, py)) continue;

                if (px >= 0 and py >= 0 and px < ctx.canvas_width and py < ctx.canvas_height) {
                    const rect = c.GeglRectangle{ .x = px, .y = py, .width = 1, .height = 1 };
                    c.gegl_buffer_set(buf, &rect, 0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE);
                }
            }
        } else {
            var by: c_int = -half;
            while (by <= half) : (by += 1) {
                var bx: c_int = -half;
                while (bx <= half) : (bx += 1) {
                    // Check shape
                    if (opts.type == .circle) {
                        const dist_sq = @as(f64, @floatFromInt(bx * bx + by * by));
                        if (dist_sq > radius_sq) continue;
                    }

                    const px = x + bx;
                    const py = y + by;

                    if (!isPointInSelection(ctx, px, py)) continue;

                    if (px >= 0 and py >= 0 and px < ctx.canvas_width and py < ctx.canvas_height) {
                        const rect = c.GeglRectangle{ .x = px, .y = py, .width = 1, .height = 1 };
                        c.gegl_buffer_set(buf, &rect, 0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE);
                    }
                }
            }
        }
    }
}

pub fn bucketFill(ctx: PaintContext, start_x: f64, start_y: f64, fill_color: [4]u8) !void {
    const buf = ctx.buffer;
    const w: usize = @intCast(ctx.canvas_width);
    const h: usize = @intCast(ctx.canvas_height);
    const x: c_int = @intFromFloat(start_x);
    const y: c_int = @intFromFloat(start_y);

    if (x < 0 or x >= ctx.canvas_width or y < 0 or y >= ctx.canvas_height) return;

    if (!isPointInSelection(ctx, x, y)) return;

    // 1. Read entire buffer
    const allocator = std.heap.c_allocator;
    const buffer_size = w * h * 4;
    const pixels = try allocator.alloc(u8, buffer_size);
    defer allocator.free(pixels);

    const rect = c.GeglRectangle{ .x = 0, .y = 0, .width = ctx.canvas_width, .height = ctx.canvas_height };
    const format = c.babl_format("R'G'B'A u8");
    const rowstride: c_int = ctx.canvas_width * 4;
    c.gegl_buffer_get(buf, &rect, 1.0, format, pixels.ptr, rowstride, c.GEGL_ABYSS_NONE);

    // 2. Identify Target Color
    const idx: usize = (@as(usize, @intCast(y)) * w + @as(usize, @intCast(x))) * 4;
    const target_color: [4]u8 = pixels[idx..][0..4].*;

    // If target matches fill, nothing to do
    if (std.mem.eql(u8, &target_color, &fill_color)) return;

    // 3. Setup Flood Fill (BFS)
    const IntPoint = struct { x: c_int, y: c_int };
    var queue = std.ArrayList(IntPoint){};
    defer queue.deinit(allocator);

    // Fill start pixel and add to queue
    @memcpy(pixels[idx..][0..4], &fill_color);
    try queue.append(allocator, .{ .x = x, .y = y });

    var min_x = x;
    var max_x = x;
    var min_y = y;
    var max_y = y;

    while (queue.items.len > 0) {
        const p = queue.pop().?;

        // Neighbors
        const neighbors = [4]IntPoint{
            .{ .x = p.x + 1, .y = p.y },
            .{ .x = p.x - 1, .y = p.y },
            .{ .x = p.x, .y = p.y + 1 },
            .{ .x = p.x, .y = p.y - 1 },
        };

        for (neighbors) |n| {
            const px = n.x;
            const py = n.y;

            if (px < 0 or px >= ctx.canvas_width or py < 0 or py >= ctx.canvas_height) continue;
            if (!isPointInSelection(ctx, px, py)) continue;

            const p_idx: usize = (@as(usize, @intCast(py)) * w + @as(usize, @intCast(px))) * 4;
            const current_pixel = pixels[p_idx..][0..4];

            // Check if matches target
            if (std.mem.eql(u8, current_pixel, &target_color)) {
                // Fill immediately
                @memcpy(current_pixel, &fill_color);

                // Update dirty bounds
                if (px < min_x) min_x = px;
                if (px > max_x) max_x = px;
                if (py < min_y) min_y = py;
                if (py > max_y) max_y = py;

                try queue.append(allocator, n);
            }
        }
    }

    // 4. Write back buffer (Only dirty rect)
    const rect_w = max_x - min_x + 1;
    const rect_h = max_y - min_y + 1;
    const dirty_rect = c.GeglRectangle{ .x = min_x, .y = min_y, .width = rect_w, .height = rect_h };

    const offset = (@as(usize, @intCast(min_y)) * w + @as(usize, @intCast(min_x))) * 4;
    c.gegl_buffer_set(buf, &dirty_rect, 0, format, pixels.ptr + offset, rowstride);
}

pub fn drawLine(ctx: PaintContext, opts: BrushOptions, x1: c_int, y1: c_int, x2: c_int, y2: c_int) void {
    const fx1: f64 = @floatFromInt(x1);
    const fy1: f64 = @floatFromInt(y1);
    const fx2: f64 = @floatFromInt(x2);
    const fy2: f64 = @floatFromInt(y2);

    paintStroke(ctx, opts, fx1, fy1, fx2, fy2);
}

pub fn drawCurve(ctx: PaintContext, opts: BrushOptions, x1: c_int, y1: c_int, x2: c_int, y2: c_int, cx1: c_int, cy1: c_int, cx2: c_int, cy2: c_int) void {
    // Flatten bezier
    // Estimate length for steps
    const d1 = @abs(cx1 - x1) + @abs(cy1 - y1);
    const d2 = @abs(cx2 - cx1) + @abs(cy2 - cy1);
    const d3 = @abs(x2 - cx2) + @abs(y2 - cy2);
    const len = d1 + d2 + d3;

    // Ensure at least 1 step, max reasonable (e.g. 1 step per pixel or so)
    var steps: usize = @intCast(len);
    if (steps < 10) steps = 10;
    if (steps > 2000) steps = 2000;

    var prev_x: f64 = @floatFromInt(x1);
    var prev_y: f64 = @floatFromInt(y1);

    const fx1: f64 = @floatFromInt(x1);
    const fy1: f64 = @floatFromInt(y1);
    const fx2: f64 = @floatFromInt(x2);
    const fy2: f64 = @floatFromInt(y2);
    const fcx1: f64 = @floatFromInt(cx1);
    const fcy1: f64 = @floatFromInt(cy1);
    const fcx2: f64 = @floatFromInt(cx2);
    const fcy2: f64 = @floatFromInt(cy2);

    var i: usize = 1;
    while (i <= steps) : (i += 1) {
        const t: f64 = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps));
        const it = 1.0 - t;

        const b1 = it * it * it;
        const b2 = 3.0 * it * it * t;
        const b3 = 3.0 * it * t * t;
        const b4 = t * t * t;

        const px = b1 * fx1 + b2 * fcx1 + b3 * fcx2 + b4 * fx2;
        const py = b1 * fy1 + b2 * fcy1 + b3 * fcy2 + b4 * fy2;

        paintStroke(ctx, opts, prev_x, prev_y, px, py);
        prev_x = px;
        prev_y = py;
    }
}

pub fn drawPolygon(ctx: PaintContext, opts: BrushOptions, points: []const Point, thickness: c_int, filled: bool) !void {
    if (points.len < 2) return;

    if (filled) {
        // Scanline Fill
        const buf = ctx.buffer;

        // 1. Calculate Bounds
        var min_x: f64 = points[0].x;
        var min_y: f64 = points[0].y;
        var max_x: f64 = points[0].x;
        var max_y: f64 = points[0].y;

        for (points) |p| {
            if (p.x < min_x) min_x = p.x;
            if (p.x > max_x) max_x = p.x;
            if (p.y < min_y) min_y = p.y;
            if (p.y > max_y) max_y = p.y;
        }

        const bx: c_int = @intFromFloat(min_x);
        const by: c_int = @intFromFloat(min_y);
        const bw: c_int = @intFromFloat(max_x - min_x + 1.0);
        const bh: c_int = @intFromFloat(max_y - min_y + 1.0);

        if (bw <= 0 or bh <= 0) return;

        // 2. Read Buffer
        const rect = c.GeglRectangle{ .x = bx, .y = by, .width = bw, .height = bh };
        const format = c.babl_format("R'G'B'A u8");
        const stride = bw * 4;
        const size: usize = @intCast(bw * bh * 4);

        const allocator = std.heap.c_allocator;
        const pixels = try allocator.alloc(u8, size);
        defer allocator.free(pixels);

        c.gegl_buffer_get(buf, &rect, 1.0, format, pixels.ptr, stride, c.GEGL_ABYSS_NONE);

        // 3. Scanline
        const y_start = by;
        const y_end = by + bh;

        // Intersections list
        var intersections = std.ArrayList(f64){};
        defer intersections.deinit(allocator);

        var y: c_int = y_start;
        while (y < y_end) : (y += 1) {
            const y_f = @as(f64, @floatFromInt(y)) + 0.5;
            intersections.clearRetainingCapacity();

            // Find intersections
            var i: usize = 0;
            const n = points.len;
            while (i < n) : (i += 1) {
                const p1 = points[i];
                const p2 = points[(i + 1) % n];

                if ((p1.y <= y_f and p2.y > y_f) or (p2.y <= y_f and p1.y > y_f)) {
                    const t = (y_f - p1.y) / (p2.y - p1.y);
                    const x = p1.x + t * (p2.x - p1.x);
                    try intersections.append(allocator, x);
                }
            }

            // Sort X
            std.mem.sort(f64, intersections.items, {}, std.sort.asc(f64));

            // Fill pairs
            var k: usize = 0;
            while (k < intersections.items.len) : (k += 2) {
                if (k + 1 >= intersections.items.len) break;
                const x1 = intersections.items[k];
                const x2 = intersections.items[k + 1];

                const ix1: c_int = @intFromFloat(std.math.ceil(x1 - 0.5));
                const ix2: c_int = @intFromFloat(std.math.floor(x2 - 0.5));

                const start = @max(bx, ix1);
                const end = @min(bx + bw - 1, ix2);

                if (start <= end) {
                    var px = start;
                    while (px <= end) : (px += 1) {
                        if (!isPointInSelection(ctx, px, y)) continue;

                        const local_x = px - bx;
                        const local_y = y - by;
                        const idx = (@as(usize, @intCast(local_y)) * @as(usize, @intCast(bw)) + @as(usize, @intCast(local_x))) * 4;

                        @memcpy(pixels[idx..][0..4], &opts.color);
                    }
                }
            }
        }

        // 4. Write Back
        c.gegl_buffer_set(buf, &rect, 0, format, pixels.ptr, stride);
    } else {
        // Outline
        // Temporarily override brush size
        var outline_opts = opts;
        outline_opts.size = thickness;
        var i: usize = 0;
        while (i < points.len) : (i += 1) {
            const p1 = points[i];
            const p2 = points[(i + 1) % points.len];
            paintStroke(ctx, outline_opts, p1.x, p1.y, p2.x, p2.y);
        }
    }
}

pub fn drawRectangle(ctx: PaintContext, opts: BrushOptions, x: c_int, y: c_int, w: c_int, h: c_int, thickness: c_int, filled: bool) !void {
    const buf = ctx.buffer;

    // Normalize
    var rx = x;
    var ry = y;
    var rw = w;
    var rh = h;

    if (rw < 0) {
        rx += rw;
        rw = -rw;
    }
    if (rh < 0) {
        ry += rh;
        rh = -rh;
    }
    if (rw == 0 or rh == 0) return;

    if (filled) {
        // Direct buffer fill
        // Note: For large fills, chunking or GEGL operations might be faster, but direct access is consistent.
        const rect = c.GeglRectangle{ .x = rx, .y = ry, .width = rw, .height = rh };
        const format = c.babl_format("R'G'B'A u8");
        const stride = rw * 4;
        const size: usize = @intCast(rw * rh * 4);

        const allocator = std.heap.c_allocator;
        const pixels = try allocator.alloc(u8, size);
        defer allocator.free(pixels);

        // Read (to handle selection and blending if we implemented it, but here we replace or just check selection)
        // If we want to support partial selection, we must read.
        c.gegl_buffer_get(buf, &rect, 1.0, format, pixels.ptr, stride, c.GEGL_ABYSS_NONE);

        var py: c_int = 0;
        while (py < rh) : (py += 1) {
            var px: c_int = 0;
            while (px < rw) : (px += 1) {
                const global_x = rx + px;
                const global_y = ry + py;
                if (!isPointInSelection(ctx, global_x, global_y)) continue;

                const idx = (@as(usize, @intCast(py)) * @as(usize, @intCast(rw)) + @as(usize, @intCast(px))) * 4;
                @memcpy(pixels[idx..][0..4], &opts.color);
            }
        }
        c.gegl_buffer_set(buf, &rect, 0, format, pixels.ptr, stride);

    } else {
        // Outline
        var outline_opts = opts;
        outline_opts.size = thickness; // Use brush size as thickness?
        // Actually drawRectangle usually creates sharp edges, not round brush strokes.
        // But reusing paintStroke with square brush approximates it if thickness is brush size.
        // However, standard drawRect usually means 1px lines or thick lines.
        // Let's use recursive filled drawRectangle calls for sides to ensure sharp corners.

        // Top
        try drawRectangle(ctx, opts, rx, ry, rw, thickness, thickness, true);
        // Bottom
        try drawRectangle(ctx, opts, rx, ry + rh - thickness, rw, thickness, thickness, true);
        // Left
        try drawRectangle(ctx, opts, rx, ry, thickness, rh, thickness, true);
        // Right
        try drawRectangle(ctx, opts, rx + rw - thickness, ry, thickness, rh, thickness, true);
    }
}

pub fn drawRoundedRectangle(ctx: PaintContext, opts: BrushOptions, x: c_int, y: c_int, w: c_int, h: c_int, radius: c_int, thickness: c_int, filled: bool) !void {
    const buf = ctx.buffer;

    // Normalize
    var rx = x;
    var ry = y;
    var rw = w;
    var rh = h;

    if (rw < 0) {
        rx += rw;
        rw = -rw;
    }
    if (rh < 0) {
        ry += rh;
        rh = -rh;
    }
    if (rw == 0 or rh == 0) return;

    const rect = c.GeglRectangle{ .x = rx, .y = ry, .width = rw, .height = rh };
    const format = c.babl_format("R'G'B'A u8");

    const stride = rw * 4;
    const size: usize = @intCast(rw * rh * 4);
    const allocator = std.heap.c_allocator;
    const pixels = try allocator.alloc(u8, size);
    defer allocator.free(pixels);

    c.gegl_buffer_get(buf, &rect, 1.0, format, pixels.ptr, stride, c.GEGL_ABYSS_NONE);

    const cx = @as(f64, @floatFromInt(rw)) / 2.0;
    const cy = @as(f64, @floatFromInt(rh)) / 2.0;
    const half_w = cx;
    const half_h = cy;
    const r_val = @min(@as(f64, @floatFromInt(radius)), @min(half_w, half_h));

    const thick_f = @as(f64, @floatFromInt(thickness));
    const fg = opts.color;

    var py: c_int = 0;
    while (py < rh) : (py += 1) {
        var px: c_int = 0;
        while (px < rw) : (px += 1) {
            const dx = @abs(@as(f64, @floatFromInt(px)) + 0.5 - cx);
            const dy = @abs(@as(f64, @floatFromInt(py)) + 0.5 - cy);

            const qx = dx - (half_w - r_val);
            const qy = dy - (half_h - r_val);

            const dist = @sqrt(@max(qx, 0.0) * @max(qx, 0.0) + @max(qy, 0.0) * @max(qy, 0.0)) + @min(@max(qx, qy), 0.0) - r_val;

            if (dist <= 0.0) {
                var draw = false;
                if (filled) {
                    draw = true;
                } else {
                    if (dist > -thick_f) {
                        draw = true;
                    }
                }

                if (draw) {
                    // Selection Check
                    if (isPointInSelection(ctx, rx + px, ry + py)) {
                         const idx = (@as(usize, @intCast(py)) * @as(usize, @intCast(rw)) + @as(usize, @intCast(px))) * 4;
                         @memcpy(pixels[idx..][0..4], &fg);
                    }
                }
            }
        }
    }

    c.gegl_buffer_set(buf, &rect, 0, format, pixels.ptr, stride);
}

pub fn drawEllipse(ctx: PaintContext, opts: BrushOptions, x: c_int, y: c_int, w: c_int, h: c_int, thickness: c_int, filled: bool) !void {
    const buf = ctx.buffer;

    var rx = x;
    var ry = y;
    var rw = w;
    var rh = h;

    if (rw < 0) {
        rx += rw;
        rw = -rw;
    }
    if (rh < 0) {
        ry += rh;
        rh = -rh;
    }
    if (rw == 0 or rh == 0) return;

    const rect = c.GeglRectangle{ .x = rx, .y = ry, .width = rw, .height = rh };
    const format = c.babl_format("R'G'B'A u8");

    const stride = rw * 4;
    const size: usize = @intCast(rw * rh * 4);
    const allocator = std.heap.c_allocator;
    const pixels = try allocator.alloc(u8, size);
    defer allocator.free(pixels);

    c.gegl_buffer_get(buf, &rect, 1.0, format, pixels.ptr, stride, c.GEGL_ABYSS_NONE);

    const cx = @as(f64, @floatFromInt(rw)) / 2.0;
    const cy = @as(f64, @floatFromInt(rh)) / 2.0;
    const radius_x = cx;
    const radius_y = cy;

    const inv_rx2 = 1.0 / (radius_x * radius_x);
    const inv_ry2 = 1.0 / (radius_y * radius_y);

    const inner_rx = @max(0.0, radius_x - @as(f64, @floatFromInt(thickness)));
    const inner_ry = @max(0.0, radius_y - @as(f64, @floatFromInt(thickness)));
    const inv_inner_rx2 = if (inner_rx > 0) 1.0 / (inner_rx * inner_rx) else 0.0;
    const inv_inner_ry2 = if (inner_ry > 0) 1.0 / (inner_ry * inner_ry) else 0.0;

    const fg = opts.color;

    var py: c_int = 0;
    while (py < rh) : (py += 1) {
        var px: c_int = 0;
        while (px < rw) : (px += 1) {
            const dx = @as(f64, @floatFromInt(px)) + 0.5 - cx;
            const dy = @as(f64, @floatFromInt(py)) + 0.5 - cy;

            const val_outer = (dx * dx) * inv_rx2 + (dy * dy) * inv_ry2;

            if (val_outer <= 1.0) {
                var draw = false;
                if (filled) {
                    draw = true;
                } else {
                    if (inner_rx <= 0 or inner_ry <= 0) {
                        draw = true;
                    } else {
                        const val_inner = (dx * dx) * inv_inner_rx2 + (dy * dy) * inv_inner_ry2;
                        if (val_inner > 1.0) {
                            draw = true;
                        }
                    }
                }

                if (draw) {
                    if (isPointInSelection(ctx, rx + px, ry + py)) {
                         const idx = (@as(usize, @intCast(py)) * @as(usize, @intCast(rw)) + @as(usize, @intCast(px))) * 4;
                         @memcpy(pixels[idx..][0..4], &fg);
                    }
                }
            }
        }
    }

    c.gegl_buffer_set(buf, &rect, 0, format, pixels.ptr, stride);
}

pub fn drawGradient(ctx: PaintContext, opts: BrushOptions, bg_color: [4]u8, x1: c_int, y1: c_int, x2: c_int, y2: c_int) !void {
    const buf = ctx.buffer;

    var bx: c_int = 0;
    var by: c_int = 0;
    var bw: c_int = ctx.canvas_width;
    var bh: c_int = ctx.canvas_height;

    if (ctx.selection) |sel| {
        bx = sel.x;
        by = sel.y;
        bw = sel.width;
        bh = sel.height;
    }

    if (bw <= 0 or bh <= 0) return;

    const allocator = std.heap.c_allocator;
    const size: usize = @intCast(bw * bh * 4);
    const pixels = try allocator.alloc(u8, size);
    defer allocator.free(pixels);

    const rect = c.GeglRectangle{ .x = bx, .y = by, .width = bw, .height = bh };
    const format = c.babl_format("R'G'B'A u8");
    const stride = bw * 4;

    c.gegl_buffer_get(buf, &rect, 1.0, format, pixels.ptr, stride, c.GEGL_ABYSS_NONE);

    const dx = @as(f64, @floatFromInt(x2 - x1));
    const dy = @as(f64, @floatFromInt(y2 - y1));
    const len_sq = dx * dx + dy * dy;
    const inv_len_sq = if (len_sq > 0.0) 1.0 / len_sq else 0.0;

    const start_x = @as(f64, @floatFromInt(x1));
    const start_y = @as(f64, @floatFromInt(y1));

    var py: c_int = 0;
    while (py < bh) : (py += 1) {
        var px: c_int = 0;
        while (px < bw) : (px += 1) {
            const global_x = bx + px;
            const global_y = by + py;

            if (!isPointInSelection(ctx, global_x, global_y)) continue;

            const pdx = @as(f64, @floatFromInt(global_x)) - start_x;
            const pdy = @as(f64, @floatFromInt(global_y)) - start_y;

            var t = (pdx * dx + pdy * dy) * inv_len_sq;
            if (t < 0.0) t = 0.0;
            if (t > 1.0) t = 1.0;

            const fg = opts.color;
            const bg = bg_color;

            const r = @as(f64, @floatFromInt(fg[0])) * (1.0 - t) + @as(f64, @floatFromInt(bg[0])) * t;
            const g = @as(f64, @floatFromInt(fg[1])) * (1.0 - t) + @as(f64, @floatFromInt(bg[1])) * t;
            const b = @as(f64, @floatFromInt(fg[2])) * (1.0 - t) + @as(f64, @floatFromInt(bg[2])) * t;
            const a = @as(f64, @floatFromInt(fg[3])) * (1.0 - t) + @as(f64, @floatFromInt(bg[3])) * t;

            const idx = (@as(usize, @intCast(py)) * @as(usize, @intCast(bw)) + @as(usize, @intCast(px))) * 4;
            pixels[idx] = @intFromFloat(r);
            pixels[idx + 1] = @intFromFloat(g);
            pixels[idx + 2] = @intFromFloat(b);
            pixels[idx + 3] = @intFromFloat(a);
        }
    }

    c.gegl_buffer_set(buf, &rect, 0, format, pixels.ptr, stride);
}
