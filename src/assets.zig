const std = @import("std");
const c = @import("c.zig").c;

// PNGs
pub const airbrush_png = @embedFile("assets/airbrush.png");
pub const brush_png = @embedFile("assets/brush.png");
pub const bucket_png = @embedFile("assets/bucket.png");
pub const eraser_png = @embedFile("assets/eraser.png");
pub const pencil_png = @embedFile("assets/pencil.png");

// SVGs
pub const color_picker_svg = @embedFile("assets/color-picker.svg");
pub const curve_svg = @embedFile("assets/curve.svg");
pub const ellipse_select_svg = @embedFile("assets/ellipse-select.svg");
pub const ellipse_shape_svg = @embedFile("assets/ellipse-shape.svg");
pub const gradient_svg = @embedFile("assets/gradient.svg");
pub const lasso_select_svg = @embedFile("assets/lasso-select.svg");
pub const line_svg = @embedFile("assets/line.svg");
pub const polygon_svg = @embedFile("assets/polygon.svg");
pub const rect_select_svg = @embedFile("assets/rect-select.svg");
pub const rect_shape_svg = @embedFile("assets/rect-shape.svg");
pub const rounded_rect_shape_svg = @embedFile("assets/rounded-rect-shape.svg");
pub const text_svg = @embedFile("assets/text.svg");
pub const transform_svg = @embedFile("assets/transform.svg");

pub fn getTexture(data: []const u8) ?*c.GdkTexture {
    const bytes = c.g_bytes_new_static(data.ptr, data.len);
    if (bytes == null) return null;
    defer c.g_bytes_unref(bytes);

    const stream = c.g_memory_input_stream_new_from_data(data.ptr, @intCast(data.len), null);
    if (stream == null) return null;
    defer c.g_object_unref(stream);

    var err: ?*c.GError = null;
    const pixbuf = c.gdk_pixbuf_new_from_stream(@ptrCast(stream), null, &err);
    if (pixbuf == null) {
        if (err) |e| {
            std.debug.print("Failed to create pixbuf from stream: {s}\n", .{e.*.message});
            c.g_error_free(e);
        }
        return null;
    }
    defer c.g_object_unref(pixbuf);

    return c.gdk_texture_new_for_pixbuf(pixbuf);
}

pub fn getIconWidget(data: []const u8, size: i32) *c.GtkWidget {
    const texture = getTexture(data);
    if (texture) |t| {
        // Transfer texture ownership to GtkImage (which adds its own ref).
        // We unref our local reference to avoid leaking.
        const img = c.gtk_image_new_from_paintable(@ptrCast(t));
        c.g_object_unref(t);
        c.gtk_widget_set_size_request(img, size, size);
        return img;
    }
    // Fallback
    const img = c.gtk_image_new_from_icon_name("image-missing-symbolic");
    c.gtk_widget_set_size_request(img, size, size);
    return img;
}
