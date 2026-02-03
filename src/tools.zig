const std = @import("std");

pub const Tool = enum {
    brush,
    pencil,
    airbrush,
    eraser,
    bucket_fill,
    rect_select,
    ellipse_select,
    rect_shape,
    ellipse_shape,
    rounded_rect_shape,
    unified_transform,
    color_picker,
    gradient,
    line,
    curve,
    polygon,
    lasso,
    text,
};
