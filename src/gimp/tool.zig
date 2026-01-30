const std = @import("std");
const c = @import("../c.zig").c;

// Check pointer size to ensure we are on 64-bit as assumed for now, or use c.long/c.int correctly
comptime {
    if (@sizeOf(usize) != 8) {
        @compileError("This code currently assumes 64-bit pointers for layout verification.");
    }
}

// Basic GObject/GIMP types helpers
pub const GimpContext = opaque {};
pub const GimpDisplay = opaque {};
pub const GimpImage = opaque {};
pub const GimpToolInfo = opaque {};
pub const GimpToolControl = opaque {};
pub const GList = c.GList; // Use C definition from gtk/glib
pub const GtkWidget = c.GtkWidget;
pub const GimpCanvasItem = opaque {};
pub const GdkModifierType = c.GdkModifierType;
pub const GimpButtonPressType = c.gint; // Enum
pub const GimpButtonReleaseType = c.gint; // Enum
pub const GimpToolAction = c.gint; // Enum
pub const GimpCursorPrecision = c.gint; // Enum
pub const GimpOrientationType = c.gint; // Enum
pub const GimpCursorType = c.gint; // Enum
pub const GimpToolCursorType = c.gint; // Enum
pub const GimpCursorModifier = c.gint; // Enum
pub const GimpUIManager = opaque {};
pub const GimpToolOptions = opaque {};
pub const GError = c.GError;
pub const GdkEventKey = c.GdkEventKey;
pub const GParamSpec = c.GParamSpec;

// GimpObject (Implied from G_DECLARE_DERIVABLE_TYPE and no public struct)
// Based on GimpObject being GObject + private data
pub const GimpObject = extern struct {
    parent_instance: c.GObject,
};

pub const GimpObjectClass = extern struct {
    parent_class: c.GObjectClass,
    disconnect: ?*const fn (*GimpObject) callconv(.C) void,
    name_changed: ?*const fn (*GimpObject) callconv(.C) void,
    get_memsize: ?*const fn (*GimpObject, *i64) callconv(.C) i64,
};

// GimpCoords from core/core-types.h
pub const GimpCoords = extern struct {
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

// GimpTool from app/tools/gimptool.h
pub const GimpTool = extern struct {
    parent_instance: GimpObject,

    tool_info: *GimpToolInfo,

    label: [*c]c.gchar,
    undo_desc: [*c]c.gchar,
    icon_name: [*c]c.gchar,
    help_id: [*c]c.gchar,

    ID: c.gint,

    control: *GimpToolControl,

    display: *GimpDisplay,
    drawables: *GList,

    // Private state of gimp_tool_set_focus_display
    focus_display: *GimpDisplay,
    modifier_state: GdkModifierType,
    button_press_state: GdkModifierType,
    active_modifier_state: GdkModifierType,

    // Private state for synthesizing button_release
    last_pointer_coords: GimpCoords,
    last_pointer_time: u32,
    last_pointer_state: GdkModifierType,

    // Private state for click detection
    in_click_distance: c.gboolean,
    got_motion_event: c.gboolean,
    button_press_coords: GimpCoords,
    button_press_time: u32,

    // Status displays
    status_displays: *GList,

    // On-canvas progress
    progress: *GimpCanvasItem,
    progress_display: *GimpDisplay,
    progress_grab_widget: *GtkWidget,
    progress_cancelable: c.gboolean,
};

pub const GimpToolClass = extern struct {
    parent_class: GimpObjectClass,

    // virtual functions
    has_display: ?*const fn (*GimpTool, *GimpDisplay) callconv(.C) c.gboolean,
    has_image: ?*const fn (*GimpTool, *GimpImage) callconv(.C) *GimpDisplay,
    initialize: ?*const fn (*GimpTool, *GimpDisplay, **GError) callconv(.C) c.gboolean,
    control: ?*const fn (*GimpTool, GimpToolAction, *GimpDisplay) callconv(.C) void,

    button_press: ?*const fn (*GimpTool, *const GimpCoords, u32, GdkModifierType, GimpButtonPressType, *GimpDisplay) callconv(.C) void,
    button_release: ?*const fn (*GimpTool, *const GimpCoords, u32, GdkModifierType, GimpButtonReleaseType, *GimpDisplay) callconv(.C) void,
    motion: ?*const fn (*GimpTool, *const GimpCoords, u32, GdkModifierType, *GimpDisplay) callconv(.C) void,

    key_press: ?*const fn (*GimpTool, *GdkEventKey, *GimpDisplay) callconv(.C) c.gboolean,
    key_release: ?*const fn (*GimpTool, *GdkEventKey, *GimpDisplay) callconv(.C) c.gboolean,
    modifier_key: ?*const fn (*GimpTool, GdkModifierType, c.gboolean, GdkModifierType, *GimpDisplay) callconv(.C) void,
    active_modifier_key: ?*const fn (*GimpTool, GdkModifierType, c.gboolean, GdkModifierType, *GimpDisplay) callconv(.C) void,

    oper_update: ?*const fn (*GimpTool, *const GimpCoords, GdkModifierType, c.gboolean, *GimpDisplay) callconv(.C) void,
    cursor_update: ?*const fn (*GimpTool, *const GimpCoords, GdkModifierType, *GimpDisplay) callconv(.C) void,

    can_undo: ?*const fn (*GimpTool, *GimpDisplay) callconv(.C) [*c]const c.gchar,
    can_redo: ?*const fn (*GimpTool, *GimpDisplay) callconv(.C) [*c]const c.gchar,
    undo: ?*const fn (*GimpTool, *GimpDisplay) callconv(.C) c.gboolean,
    redo: ?*const fn (*GimpTool, *GimpDisplay) callconv(.C) c.gboolean,

    get_popup: ?*const fn (*GimpTool, *const GimpCoords, GdkModifierType, *GimpDisplay, [*c][*c]const c.gchar) callconv(.C) *GimpUIManager,
    options_notify: ?*const fn (*GimpTool, *GimpToolOptions, *GParamSpec) callconv(.C) void,

    is_destructive: c.gboolean,
};
