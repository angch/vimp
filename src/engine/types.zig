const c = @import("../c.zig").c;

pub const Point = struct {
    x: f64,
    y: f64,
};

pub const SelectionMode = enum {
    rectangle,
    ellipse,
    lasso,
};

pub const PaintMode = enum {
    paint,
    erase,
    fill,
    airbrush,
};

pub const BrushType = enum {
    square,
    circle,
};

pub const PaintContext = struct {
    buffer: *c.GeglBuffer,
    canvas_width: c_int,
    canvas_height: c_int,
    selection: ?c.GeglRectangle,
    selection_mode: SelectionMode,
    selection_points: []const Point,
    sel_cx: f64,
    sel_cy: f64,
    sel_inv_rx_sq: f64,
    sel_inv_ry_sq: f64,
};

pub const BrushOptions = struct {
    size: c_int,
    opacity: f64,
    type: BrushType,
    mode: PaintMode,
    color: [4]u8,
    pressure: f64 = 1.0,
};
