const std = @import("std");
const c = @import("../c.zig").c;

pub fn renderText(
    text: []const u8,
    x: i32,
    y: i32,
    size: i32,
    canvas_width: c_int,
    canvas_height: c_int,
    fg_color: [4]u8,
    bg_color: [4]u8,
    is_opaque: bool,
) !*c.GeglBuffer {
    const w = canvas_width;
    const h = canvas_height;
    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, w, h);
    if (c.cairo_surface_status(surface) != c.CAIRO_STATUS_SUCCESS) return error.CairoFailed;
    defer c.cairo_surface_destroy(surface);

    const cr = c.cairo_create(surface);
    defer c.cairo_destroy(cr);

    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_CLEAR);
    c.cairo_paint(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    const layout = c.pango_cairo_create_layout(cr);
    defer c.g_object_unref(layout);

    c.pango_layout_set_text(layout, text.ptr, @intCast(text.len));

    var desc_str: [64]u8 = undefined;
    const desc_z = std.fmt.bufPrintZ(&desc_str, "Sans {d}px", .{size}) catch "Sans 12px";

    const desc = c.pango_font_description_from_string(desc_z.ptr);
    defer c.pango_font_description_free(desc);
    c.pango_layout_set_font_description(layout, desc);

    if (is_opaque) {
        var ink_rect: c.PangoRectangle = undefined;
        var logical_rect: c.PangoRectangle = undefined;
        c.pango_layout_get_pixel_extents(layout, &ink_rect, &logical_rect);

        const bg = bg_color;
        c.cairo_set_source_rgba(cr, @as(f64, @floatFromInt(bg[0])) / 255.0, @as(f64, @floatFromInt(bg[1])) / 255.0, @as(f64, @floatFromInt(bg[2])) / 255.0, @as(f64, @floatFromInt(bg[3])) / 255.0);

        c.cairo_rectangle(cr, @floatFromInt(x + logical_rect.x), @floatFromInt(y + logical_rect.y), @floatFromInt(logical_rect.width), @floatFromInt(logical_rect.height));
        c.cairo_fill(cr);
    }

    const fg = fg_color;
    c.cairo_set_source_rgba(cr, @as(f64, @floatFromInt(fg[0])) / 255.0, @as(f64, @floatFromInt(fg[1])) / 255.0, @as(f64, @floatFromInt(fg[2])) / 255.0, @as(f64, @floatFromInt(fg[3])) / 255.0);

    c.cairo_move_to(cr, @floatFromInt(x), @floatFromInt(y));
    c.pango_cairo_show_layout(cr, layout);

    const bbox = c.GeglRectangle{ .x = 0, .y = 0, .width = w, .height = h };
    const src_format = c.babl_format("cairo-ARGB32");
    const layer_format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(&bbox, layer_format);
    if (new_buffer == null) return error.GeglBufferFailed;

    c.cairo_surface_flush(surface);
    const data = c.cairo_image_surface_get_data(surface);
    const stride = c.cairo_image_surface_get_stride(surface);

    c.gegl_buffer_set(new_buffer.?, &bbox, 0, src_format, data, stride);

    return new_buffer.?;
}
