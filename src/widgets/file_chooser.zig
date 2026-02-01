const std = @import("std");
const c = @import("../c.zig").c;

pub const OpenCallback = *const fn (user_data: ?*anyopaque, path: ?[:0]const u8) void;

const DialogContext = struct {
    callback: OpenCallback,
    user_data: ?*anyopaque,
    as_layers: bool,
    chooser_widget: *c.GtkWidget,
};

fn update_preview_cb(chooser: *c.GtkFileChooser, user_data: ?*anyopaque) callconv(.c) void {
    const preview_picture: *c.GtkPicture = @ptrCast(@alignCast(user_data));
    const file = c.gtk_file_chooser_get_file(chooser);

    if (file) |f| {
        const path = c.g_file_get_path(f);
        if (path) |p| {
            // GtkPicture handles scaling and aspect ratio for content images.
            c.gtk_picture_set_filename(preview_picture, p);
            c.g_free(p);
        } else {
            // Clear
            c.gtk_picture_set_paintable(preview_picture, null);
        }
        c.g_object_unref(f);
    } else {
        c.gtk_picture_set_paintable(preview_picture, null);
    }
}

fn response_cb(dialog: *c.GtkDialog, response_id: c_int, user_data: ?*anyopaque) callconv(.c) void {
    const ctx: *DialogContext = @ptrCast(@alignCast(user_data));

    if (response_id == c.GTK_RESPONSE_ACCEPT) {
        const chooser: *c.GtkFileChooser = @ptrCast(ctx.chooser_widget);
        const file = c.gtk_file_chooser_get_file(chooser);
        if (file) |f| {
            const path = c.g_file_get_path(f);
            if (path) |p| {
                const span = std.mem.span(p);
                ctx.callback(ctx.user_data, span);
                c.g_free(p);
            } else {
                ctx.callback(ctx.user_data, null);
            }
            c.g_object_unref(f);
        } else {
            ctx.callback(ctx.user_data, null);
        }
    } else {
        // Cancelled or closed
        ctx.callback(ctx.user_data, null);
    }

    // Cleanup
    std.heap.c_allocator.destroy(ctx);
    c.gtk_window_destroy(@ptrCast(dialog));
}

