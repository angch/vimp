# Agent Guidelines for Vimp

## Project Overview
Vimp is a learning project attempting to create a GIMP-like application using **Zig** and **GTK4**, complying with the **GNOME HIG**.
Goal: Upgrade GIMP concepts to a modern stack (Zig, GTK4, GEGL/Babl).

## Documentation
- [Architecture](doc/architecture.md) - Directory structure, key components, and data flow.
- [Development Workflow](doc/development_workflow.md) - Build instructions, environment setup, and reference code.
- [Coding Conventions](doc/coding_conventions.md) - Naming, memory management, and C interop guidelines.
- [Agent Protocol](doc/agent_protocol.md) - Task selection, implementation, verification, and documentation steps.
- [Dev Log / Engineering Notes](doc/dev_log.md) - History of changes, decisions, and technical notes.

## Skills (Generic)
- [Zig & GTK Interop](.agent/skills/zig_gtk_interop/SKILL.md) - Guidelines for interacting with GObject/C from Zig.
- [GTK4 Migration](.agent/skills/gtk4_migration/SKILL.md) - Patterns for migrating from older GTK versions.

## Feature Specs & Analysis
- [GIMP Analysis](doc/gimp-analysis.md)
- [GNOME HIG Analysis](doc/gnome-hig-analysis.md)
- [GAP Analysis](doc/gimp_gnome_hig_gap_analysis.md)

## Tech Stack Summary
- **Language**: Zig 0.15+
- **Toolkit**: GTK4 + Libadwaita
- **Engine**: GEGL 0.4 / Babl 0.1
- **Build**: `zig build`

## Environment Limitations
- **GEGL Loaders**: The development environment lacks loaders for certain formats like EPS/PostScript (`image/x-eps`). While filters are implemented in the UI, `gegl:load` may fail with a warning unless proper delegates (Ghostscript) or plugins are installed.
- **Missing Operations**: `gegl:color-to-alpha` appears to be missing or fails to load in the current environment (warns "using a passthrough op instead"). Manual pixel manipulation is required for transparency effects.

## Critical Gotchas & Learnings
- **High Contrast Support:** Avoid hardcoded colors (e.g. `rgba(0,0,0,0.2)`) for borders or backgrounds. Use `alpha(currentColor, 0.2)` or standard style classes (`.osd`, `.sidebar`, `.background`) to respect system themes and High Contrast mode.
* When using `gdk_texture_download` to extract bytes for GEGL, use `c.babl_format("cairo-ARGB32")` as the source format, as GDK/Cairo often use BGRA memory layout on little-endian systems, while `R'G'B'A u8` expects RGBA.
* `gegl:save` can be used for generic image export (JPG, PNG, WEBP, etc.) by inferring the format from the file extension. It is preferred over `cairo_surface_write_to_png` as it handles color depth and format delegation properly.
* **Stateful Actions:** For UI toggles (e.g., Show Grid), use `g_simple_action_new_stateful`. Implement a callback connected to "change-state" that updates the global/engine boolean, updates the action state via `g_simple_action_set_state`, and triggers a redraw. Ensure the default value in code matches the default value passed to `g_simple_action_new_stateful`.
* **GtkFlowBox Manual Population:** When replacing `GtkListBox` with `GtkFlowBox` for dynamic lists (e.g., Recent Files), ensure you remove children using a loop (e.g. `c.gtk_flow_box_remove`) before repopulating. Unlike `GtkGridView` which uses models, `GtkFlowBox` allows manual widget insertion via `gtk_flow_box_append`. Use `child-activated` signal instead of `row-activated` and retrieve the inner custom widget via `gtk_flow_box_child_get_child`.
* **Zig Slices to C Strings:** When passing Zig string slices (e.g. from `std.mem.trim`) to C functions like `gtk_editable_set_text`, ensure they are null-terminated. Slices are not guaranteed to have a null terminator at `slice.ptr + slice.len`. Use `std.fmt.allocPrintSentinel` to create a temporary Z-string if needed.
