---
name: gtk4_migration
description: Patterns and replacements for migrating from GIMP/GTK2/3 to GTK4
---

# GTK4 Migration Patterns

## GtkAccelGroup
`GtkAccelGroup` is deprecated in GTK4.
- **Replacement**: Use `GtkShortcutController`.
- **Setup**:
  1. Create a `GtkShortcutController`.
  2. Set scope to `GTK_SHORTCUT_SCOPE_MANAGED` (for window/dialog scope).
  3. Add it to the widget with `gtk_widget_add_controller`.
- **Callbacks**:
  - Replace `GtkAccelGroupActivate` callbacks:
    `void func(GtkAccelGroup*, GObject*, guint, GdkModifierType, gpointer)`
  - With `GtkShortcutFunc` callbacks:
    `gboolean func(GtkWidget*, GVariant*, gpointer)`
- **Mapping**:
  - Use `gtk_application_get_accels_for_action` to get accelerator strings.
  - Parse them with `gtk_shortcut_trigger_parse_string`.
  - Bind them to actions using `gtk_callback_action_new`.
