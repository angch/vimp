# TODO.md

## High-Level Alignment
> Tracks alignment with design docs in `doc/`. Cross-reference when picking up tasks.

- [ ] `doc/gimp-file-open-spec.md` - File open/import workflows (Partial)

## Code Health & Refactoring (Priority: High)
> Technical debt reduction to enable easier feature development and maintainability.

- [ ] **Refactor Engine - Split Modules:** Break down `src/engine.zig` (God Object) into cohesive modules in `src/engine/`.
    - [x] Extract `Layer` struct and management logic to `src/engine/layers.zig` with unit tests.
    - [ ] Extract `Command` and Undo/Redo stack to `src/engine/history.zig` with unit tests.
    - [ ] Extract painting primitives (Bresenham, Airbrush) to `src/engine/paint.zig` with unit tests.
    - [ ] Extract selection logic (Rectangle, Ellipse, Lasso) to `src/engine/selection.zig` with unit tests.
- [ ] **Refactor Tool System:** Decouple `src/main.zig` by implementing a polymorphic Tool interface.
    - [ ] Define `Tool` interface in `src/tools/interface.zig` (handling `drag_begin`, `update`, `end`, etc.).
    - [ ] Move tool-specific logic (Brush, Pencil, Select, etc.) from `src/main.zig` to `src/tools/<tool>.zig`.
    - [ ] Update `src/main.zig` to delegate events to the active `Tool` instance.
- [ ] **Refactor UI - Split Main:** Decompose `src/main.zig` UI construction.
    - [ ] Extract Sidebar construction to `src/ui/sidebar.zig`.
    - [ ] Extract Header construction to `src/ui/header.zig`.

## File Format Support (Priority: High)
- [ ] **XCF:** Full layer/channel/path support (currently basic flattened load).
- [ ] **PDF Import:** Support opening multiple pages as separate images (currently warning/reset).

## Input & Navigation (Priority: Medium)
- [ ] Implement pinch-to-zoom gesture support (Verify existing implementation covers all cases).
- [ ] Implement two-finger pan gesture support (Verify existing implementation covers all cases).

## UI/UX Improvements (Priority: Medium)
- [ ] [Verify/Complete] Implement Tool Grouping (Popovers/long-press revealers are present in `main.zig`, verify completeness).
- [ ] Implement Properties Sidebar (contextual tool options).

## Specialized Features (Priority: Low)
- [ ] Implement HUD for live dimensions during selection/transform.
- [ ] PostScript (.ps, .eps) import.
