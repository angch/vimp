---
name: gtk4_ui
description: "Guidelines and best practices for developing UI with GTK4 in Vimp."
---

# GTK4 UI Best Practices

## Styling & Accessibility
- **High Contrast Support:**
  - Avoid hardcoded colors (e.g. `rgba(0,0,0,0.2)`) for borders or backgrounds.
  - Use `alpha(currentColor, 0.2)` or standard style classes (`.osd`, `.sidebar`, `.background`) to respect system themes and High Contrast mode.

## Actions & State
- **Stateful Actions (Toggles):**
  - For UI toggles (e.g., Show Grid), use `g_simple_action_new_stateful`.
  - Implement a callback connected to `"change-state"`.
  - The callback must:
    1. Update the global/engine state (boolean).
    2. Update the action state via `g_simple_action_set_state`.
    3. Trigger a redraw.
  - **Important:** Ensure the default value in code matches the default value passed to `g_simple_action_new_stateful`.

## Widgets
- **GtkFlowBox Manual Population:**
  - When replacing `GtkListBox` with `GtkFlowBox` for dynamic lists (e.g., Recent Files), you must manually manage children.
  - **Clear First:** Ensure you remove children using a loop (e.g. `c.gtk_flow_box_remove`) before repopulating.
  - **Appending:** `GtkFlowBox` allows manual widget insertion via `gtk_flow_box_append` (unlike `GtkGridView` which uses models).
  - **Signals:** Use `child-activated` signal (instead of `row-activated`).
  - **Retrieving Children:** Retrieve the inner custom widget via `gtk_flow_box_child_get_child`.
