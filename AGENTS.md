# Agent Guidelines for Vimp

## Project Overview
Vimp is a learning project attempting to create a GIMP-like application using **Zig** and **GTK4**, complying with the **GNOME HIG**.
Goal: Upgrade GIMP concepts to a modern stack (Zig, GTK4, GEGL/Babl).

## Technology Stack
- **Language**: Zig 0.15+ (Do not use older versions).
- **GUI Toolkit**: GTK4 + Libadwaita (via C interop).
- **Image Engine**: GEGL 0.4 / Babl 0.1.
- **Build System**: `zig build`.

## Directory Structure
- `src/main.zig`: Application entry point and GUI logic.
- `src/engine.zig`: Image processing engine (wrapper around GEGL).
- `src/c.zig`: C import definitions (GTK, GEGL, Babl, Adwaita).
- `src/widgets/`: GTK4 widget implementations (ported from GIMP).
- `build.zig`: Build configuration and test definitions.
- `scripts/`: Utility scripts (setup, vendoring).
- `libs/`: Vendored libraries (GEGL/Babl) - *Do not modify manually unless necessary*.
- `tasks/` & `prd.json`: Ralph Agent workflow files.
- `ref/gimp`: Clone of the GIMP repository for reference and tests. **Ignored by git**.

## Development Workflow

### Build & Run
- **Build**: `zig build`
- **Run**: `zig build run`
- **Test**: `zig build test` (Runs unit tests, engine tests, and widget tests).

### Environment
- The project uses vendored headers/libs for GEGL/Babl in `libs/`.
- `build.zig` automatically handles `GEGL_PATH`, `BABL_PATH`, and `LD_LIBRARY_PATH` when running via `zig build run` or `zig build test`.
- If running binaries directly, ensure these environment variables are set (see `build.zig` for details).
- Development environment setup script is available at `setup.sh` (wraps `scripts/setup_dev_machine.sh` logic and library setup).

### Reference Code & Porting
- The directory `ref/gimp` contains a partial or full clone of the GIMP repository (setup by `setup.sh`).
- This directory is **ignored by git**.
- If a task requires modifying code within `ref/gimp` (e.g., fixing deprecations or bugs in the reference implementation to make it compatible or testable), you **must create a patch file**.
  - Make your changes in `ref/gimp`.
  - Run `git diff path/to/changed/file > my-change.patch` from the `ref/gimp` directory (or adjusted path).
  - Save the patch file in the project root.
  - Submit the patch file.

## Coding Conventions

### Zig & C Interop
- **Safety**: Always validate C pointers and return codes. Use `std.debug.print` for errors in GUI context if throwing is not an option.
- Use `@cImport` definitions from `src/c.zig`.
- **Memory Management**: GTK/GEGL objects are reference-counted.
  - Use `c.g_object_unref(obj)` when you own a reference and are done with it.
  - Be careful with signal callbacks; generally `user_data` can pass pointers to Zig structs.
- **Signals**: Use `c.g_signal_connect_data` to connect signals to Zig functions. The callback must have `callconv(std.builtin.CallingConvention.c)` or `callconv(.c)`.

### Naming
- **Vimp vs GIMP**: We are making something that is feature compatible, we are not replacing GIMP. Avoid variables or references with "GIMP" in the codebase (e.g., use `VimpTool` instead of `GimpTool`).
- **Bindings**: The directory `src/vimp/` contains structures that mirror GIMP's memory layout for verification, but they should be named `Vimp...`.

### Architecture
- **GUI (src/main.zig)**: Handles windowing, inputs, and drawing the canvas (via Cairo).
- **Engine (src/engine.zig)**: Handles the GEGL graph, buffers, and image operations.
  - *Threading*: GEGL init/exit is not thread-safe. `Engine` handles this with a mutex for initialization if needed.
  - *Data Flow*: GUI inputs -> Engine methods -> Engine updates GEGL buffer -> GUI requests draw -> Engine blits to Cairo surface -> GUI paints Surface.

