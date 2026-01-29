# PRD: Phase 2 - The Core (Interop)

## Introduction

Integrate the core image processing engine by linking Zig with `libgegl` and `libbabl`. This phase transforms the application from a hollow shell into a functioning (albeit basic) graphics editor by backing the GTK4 canvas with a real GEGL graph and enabling pixel-level manipulation.

## Goals

- Seamless integration of `libgegl` and `libbabl` into the Zig build system.
- Establish a "Zig-native" way to manipulate GEGL nodes (using `@cImport`).
- Render a live GEGL buffer to the GTK4 window.
- Implement basic "draw on click" functionality that modifies the underlying GEGL buffer.

## User Stories

### US-001: Build System Dependencies (GEGL/Babl)
**Description:** As a developer, I need the build system to link against system GEGL and Babl libraries so I can call their functions from Zig.

**Acceptance Criteria:**
- [ ] `zig build` links `libgegl-0.4` (or similar) and `libbabl-0.1`.
- [ ] `@cImport` in Zig successfully finds `gegl.h` and `babl.h`.
- [ ] Application compiles and runs without linker errors.
- [ ] Typecheck passes.

### US-002: GEGL Initialization & Graph Setup
**Description:** As a developer, I want the application to initialize the GEGL engine on startup so it is ready for image processing.

**Acceptance Criteria:**
- [ ] Call `gegl_init()` and `babl_init()` at application launch.
- [ ] Construct a basic GEGL graph (e.g., a background color node connected to a write buffer).
- [ ] Clean up resources (if applicable) on exit.
- [ ] No crashes on startup.

### US-003: Render GEGL Buffer to Canvas
**Description:** As a user, I want to see the actual image data from GEGL displayed in the window, rather than a placeholder.

**Acceptance Criteria:**
- [ ] Extract pixel data from the GEGL graph/node.
- [ ] Convert/Blit the data to a format compatible with `GtkDrawingArea` (e.g., `GdkTexture` or Cairo surface).
- [ ] The canvas displays the visual output of the GEGL graph (e.g., a solid color or pattern defined by the graph).
- [ ] Visual verification.

### US-004: Interactive Drawing (GEGL Update)
**Description:** As a user, when I draw on the canvas, I want the underlying image data to change using GEGL operations.

**Acceptance Criteria:**
- [ ] Mouse/Pointer events on the canvas map to coordinates in the GEGL graph.
- [ ] Clicking/Dragging applies a GEGL operation (e.g., painting a stroke on a buffer node) or modifies a node property.
- [ ] The view updates to reflect the change (repaint triggered).
- [ ] Visual verification (strokes appear where drawn).

## Functional Requirements

- **FR-1:** `build.zig` configured to use `pkg-config` (or manual paths) for `gegl` and `babl`.
- **FR-2:** `GeglNode` wrapper or direct usage in Zig to manage the graph.
- **FR-3:** Mechanism to copy data from `GeglBuffer` to GTK4 texture/surface (Inter-process or memory copy).
- **FR-4:** Event loop integration ensures GEGL processing doesn't block the UI thread (or use `gegl_processor` properly).

## Non-Goals

- Linking `libgimp` (GIMP Core) - Reserved for Phase 3.
- Complex tools (Brush dynamics, layers, etc.).
- Saving/Loading files.
- GPU acceleration (OpenCL) explicit optimization (rely on GEGL defaults).

## Technical Considerations

- **Interop:** Use `@cImport` for all GEGL/Babl calls.
- **Memory:** Be careful with C pointers returned by GEGL. Ensure proper initialization/cleanup.
- **Performance:** For US-003, ensure the transfer from GEGL buffer to display is reasonably fast (avoid full copies if possible, but copy is acceptable for Phase 2).

## Success Metrics

- Check `ldd` verifies linkage to `libgegl` and `libbabl`.
- Drawing a line results in a visible stroke backed by the engine.

## Open Questions

- Exact version of GEGL/Babl available on the user's system vs what we need? (Assume system default for now).
