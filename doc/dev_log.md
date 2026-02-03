# Engineering Notes / Dev Log

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

### 2026-01-31: Ripple/Waves Filter
- Implemented `gegl:waves` support in `src/engine.zig`.
- Added "Waves" dialog with Amplitude, Phase, and Wavelength controls.
- Note: `gegl:waves` operation is missing in the development environment (similar to oilify), causing passthrough behavior in tests.

### 2026-01-31: Lighting Effects Filter
- Implemented `gegl:lighting` support in `src/engine.zig`.
- Added "Lighting Effects" dialog with Position (X, Y, Z), Intensity, and Color controls.
- Defaulted to Point light type (0).
- Validated with `test "Engine lighting"` (note: `gegl:lighting` is missing in current dev env, causing passthrough warning).

### 2026-01-31: Colored Icons Implementation
- Generated SVG icons for all tools using `scripts/generate_icons.py`.
- Updated `src/main.zig` to use these SVG assets instead of symbolic icons.
- **Finding/Gotcha**: The application currently loads assets using relative paths (e.g., `assets/brush.png`). This makes the executable dependent on the current working directory.
- **Future Task**: Refactor asset loading to embed resources directly into the binary (e.g., using `@embedFile` or GResource) to improve robustness and portability.