pub fn showOpenDialog(
    parent: ?*c.GtkWindow,
    title: [:0]const u8,
    as_layers: bool,
    callback: OpenCallback,
    user_data: ?*anyopaque,
) !void {
    const dialog = c.gtk_dialog_new_with_buttons(
        title.ptr,
        parent,
        c.GTK_DIALOG_MODAL | c.GTK_DIALOG_DESTROY_WITH_PARENT,
        "_Cancel", c.GTK_RESPONSE_CANCEL,
        "_Open", c.GTK_RESPONSE_ACCEPT,
        @as(?*anyopaque, null)
    );

    c.gtk_window_set_default_size(@ptrCast(dialog), 900, 600);

    const content_area = c.gtk_dialog_get_content_area(@ptrCast(dialog));

    // Main HBox
    const hbox = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 10);
    c.gtk_widget_set_margin_top(hbox, 10);
    c.gtk_widget_set_margin_bottom(hbox, 10);
    c.gtk_widget_set_margin_start(hbox, 10);
    c.gtk_widget_set_margin_end(hbox, 10);
    c.gtk_box_append(@ptrCast(content_area), hbox);

    // File Chooser Widget
    const chooser_widget = c.gtk_file_chooser_widget_new(c.GTK_FILE_CHOOSER_ACTION_OPEN);
    c.gtk_widget_set_hexpand(chooser_widget, 1);
    c.gtk_widget_set_vexpand(chooser_widget, 1);
    c.gtk_box_append(@ptrCast(hbox), chooser_widget);

    // Preview Column (VBox)
    const preview_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_size_request(preview_box, 300, -1);
    c.gtk_box_append(@ptrCast(hbox), preview_box);

    const preview_label = c.gtk_label_new("Preview");
    c.gtk_widget_add_css_class(preview_label, "heading");
    c.gtk_box_append(@ptrCast(preview_box), preview_label);

    const preview_frame = c.gtk_frame_new(null);
    c.gtk_widget_set_vexpand(preview_frame, 0); // Don't expand infinitely
    c.gtk_box_append(@ptrCast(preview_box), preview_frame);

    // Use GtkPicture for proper content scaling
    const preview = c.gtk_picture_new();
    c.gtk_widget_set_size_request(preview, 280, 280);
    c.gtk_picture_set_can_shrink(@ptrCast(preview), 1);
    c.gtk_picture_set_content_fit(@ptrCast(preview), c.GTK_CONTENT_FIT_CONTAIN);

    c.gtk_frame_set_child(@ptrCast(preview_frame), preview);

    // Filters (Apply to chooser_widget)
    const filter_imgs = c.gtk_file_filter_new();
    c.gtk_file_filter_set_name(filter_imgs, "All Supported Images");
    c.gtk_file_filter_add_pattern(filter_imgs, "*.png");
    c.gtk_file_filter_add_pattern(filter_imgs, "*.jpg");
    c.gtk_file_filter_add_pattern(filter_imgs, "*.jpeg");
    c.gtk_file_filter_add_pattern(filter_imgs, "*.webp");
    c.gtk_file_filter_add_pattern(filter_imgs, "*.gif");
    c.gtk_file_filter_add_pattern(filter_imgs, "*.tif");
    c.gtk_file_filter_add_pattern(filter_imgs, "*.tiff");
    c.gtk_file_filter_add_pattern(filter_imgs, "*.bmp");
    c.gtk_file_filter_add_pattern(filter_imgs, "*.avif");
    c.gtk_file_filter_add_pattern(filter_imgs, "*.ico");
    c.gtk_file_filter_add_pattern(filter_imgs, "*.tga");
    c.gtk_file_filter_add_pattern(filter_imgs, "*.xcf");
    c.gtk_file_chooser_add_filter(@ptrCast(chooser_widget), filter_imgs);

    const filter_png = c.gtk_file_filter_new();
    c.gtk_file_filter_set_name(filter_png, "PNG Image");
    c.gtk_file_filter_add_pattern(filter_png, "*.png");
    c.gtk_file_chooser_add_filter(@ptrCast(chooser_widget), filter_png);

    const filter_jpg = c.gtk_file_filter_new();
    c.gtk_file_filter_set_name(filter_jpg, "JPEG Image");
    c.gtk_file_filter_add_pattern(filter_jpg, "*.jpg");
    c.gtk_file_filter_add_pattern(filter_jpg, "*.jpeg");
    c.gtk_file_chooser_add_filter(@ptrCast(chooser_widget), filter_jpg);

    const filter_webp = c.gtk_file_filter_new();
    c.gtk_file_filter_set_name(filter_webp, "WebP Image");
    c.gtk_file_filter_add_pattern(filter_webp, "*.webp");
    c.gtk_file_chooser_add_filter(@ptrCast(chooser_widget), filter_webp);

    const filter_xcf = c.gtk_file_filter_new();
    c.gtk_file_filter_set_name(filter_xcf, "GIMP XCF Image");
    c.gtk_file_filter_add_pattern(filter_xcf, "*.xcf");
    c.gtk_file_chooser_add_filter(@ptrCast(chooser_widget), filter_xcf);

    const filter_all = c.gtk_file_filter_new();
    c.gtk_file_filter_set_name(filter_all, "All Files");
    c.gtk_file_filter_add_pattern(filter_all, "*");
    c.gtk_file_chooser_add_filter(@ptrCast(chooser_widget), filter_all);

    _ = c.g_signal_connect_data(chooser_widget, "selection-changed", @ptrCast(&update_preview_cb), preview, null, 0);

    // Context
    const ctx = try std.heap.c_allocator.create(DialogContext);
    ctx.* = .{
        .callback = callback,
        .user_data = user_data,
        .as_layers = as_layers,
        .chooser_widget = chooser_widget,
    };

    _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&response_cb), ctx, null, 0);

    c.gtk_window_present(@ptrCast(dialog));
}
