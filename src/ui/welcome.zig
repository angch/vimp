const std = @import("std");
const c = @import("../c.zig").c;
const RecentManager = @import("../recent.zig").RecentManager;

pub const WelcomeScreen = struct {
    pub const OpenFileCallback = *const fn (user_data: ?*anyopaque, path: [:0]const u8) void;

    allocator: std.mem.Allocator,
    widget: *c.GtkWidget,
    recent_manager: *RecentManager,
    recent_flow_box: *c.GtkWidget,
    open_callback: OpenFileCallback,
    open_callback_data: ?*anyopaque,

    pub fn create(
        allocator: std.mem.Allocator,
        recent_manager: *RecentManager,
        open_callback: OpenFileCallback,
        open_callback_data: ?*anyopaque,
    ) !*WelcomeScreen {
        const self = try allocator.create(WelcomeScreen);
        self.allocator = allocator;
        self.recent_manager = recent_manager;
        self.open_callback = open_callback;
        self.open_callback_data = open_callback_data;

        // Welcome Page
        const welcome_page = c.adw_status_page_new();
        c.adw_status_page_set_icon_name(@ptrCast(welcome_page), "camera-photo-symbolic");
        c.adw_status_page_set_title(@ptrCast(welcome_page), "Welcome to Vimp");
        c.adw_status_page_set_description(@ptrCast(welcome_page), "Create a new image or open an existing one to get started.");

        const welcome_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
        c.gtk_widget_set_halign(welcome_box, c.GTK_ALIGN_CENTER);

        const welcome_new_btn = c.gtk_button_new_with_mnemonic("_New Image");
        c.gtk_widget_add_css_class(welcome_new_btn, "pill");
        c.gtk_widget_add_css_class(welcome_new_btn, "suggested-action");
        c.gtk_actionable_set_action_name(@ptrCast(welcome_new_btn), "app.new");
        c.gtk_box_append(@ptrCast(welcome_box), welcome_new_btn);

        const welcome_open_btn = c.gtk_button_new_with_mnemonic("_Open Image");
        c.gtk_widget_add_css_class(welcome_open_btn, "pill");
        c.gtk_actionable_set_action_name(@ptrCast(welcome_open_btn), "app.open");
        c.gtk_box_append(@ptrCast(welcome_box), welcome_open_btn);

        const welcome_open_loc_btn = c.gtk_button_new_with_mnemonic("Open _Location");
        c.gtk_widget_add_css_class(welcome_open_loc_btn, "pill");
        c.gtk_actionable_set_action_name(@ptrCast(welcome_open_loc_btn), "app.open-location");
        c.gtk_box_append(@ptrCast(welcome_box), welcome_open_loc_btn);

        // Recent Label
        const recent_label = c.gtk_label_new("Recent Files");
        c.gtk_widget_set_margin_top(recent_label, 20);
        c.gtk_widget_add_css_class(recent_label, "dim-label");
        c.gtk_box_append(@ptrCast(welcome_box), recent_label);

        // Recent List
        const recent_scrolled = c.gtk_scrolled_window_new();
        c.gtk_widget_set_vexpand(recent_scrolled, 1);
        c.gtk_widget_set_size_request(recent_scrolled, 400, 250);

        const recent_list = c.gtk_flow_box_new();
        c.gtk_flow_box_set_selection_mode(@ptrCast(recent_list), c.GTK_SELECTION_NONE);
        c.gtk_flow_box_set_max_children_per_line(@ptrCast(recent_list), 6);
        c.gtk_flow_box_set_min_children_per_line(@ptrCast(recent_list), 3);
        c.gtk_flow_box_set_row_spacing(@ptrCast(recent_list), 20);
        c.gtk_flow_box_set_column_spacing(@ptrCast(recent_list), 20);
        c.gtk_widget_set_valign(recent_list, c.GTK_ALIGN_START);

        c.gtk_scrolled_window_set_child(@ptrCast(recent_scrolled), recent_list);
        c.gtk_box_append(@ptrCast(welcome_box), recent_scrolled);

        self.recent_flow_box = recent_list;
        self.widget = welcome_page; // The AdwStatusPage is the root widget for this component

        c.adw_status_page_set_child(@ptrCast(welcome_page), welcome_box);

        // Connect signal
        _ = c.g_signal_connect_data(recent_list, "child-activated", @ptrCast(&on_child_activated), self, null, 0);

        self.refresh();

        return self;
    }

    fn on_child_activated(_: *c.GtkFlowBox, child: *c.GtkFlowBoxChild, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
        const self: *WelcomeScreen = @ptrCast(@alignCast(user_data));
        const widget = c.gtk_flow_box_child_get_child(child);
        const data = c.g_object_get_data(@ptrCast(widget), "file-path");
        if (data) |p| {
            const path: [*c]const u8 = @ptrCast(p);
            const span = std.mem.span(path);

            // Invoke callback
            self.open_callback(self.open_callback_data, span);
        }
    }

    pub fn refresh(self: *WelcomeScreen) void {
        const box = self.recent_flow_box;

        // Clear
        var child = c.gtk_widget_get_first_child(@ptrCast(box));
        while (child != null) {
            const next = c.gtk_widget_get_next_sibling(child);
            c.gtk_flow_box_remove(@ptrCast(box), child);
            child = next;
        }

        // Add recent files
        if (self.recent_manager.paths.items.len == 0) {
            const label = c.gtk_label_new("(No recent files)");
            c.gtk_widget_add_css_class(label, "dim-label");
            c.gtk_widget_set_margin_top(label, 20);
            c.gtk_widget_set_margin_bottom(label, 20);
            c.gtk_flow_box_append(@ptrCast(box), label);
        } else {
            // Iterate safely
            for (self.recent_manager.paths.items) |path| {
                const row_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 6);
                c.gtk_widget_set_halign(row_box, c.GTK_ALIGN_CENTER);
                c.gtk_widget_set_margin_top(row_box, 12);
                c.gtk_widget_set_margin_bottom(row_box, 12);
                c.gtk_widget_set_margin_start(row_box, 12);
                c.gtk_widget_set_margin_end(row_box, 12);

                var icon_widget: *c.GtkWidget = undefined;
                var has_thumb = false;

                if (self.recent_manager.getThumbnailPath(path)) |tp| {
                    if (std.fs.openFileAbsolute(tp, .{})) |f| {
                        f.close();
                        const tp_z = std.fmt.allocPrintSentinel(std.heap.c_allocator, "{s}", .{tp}, 0) catch null;
                        if (tp_z) |z| {
                            icon_widget = c.gtk_image_new_from_file(z);
                            c.gtk_image_set_pixel_size(@ptrCast(icon_widget), 128);
                            std.heap.c_allocator.free(z);
                            has_thumb = true;
                        }
                    } else |_| {}
                    std.heap.c_allocator.free(tp);
                } else |_| {}

                if (!has_thumb) {
                    icon_widget = c.gtk_image_new_from_icon_name("image-x-generic-symbolic");
                    c.gtk_image_set_pixel_size(@ptrCast(icon_widget), 128);
                }
                c.gtk_box_append(@ptrCast(row_box), icon_widget);

                const basename = std.fs.path.basename(path);
                var buf: [256]u8 = undefined;
                const label_text = std.fmt.bufPrintZ(&buf, "{s}", .{basename}) catch "File";

                const label = c.gtk_label_new(label_text.ptr);
                c.gtk_label_set_wrap(@ptrCast(label), 1);
                c.gtk_label_set_max_width_chars(@ptrCast(label), 12);
                c.gtk_label_set_ellipsize(@ptrCast(label), c.PANGO_ELLIPSIZE_END);
                c.gtk_label_set_lines(@ptrCast(label), 2);
                c.gtk_label_set_justify(@ptrCast(label), c.GTK_JUSTIFY_CENTER);

                c.gtk_box_append(@ptrCast(row_box), label);

                // Show full path as tooltip
                var path_buf: [1024]u8 = undefined;
                const path_z = std.fmt.bufPrintZ(&path_buf, "{s}", .{path}) catch "File";
                c.gtk_widget_set_tooltip_text(row_box, path_z.ptr);

                c.gtk_flow_box_append(@ptrCast(box), row_box);

                // Attach data
                const path_dup = std.fmt.allocPrintSentinel(std.heap.c_allocator, "{s}", .{path}, 0) catch continue;
                c.g_object_set_data_full(@ptrCast(row_box), "file-path", @ptrCast(path_dup), @ptrCast(&c.g_free));
            }
        }
    }
};