### GTK4 Migration Patterns
- **GtkAccelGroup**: `GtkAccelGroup` is deprecated in GTK4.
  - **Replacement**: Use `GtkShortcutController`.
  - **Setup**: Create a `GtkShortcutController`, set scope to `GTK_SHORTCUT_SCOPE_MANAGED` (for window/dialog scope), and add it to the widget with `gtk_widget_add_controller`.
  - **Callbacks**: Replace `GtkAccelGroupActivate` callbacks (`void func(GtkAccelGroup*, GObject*, guint, GdkModifierType, gpointer)`) with `GtkShortcutFunc` callbacks (`gboolean func(GtkWidget*, GVariant*, gpointer)`).
  - **Mapping**: Use `gtk_application_get_accels_for_action` to get accelerator strings, parse them with `gtk_shortcut_trigger_parse_string`, and bind them to actions using `gtk_callback_action_new`.

## Agent Protocol

1.  **Task Selection**: Check `TODO.md` or `prd.json` for active tasks.
2.  **Implementation**:
    - Modify source code in `src/`.
    - Create/Update tests in `src/` to verify changes.
3.  **Verification**:
    - **MUST** run `zig build test` before submitting.
    - If `zig build test` fails, fix the code or the test.
    - Verify GUI changes visually if possible (though agents often can't see, running the code ensures no crashes).
4.  **Documentation**:
    - Update `AGENTS.md` (this file) with any new findings, gotchas, or architectural decisions.
    - Update `progress.txt` if working in the Ralph loop.

## Known Issues / Gotchas
- GEGL plugin loading can be tricky in test environments. `build.zig` attempts to set it up correctly.
- Cairo surfaces need `cairo_surface_mark_dirty` after modification by GEGL/CPU before being painted again.
The overall guiding principle is to be a GIMP-like application
following GNOME HIG. This is detailed in the file
`doc/gimp_gnome_hig_gap_analysis.md` and should be consulted for long
term planning.

## Engineering Notes

### 2026-01-31: GtkEventBox Migration
- Replaced deprecated `GtkEventBox` with `GtkBox` + `GtkEventController` pattern for `TextStyleEditor` handle.
- Widgets in GTK4 have their own windows, so `GtkEventBox` is no longer needed.
- Use `GtkEventControllerMotion` for enter/leave signals.
- Use `GtkGestureDrag` for drag-and-drop operations.
- Implementation located in `src/widgets/text_style_editor.zig`.

### 2026-01-31: Basic Blur Filters (Gaussian)
- Implemented destructive Gaussian Blur on active layer using `gegl:gaussian-blur`.
- Reused `PaintCommand` for Undo/Redo as it handles buffer swapping.
- Exposed via "Filters" menu in Header Bar.
- Validated with `test "Engine gaussian blur"`.

### 2026-01-31: Security Hardening (Cairo/GEGL)
- Identified and fixed critical vulnerability where `cairo_image_surface_create` failure could lead to NULL pointer dereference.
- Enforced validation of Cairo surface status and data pointers before usage in `draw_func` and `save_file`.
- Added unit test "Cairo error surface check" in `src/engine.zig` to prevent regression.
- **Rule**: Always check `c.cairo_surface_status(s) == c.CAIRO_STATUS_SUCCESS` and `c.cairo_image_surface_get_data(s) != null` when working with Cairo surfaces, especially before passing data to C libraries like GEGL.

### 2026-01-30: Bucket Fill Optimization
- Implemented dirty rectangle tracking for `bucketFill` in `src/engine.zig`.
- Reduced memory bandwidth usage by only writing back changed pixels to GEGL.
- Benchmark: ~18% speedup for small fills (87ms -> 71ms).
- Bottleneck remains reading the full biopsy from GEGL to perform the flood fill client-side. Future optimization should look into tiling the read or using GEGL iterators.
 
 ### 2026-01-30: Rectangle Select Tool
 - Implemented `setSelection` and clipping in `engine.zig`.
 - Updated `paintStroke` and `bucketFill` to respect selection bounds.
 - Added `rect_select` tool to UI with "marching ants" visual feedback.
 - Verified correct clipping behavior with unit tests.

### 2026-01-30: Ellipse Select Tool
- Implemented Ellipse Select Tool with `SelectionMode` enum in `Engine`.
- Added `isPointInSelection` helper to centralize clipping logic (Rectangle vs Ellipse).
- Updated `paintStroke` and `bucketFill` to use this helper.
- UI: Added Ellipse tool button and Cairo rendering for elliptical selection (using `cairo_scale` and `cairo_arc`).
- Verified with unit tests for edge/corner cases of ellipse clipping.

### 2026-01-30: Layer Management
- Refactored `Engine` to support multiple layers using `std.ArrayList(Layer)`.
- Replaced static GEGL graph with dynamic `rebuildGraph` which chains `gegl:over` nodes for visible layers.
- Implemented `addLayer`, `removeLayer`, `reorderLayer`, `toggleLayerVisibility`, `toggleLayerLock`.
- Updated UI to include a Layers panel with controls and visibility/lock toggles.
- Gotcha: `std.ArrayList` in Zig 0.15+ behaves like `Unmanaged` (requires allocator for `append`/`deinit` and init via struct literal `{}`).
- Gotcha: `c.gegl_node_new_child` returns optional pointer, must be handled.
- Gotcha: `gegl_node_link` failures or graph update issues can cause rendering to stop.
- Gotcha: When removing layers, old `gegl:over` nodes in the composition chain must be cleaned up (currently removed from graph).

### 2026-01-31: Layer Undo/Redo System
- Implemented Undo/Redo for Layer operations: Add, Remove, Reorder, Visibility, Lock.
- Introduced `LayerCommand` and `LayerSnapshot` structs in `src/engine.zig`.
- Refactored layer operations to separate internal logic (`addLayerInternal`, etc.) from public API which handles Command creation.
- `LayerSnapshot` holds a reference to the `gegl_buffer`, ensuring data persists during Undo/Redo cycles even if the layer is removed from the engine.
- Verified with unit test `Engine layer undo redo`.

### 2026-01-31: Overlay Feedback (OSD)
- Implemented `OsdState` and helper functions (`osd_show`, `osd_hide_callback`) in `src/main.zig` to provide transient visual feedback.
- Used `GtkOverlay` to layer the OSD on top of the `GtkDrawingArea`.
- Used `GtkRevealer` for fade-in/out animations.
- Integrated OSD with Zoom (percentage feedback) and Tool Switching events.
- **Pattern**: `GtkOverlay` + `GtkRevealer` is effective for non-blocking notifications in GTK4 apps.

### 2026-01-31: Rendering Optimization & Resize Handling
- Fixed an issue where the intermediate Cairo surface in `src/main.zig` was not resized when the window/widget size changed, leading to clipping or artifacts.
- Implemented a `canvas_dirty` flag in `src/main.zig` to avoid expensive GEGL-to-Cairo blitting (`engine.blitView`) when the image content hasn't changed (e.g., during OSD animations or selection overlay repaints).
- **Rule**: Always manage intermediate surface lifecycle (destroy/recreate) on resize in `draw_func`.
- **Optimization**: Skip heavy composition steps if only overlay/vector elements need repainting.

### 2026-01-31: Unified Transform Tool
- Implemented `TransformParams` and `TransformCommand` in `src/engine.zig`.
- Added support for `gegl:transform` in `rebuildGraph` for live preview.
- Implemented `applyTransform` for destructive commit using `gegl:transform` and `gegl:write-buffer` (manual blit).
- Added `Unified Transform` tool to UI with Sidebar controls (Translate, Rotate, Scale) and an Overlay Action Bar (Apply/Cancel).
- **Note**: `gegl:transform` preview logic assumes rotation/scaling around the layer center.
- **Gotcha**: `c.gegl_node_new_child` with varargs requires careful handling of string pointers.

### 2026-01-31: File Open & Open as Layers
- Implemented `Ctrl+O` (Open) to reset the engine (clear layers, undo stack) before loading the new file.
- Implemented `Ctrl+Alt+O` (Open as Layers) to append the loaded file as a new layer without clearing existing content.
- Added `Engine.reset()` and `Engine.setCanvasSize()` to support these workflows.
- Refactored `src/main.zig` to use `OpenContext` for passing state to async file dialog callbacks.
- **Note**: `reset()` clears all layers and resets canvas size to default (800x600). Standard Open resizes canvas to match the loaded image.

### 2026-01-31: PDF Import "Separate Images"
- Implemented UI toggle "Open pages as separate images" in PDF import dialog.
- Current architecture supports only single-document interface (SDI).
- **Behavior**:
  - If single page selected + "Separate Images": Resets engine and loads page (Standard "Open").
  - If multiple pages selected + "Separate Images": Shows warning toast and falls back to "Open as Layers" (appending to current or new image), as creating multiple windows/tabs is not supported yet.
- **Future**: When MDI/Tabs are supported, `on_pdf_import` should be updated to spawn new instances for each page.
