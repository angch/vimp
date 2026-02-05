const std = @import("std");
const c = @import("../c.zig").c;
const TypesMod = @import("types.zig");

pub const Point = TypesMod.Point;
pub const SelectionMode = TypesMod.SelectionMode;

pub const Selection = struct {
    rect: ?c.GeglRectangle = null,
    mode: SelectionMode = .rectangle,
    points: std.ArrayList(Point),
    transparent: bool = false,

    // Ellipse cache
    cx: f64 = 0,
    cy: f64 = 0,
    inv_rx_sq: f64 = 0,
    inv_ry_sq: f64 = 0,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Selection {
        return .{
            .points = std.ArrayList(Point){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Selection) void {
        self.points.deinit(self.allocator);
    }

    pub fn clear(self: *Selection) void {
        self.rect = null;
        self.points.clearRetainingCapacity();
    }

    pub fn setRect(self: *Selection, x: c_int, y: c_int, w: c_int, h: c_int) void {
        self.rect = c.GeglRectangle{ .x = x, .y = y, .width = w, .height = h };

        const width_f = @as(f64, @floatFromInt(w));
        const height_f = @as(f64, @floatFromInt(h));
        const rx = width_f / 2.0;
        const ry = height_f / 2.0;
        self.cx = @as(f64, @floatFromInt(x)) + rx;
        self.cy = @as(f64, @floatFromInt(y)) + ry;

        if (rx > 0.0) {
            self.inv_rx_sq = 1.0 / (rx * rx);
        } else {
            self.inv_rx_sq = 0.0;
        }

        if (ry > 0.0) {
            self.inv_ry_sq = 1.0 / (ry * ry);
        } else {
            self.inv_ry_sq = 0.0;
        }
    }

    pub fn setLasso(self: *Selection, points: []const Point) void {
        self.points.clearRetainingCapacity();
        self.points.appendSlice(self.allocator, points) catch {};
        self.mode = .lasso;

        if (points.len > 0) {
            var min_x: f64 = points[0].x;
            var max_x: f64 = points[0].x;
            var min_y: f64 = points[0].y;
            var max_y: f64 = points[0].y;

            for (points) |p| {
                if (p.x < min_x) min_x = p.x;
                if (p.x > max_x) max_x = p.x;
                if (p.y < min_y) min_y = p.y;
                if (p.y > max_y) max_y = p.y;
            }

            const x = @as(c_int, @intFromFloat(min_x));
            const y = @as(c_int, @intFromFloat(min_y));
            const w = @as(c_int, @intFromFloat(max_x - min_x + 1.0));
            const h = @as(c_int, @intFromFloat(max_y - min_y + 1.0));

            self.setRect(x, y, w, h);
        } else {
            self.clear();
        }
    }

    pub fn isPointIn(self: *const Selection, x: c_int, y: c_int) bool {
        if (self.rect) |sel| {
            if (x < sel.x or x >= sel.x + sel.width or y < sel.y or y >= sel.y + sel.height) return false;

            if (self.mode == .ellipse) {
                const dx_p = @as(f64, @floatFromInt(x)) + 0.5 - self.cx;
                const dy_p = @as(f64, @floatFromInt(y)) + 0.5 - self.cy;

                if ((dx_p * dx_p) * self.inv_rx_sq + (dy_p * dy_p) * self.inv_ry_sq > 1.0) return false;
            } else if (self.mode == .lasso) {
                // Ray Casting Algorithm (Even-Odd Rule)
                const px = @as(f64, @floatFromInt(x)) + 0.5;
                const py = @as(f64, @floatFromInt(y)) + 0.5;
                var inside = false;
                const pt_list = self.points.items;
                if (pt_list.len == 0) return false;

                var j = pt_list.len - 1;
                for (pt_list, 0..) |pi, i| {
                    const pj = pt_list[j];
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
        return true; // No selection => entire canvas selected
    }

    pub fn setMode(self: *Selection, mode: SelectionMode) void {
        self.mode = mode;
    }

    pub fn setTransparent(self: *Selection, transparent: bool) void {
        self.transparent = transparent;
    }
};

test "Selection rect" {
    var sel = Selection.init(std.testing.allocator);
    defer sel.deinit();

    sel.setRect(10, 10, 10, 10);
    sel.setMode(.rectangle);

    try std.testing.expect(sel.isPointIn(15, 15));
    try std.testing.expect(!sel.isPointIn(5, 5));
    try std.testing.expect(!sel.isPointIn(25, 25));
}

test "Selection ellipse" {
    var sel = Selection.init(std.testing.allocator);
    defer sel.deinit();

    sel.setRect(10, 10, 10, 10);
    sel.setMode(.ellipse);

    // Center (15, 15) is inside
    try std.testing.expect(sel.isPointIn(15, 15));
    // Corner (10, 10) is outside
    try std.testing.expect(!sel.isPointIn(10, 10));
}

test "Selection lasso" {
    var sel = Selection.init(std.testing.allocator);
    defer sel.deinit();

    // Triangle
    var points = [_]Point{
        .{ .x = 10, .y = 10 },
        .{ .x = 20, .y = 10 },
        .{ .x = 10, .y = 20 },
    };
    sel.setLasso(&points);

    // BBox should be 10, 10, 11, 11 (Wait, width/height is max-min+1)
    // 20-10+1 = 11.
    if (sel.rect) |r| {
        try std.testing.expectEqual(r.x, 10);
        try std.testing.expectEqual(r.width, 11);
    }

    // Check mode
    try std.testing.expectEqual(sel.mode, .lasso);
    try std.testing.expectEqual(sel.points.items.len, 3);

    // Inside triangle (12, 12)
    try std.testing.expect(sel.isPointIn(12, 12));

    // Outside triangle
    try std.testing.expect(!sel.isPointIn(18, 18));
}
