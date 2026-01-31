const std = @import("std");
const c = @import("../c.zig").c;

// Check pointer size to ensure we are on 64-bit as assumed for now, or use c.long/c.int correctly
comptime {
    if (@sizeOf(usize) != 8) {
        @compileError("This code currently assumes 64-bit pointers for layout verification.");
    }
}

// Basic GObject/GIMP types helpers
pub const VimpContext = opaque {};
pub const VimpDisplay = opaque {};
pub const VimpImage = opaque {};
pub const VimpToolInfo = opaque {};
pub const VimpToolControl = opaque {};
pub const GList = c.GList; // Use C definition from gtk/glib
pub const GtkWidget = c.GtkWidget;
pub const VimpCanvasItem = opaque {};
pub const GdkModifierType = c.GdkModifierType;
pub const VimpButtonPressType = c.gint; // Enum
pub const VimpButtonReleaseType = c.gint; // Enum
pub const VimpToolAction = c.gint; // Enum
pub const VimpCursorPrecision = c.gint; // Enum
pub const VimpOrientationType = c.gint; // Enum
pub const VimpCursorType = c.gint; // Enum
pub const VimpToolCursorType = c.gint; // Enum
pub const VimpCursorModifier = c.gint; // Enum
pub const VimpUIManager = opaque {};
pub const VimpToolOptions = opaque {};
pub const GError = c.GError;
pub const GdkEventKey = c.GdkEventKey;
pub const GParamSpec = c.GParamSpec;

// VimpObject (Implied from G_DECLARE_DERIVABLE_TYPE and no public struct)
// Based on VimpObject being GObject + private data
pub const VimpObject = extern struct {
    parent_instance: c.GObject,
};

pub const VimpObjectClass = extern struct {
    parent_class: c.GObjectClass,
    disconnect: ?*const fn (*VimpObject) callconv(.C) void,
    name_changed: ?*const fn (*VimpObject) callconv(.C) void,
    get_memsize: ?*const fn (*VimpObject, *i64) callconv(.C) i64,
};

// VimpCoords from core/core-types.h
pub const VimpCoords = extern struct {
    x: f64,
    y: f64,
    pressure: f64,
    xtilt: f64,
    ytilt: f64,
    wheel: f64,
    distance: f64,
    rotation: f64,
    slider: f64,
    velocity: f64,
    direction: f64,
    xscale: f64,
    yscale: f64,
    angle: f64,
    reflect: c.gboolean,
};

// VimpTool from app/tools/gimptool.h
pub const VimpTool = extern struct {
    parent_instance: VimpObject,

    tool_info: *VimpToolInfo,

    label: [*c]c.gchar,
    undo_desc: [*c]c.gchar,
    icon_name: [*c]c.gchar,
    help_id: [*c]c.gchar,

    ID: c.gint,

    control: *VimpToolControl,

    display: *VimpDisplay,
    drawables: *GList,

    // Private state of gimp_tool_set_focus_display
    focus_display: *VimpDisplay,
    modifier_state: GdkModifierType,
    button_press_state: GdkModifierType,
    active_modifier_state: GdkModifierType,

    // Private state for synthesizing button_release
    last_pointer_coords: VimpCoords,
    last_pointer_time: u32,
    last_pointer_state: GdkModifierType,

    // Private state for click detection
    in_click_distance: c.gboolean,
    got_motion_event: c.gboolean,
    button_press_coords: VimpCoords,
    button_press_time: u32,

    // Status displays
    status_displays: *GList,

    // On-canvas progress
    progress: *VimpCanvasItem,
    progress_display: *VimpDisplay,
    progress_grab_widget: *GtkWidget,
    progress_cancelable: c.gboolean,
};

pub const VimpToolClass = extern struct {
    parent_class: VimpObjectClass,

    // virtual functions
    has_display: ?*const fn (*VimpTool, *VimpDisplay) callconv(.C) c.gboolean,
    has_image: ?*const fn (*VimpTool, *VimpImage) callconv(.C) *VimpDisplay,
    initialize: ?*const fn (*VimpTool, *VimpDisplay, **GError) callconv(.C) c.gboolean,
    control: ?*const fn (*VimpTool, VimpToolAction, *VimpDisplay) callconv(.C) void,

    button_press: ?*const fn (*VimpTool, *const VimpCoords, u32, GdkModifierType, VimpButtonPressType, *VimpDisplay) callconv(.C) void,
    button_release: ?*const fn (*VimpTool, *const VimpCoords, u32, GdkModifierType, VimpButtonReleaseType, *VimpDisplay) callconv(.C) void,
    motion: ?*const fn (*VimpTool, *const VimpCoords, u32, GdkModifierType, *VimpDisplay) callconv(.C) void,

    key_press: ?*const fn (*VimpTool, *GdkEventKey, *VimpDisplay) callconv(.C) c.gboolean,
    key_release: ?*const fn (*VimpTool, *GdkEventKey, *VimpDisplay) callconv(.C) c.gboolean,
    modifier_key: ?*const fn (*VimpTool, GdkModifierType, c.gboolean, GdkModifierType, *VimpDisplay) callconv(.C) void,
    active_modifier_key: ?*const fn (*VimpTool, GdkModifierType, c.gboolean, GdkModifierType, *VimpDisplay) callconv(.C) void,

    oper_update: ?*const fn (*VimpTool, *const VimpCoords, GdkModifierType, c.gboolean, *VimpDisplay) callconv(.C) void,
    cursor_update: ?*const fn (*VimpTool, *const VimpCoords, GdkModifierType, *VimpDisplay) callconv(.C) void,

    can_undo: ?*const fn (*VimpTool, *VimpDisplay) callconv(.C) [*c]const c.gchar,
    can_redo: ?*const fn (*VimpTool, *VimpDisplay) callconv(.C) [*c]const c.gchar,
    undo: ?*const fn (*VimpTool, *VimpDisplay) callconv(.C) c.gboolean,
    redo: ?*const fn (*VimpTool, *VimpDisplay) callconv(.C) c.gboolean,

    get_popup: ?*const fn (*VimpTool, *const VimpCoords, GdkModifierType, *VimpDisplay, [*c][*c]const c.gchar) callconv(.C) *VimpUIManager,
    options_notify: ?*const fn (*VimpTool, *VimpToolOptions, *GParamSpec) callconv(.C) void,

    is_destructive: c.gboolean,
};
