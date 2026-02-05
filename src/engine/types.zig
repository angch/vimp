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

pub const ShapeType = enum {
    rectangle,
    ellipse,
    rounded_rectangle,
    line,
    curve,
    polygon,
};

pub const ShapePreview = struct {
    type: ShapeType,
    x: c_int,
    y: c_int,
    width: c_int,
    height: c_int,
    x2: c_int = 0,
    y2: c_int = 0,
    cx1: c_int = 0,
    cy1: c_int = 0,
    cx2: c_int = 0,
    cy2: c_int = 0,
    thickness: c_int,
    filled: bool,
    points: ?[]const Point = null,
    radius: c_int = 0,
};

pub const PreviewMode = enum {
    none,
    blur,
    motion_blur,
    pixelize,
    transform,
    unsharp_mask,
    noise_reduction,
    oilify,
    drop_shadow,
    red_eye_removal,
    waves,
    supernova,
    lighting,
    move_selection,
};

pub const TransformParams = struct {
    x: f64 = 0.0,
    y: f64 = 0.0,
    rotate: f64 = 0.0,
    scale_x: f64 = 1.0,
    scale_y: f64 = 1.0,
    skew_x: f64 = 0.0,
    skew_y: f64 = 0.0,
};
