# TODO.md

## High-Level Alignment
> Tracks alignment with design docs in `doc/`. Cross-reference when picking up tasks.

- [ ] `doc/gimp-file-open-spec.md` - File open/import workflows (Partial)

## UI/UX Improvements (Priority: High)
- [x] Implement Tool Grouping (Implemented in `src/ui/sidebar.zig` with popovers).
- [x] Implement Properties Sidebar (Implemented `src/widgets/tool_options_panel.zig`).
- [x] Sidebar should be resizable and not be > 20% of the window width (Implemented with GtkPaned constraints).
- [x] Default colors in two rows by defaults shows up as black instead of their own color.

## Code Health & Refactoring (Priority: Medium)
> Technical debt reduction to enable easier feature development and maintainability.

- [x] **Refactor Engine - Split Modules:** Break down `src/engine.zig` (God Object) into cohesive modules in `src/engine/`.
    - [x] Extract `Layer` struct and management logic to `src/engine/layers.zig` with unit tests.
    - [x] Extract `Command` and Undo/Redo stack to `src/engine/history.zig` with unit tests.
    - [x] Extract painting primitives (Bresenham, Airbrush) to `src/engine/paint.zig` with unit tests.
    - [x] Extract selection logic (Rectangle, Ellipse, Lasso) to `src/engine/selection.zig` with unit tests.
    - [x] Extract channel management to `src/engine/channels.zig` with unit tests.
- [x] **Refactor Tool System:** Decouple `src/main.zig` by implementing a polymorphic Tool interface.
    - [x] Define `Tool` interface in `src/tools/interface.zig` (handling `drag_begin`, `update`, `end`, etc.).
    - [x] Move Paint Tools (Brush, Pencil, Airbrush, Eraser, Bucket Fill) to `src/tools/`.
    - [x] Move Selection Tools (Rect, Ellipse) to `src/tools/`.
    - [x] Move remaining tools (Lasso, Shapes, Lines, Text, Gradient, Picker) to `src/tools/`.
    - [x] Update `src/main.zig` to delegate events to the active `Tool` instance.
    - [x] Refactor tool creation to `src/tools/factory.zig`.
- [x] **Refactor UI - Split Main:** Decompose `src/main.zig` UI construction.
    - [x] Extract Sidebar construction to `src/ui/sidebar.zig`.
    - [x] Extract Header construction to `src/ui/header.zig`.

## File Format Support (Priority: Medium)
- [x] **XCF:** Full layer/channel/path support (Layers, Channels, and Paths implemented).
- [x] **PDF Import:** Support opening multiple pages as separate images (implemented via multi-process spawning).

## Input & Navigation (Priority: Medium)
- [x] Implement pinch-to-zoom gesture support (Verified existing implementation).
- [ ] Implement two-finger pan gesture support (Verify existing implementation covers all cases).

## Specialized Features (Priority: Low)
- [x] Implement HUD for live dimensions during selection/transform (Implemented in `src/main.zig`).
- [ ] PostScript (.ps, .eps) import.

## Testing & Quality Assurance (Proposals)
> Strategies to improve stability and accessibility verification.

- [x] **Evaluate AT-SPI based testing (Dogtail/PyATSPI):**
    - **Outcome:** Deferred. Requires system-level dependencies (`gobject-introspection`, `at-spi2-core`) which are not available in the current environment.
    - Leverage GNOME's accessibility layer (AT-SPI) to drive the UI for E2E tests.
    - Allows black-box testing of widgets and user flows without relying on brittle coordinate clicks.
    - Ensures the application remains accessible to screen readers.
- [x] **Evaluate Broadway + Web Automation (Playwright/Selenium):**
    - Run Vimp with `GDK_BACKEND=broadway` to render the UI in a web browser.
    - Use mature web testing ecosystems (Playwright, Cypress) to inspect DOM and simulate input.
    - Potential for cross-platform visual regression testing via browser screenshots.
- [x] **Implement Visual Regression Testing:**
    - Capture canvas output (via `gegl:save` or `gdk_texture_download`) and compare against baseline images.
    - Essential for verifying rendering correctness of GEGL graph operations.
- [ ] **UI Analysis & Feedback Tools:**
    - Integrate `GtkInspector` (accessible via Ctrl+Shift+I or `GTK_DEBUG=interactive`) for runtime widget analysis.
    - Use `Accerciser` to audit the accessibility tree and verify `ATK_RELATION_LABEL_FOR` properties.
