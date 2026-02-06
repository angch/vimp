const std = @import("std");
const c = @import("../c.zig").c;

fn sidebar_toggled(
    _: *c.GtkButton,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    const sidebar_widget: *c.GtkWidget = @ptrCast(@alignCast(user_data));
    const is_visible = c.gtk_widget_get_visible(sidebar_widget);
    c.gtk_widget_set_visible(sidebar_widget, if (is_visible != 0) 0 else 1);
}

pub const Header = struct {
    widget: *c.GtkWidget,
    apply_btn: *c.GtkWidget,
    discard_btn: *c.GtkWidget,
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator, sidebar_widget: *c.GtkWidget) !*Header {
        const self = try allocator.create(Header);
        self.allocator = allocator;

        const header_bar = c.adw_header_bar_new();
        self.widget = @ptrCast(header_bar);

        // Sidebar Toggle Button
        const sidebar_btn = c.gtk_button_new_from_icon_name("sidebar-show-symbolic");
        c.gtk_widget_set_tooltip_text(sidebar_btn, "Toggle Sidebar");
        c.adw_header_bar_pack_start(@ptrCast(header_bar), sidebar_btn);
        _ = c.g_signal_connect_data(sidebar_btn, "clicked", @ptrCast(&sidebar_toggled), sidebar_widget, null, 0);

        // Primary Actions (Start)
        const new_btn = c.gtk_button_new_from_icon_name("document-new-symbolic");
        c.gtk_actionable_set_action_name(@ptrCast(new_btn), "app.new");
        c.gtk_widget_set_tooltip_text(new_btn, "New Image (Ctrl+N)");
        c.adw_header_bar_pack_start(@ptrCast(header_bar), new_btn);

        const open_btn = c.gtk_button_new_from_icon_name("document-open-symbolic");
        c.gtk_actionable_set_action_name(@ptrCast(open_btn), "app.open");
        c.gtk_widget_set_tooltip_text(open_btn, "Open Image (Ctrl+O)");
        c.adw_header_bar_pack_start(@ptrCast(header_bar), open_btn);

        const save_btn = c.gtk_button_new_from_icon_name("document-save-symbolic");
        c.gtk_actionable_set_action_name(@ptrCast(save_btn), "app.save");
        c.gtk_widget_set_tooltip_text(save_btn, "Save Image (Ctrl+S)");
        c.adw_header_bar_pack_start(@ptrCast(header_bar), save_btn);

        // Undo/Redo
        const undo_btn = c.gtk_button_new_from_icon_name("edit-undo-symbolic");
        c.gtk_actionable_set_action_name(@ptrCast(undo_btn), "app.undo");
        c.gtk_widget_set_tooltip_text(undo_btn, "Undo (Ctrl+Z)");
        c.adw_header_bar_pack_start(@ptrCast(header_bar), undo_btn);

        const redo_btn = c.gtk_button_new_from_icon_name("edit-redo-symbolic");
        c.gtk_actionable_set_action_name(@ptrCast(redo_btn), "app.redo");
        c.gtk_widget_set_tooltip_text(redo_btn, "Redo (Ctrl+Y)");
        c.adw_header_bar_pack_start(@ptrCast(header_bar), redo_btn);

        // Image Menu
        const image_menu = c.g_menu_new();
        c.g_menu_append(image_menu, "_Canvas Size...", "app.canvas-size");
        c.g_menu_append(image_menu, "_Invert Colors", "app.invert-colors");
        c.g_menu_append(image_menu, "Cl_ear Image", "app.clear-image");
        c.g_menu_append(image_menu, "Flip _Horizontal", "app.flip-horizontal");
        c.g_menu_append(image_menu, "Flip _Vertical", "app.flip-vertical");
        c.g_menu_append(image_menu, "Rotate _90° CW", "app.rotate-90");
        c.g_menu_append(image_menu, "Rotate _180°", "app.rotate-180");
        c.g_menu_append(image_menu, "Rotate _270° CW", "app.rotate-270");
        c.g_menu_append(image_menu, "_Stretch and Skew...", "app.stretch");

        const image_btn = c.gtk_menu_button_new();
        c.gtk_menu_button_set_label(@ptrCast(image_btn), "_Image");
        c.gtk_menu_button_set_use_underline(@ptrCast(image_btn), 1);
        c.gtk_menu_button_set_menu_model(@ptrCast(image_btn), @ptrCast(@alignCast(image_menu)));
        c.gtk_widget_set_tooltip_text(image_btn, "Image Operations");
        c.adw_header_bar_pack_start(@ptrCast(header_bar), image_btn);

        // Filters Menu
        const filters_menu = c.g_menu_new();
        c.g_menu_append(filters_menu, "Blur (_5px)", "app.blur-small");
        c.g_menu_append(filters_menu, "Blur (1_0px)", "app.blur-medium");
        c.g_menu_append(filters_menu, "Blur (_20px)", "app.blur-large");
        c.g_menu_append(filters_menu, "_Pixelize...", "app.pixelize");
        c.g_menu_append(filters_menu, "_Motion Blur...", "app.motion-blur");
        c.g_menu_append(filters_menu, "_Unsharp Mask...", "app.unsharp-mask");
        c.g_menu_append(filters_menu, "_Noise Reduction...", "app.noise-reduction");
        c.g_menu_append(filters_menu, "_Oilify...", "app.oilify");
        c.g_menu_append(filters_menu, "_Drop Shadow...", "app.drop-shadow");
        c.g_menu_append(filters_menu, "_Red Eye Removal...", "app.red-eye-removal");
        c.g_menu_append(filters_menu, "_Waves...", "app.waves");
        c.g_menu_append(filters_menu, "_Supernova...", "app.supernova");
        c.g_menu_append(filters_menu, "_Lighting Effects...", "app.lighting-effects");
        c.g_menu_append(filters_menu, "Split _View", "app.split-view");

        const filters_btn = c.gtk_menu_button_new();
        c.gtk_menu_button_set_label(@ptrCast(filters_btn), "_Filters");
        c.gtk_menu_button_set_use_underline(@ptrCast(filters_btn), 1);
        c.gtk_menu_button_set_menu_model(@ptrCast(filters_btn), @ptrCast(@alignCast(filters_menu)));
        c.gtk_widget_set_tooltip_text(filters_btn, "Image Filters");
        c.adw_header_bar_pack_start(@ptrCast(header_bar), filters_btn);

        // View Menu
        const view_menu = c.g_menu_new();
        c.g_menu_append(view_menu, "View _Bitmap", "app.view-bitmap");
        c.g_menu_append(view_menu, "_Overview (Thumbnail)", "app.view-thumbnail");
        c.g_menu_append(view_menu, "Show _Grid", "app.show-grid");

        const view_btn = c.gtk_menu_button_new();
        c.gtk_menu_button_set_label(@ptrCast(view_btn), "_View");
        c.gtk_menu_button_set_use_underline(@ptrCast(view_btn), 1);
        c.gtk_menu_button_set_menu_model(@ptrCast(view_btn), @ptrCast(@alignCast(view_menu)));
        c.gtk_widget_set_tooltip_text(view_btn, "View Options");
        c.adw_header_bar_pack_start(@ptrCast(header_bar), view_btn);

        // Apply Preview Button (Hidden by default, shown when preview_mode != none)
        const apply_btn = c.gtk_button_new_from_icon_name("object-select-symbolic");
        c.gtk_actionable_set_action_name(@ptrCast(apply_btn), "app.apply-preview");
        c.gtk_widget_set_tooltip_text(apply_btn, "Apply Filter");
        c.gtk_widget_set_visible(apply_btn, 0); // Hidden initially
        self.apply_btn = apply_btn;
        c.adw_header_bar_pack_start(@ptrCast(header_bar), apply_btn);

        // Discard Preview Button
        const discard_btn = c.gtk_button_new_from_icon_name("process-stop-symbolic");
        c.gtk_actionable_set_action_name(@ptrCast(discard_btn), "app.discard-preview");
        c.gtk_widget_set_tooltip_text(discard_btn, "Discard Filter");
        c.gtk_widget_set_visible(discard_btn, 0); // Hidden initially
        self.discard_btn = discard_btn;
        c.adw_header_bar_pack_start(@ptrCast(header_bar), discard_btn);

        // Hamburger Menu (End)
        const menu = c.g_menu_new();
        c.g_menu_append(menu, "_Command Palette...", "app.command-palette");
        c.g_menu_append(menu, "_Open Location...", "app.open-location");
        c.g_menu_append(menu, "_Inspector", "app.inspector");
        c.g_menu_append(menu, "_About Vimp", "app.about");
        c.g_menu_append(menu, "_Quit", "app.quit");

        const menu_btn = c.gtk_menu_button_new();
        c.gtk_menu_button_set_icon_name(@ptrCast(menu_btn), "open-menu-symbolic");
        c.gtk_menu_button_set_menu_model(@ptrCast(menu_btn), @ptrCast(@alignCast(menu)));
        c.gtk_widget_set_tooltip_text(menu_btn, "Menu");

        c.adw_header_bar_pack_end(@ptrCast(header_bar), menu_btn);

        return self;
    }
};
