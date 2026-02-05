pub const Point = struct {
    x: f64,
    y: f64,
};

pub const SelectionMode = enum {
    rectangle,
    ellipse,
    lasso,
};
