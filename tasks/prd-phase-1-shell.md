# PRD: Phase 1 - The Zig/GTK4 Shell

## Introduction

Implement the initial application shell using Zig and GTK4. This phase establishes the project structure, build system, and basic UI layout, proving the viability of the chosen stack (Zig + GTK4) as recommended in the architecture analysis.

## Goals

- Establish a working Zig build system for Linux.
- Create a main window with modern GNOME styling (HeaderBar).
- Implement a basic static layout with a sidebar and main canvas area.
- Implement basic interaction (click-to-draw) on the canvas to verify event handling.

## User Stories

### US-001: Project Setup & Linux Build System
**Description:** As a developer, I want a reproducible build command so I can compile the application on Linux.

**Acceptance Criteria:**
- [ ] `zig build` produces a binary executable.
- [ ] Project compiles against system GTK4 libraries.
- [ ] `build.zig` uses standard configuration patterns.
- [ ] Typecheck/Compile passes.

### US-002: Main Window with Custom Decorations (CSD)
**Description:** As a user, I want a modern-looking window so that the app feels native to the GNOME environment.

**Acceptance Criteria:**
- [ ] Window uses GTK4 Client-Side Decorations (HeaderBar).
- [ ] Application title and standard window controls (min, max, close) are visible and functional.
- [ ] Window is resizable.
- [ ] Visual verification (Launch app and check window frame).

### US-003: Static Layout Implementation
**Description:** As a user, I want to see a sidebar and a main area so I can distinguish between tools and the workspace.

**Acceptance Criteria:**
- [ ] Layout contains a Sidebar on the left (fixed width or minimally static).
- [ ] Layout contains a Main Content Area on the right.
- [ ] Areas have distinct visual separation (different background colors or borders).
- [ ] Visual verification.

### US-004: Basic Canvas Interaction
**Description:** As a user, I want to draw on the canvas so I can see that the application is responsive.

**Acceptance Criteria:**
- [ ] Clicking and dragging on the main canvas area draws pixels (e.g., simplistic single-color line or dots).
- [ ] Pointer input events are correctly captured by the view.
- [ ] No crashes during drawing.

## Functional Requirements

- **FR-1:** Application entry point written in Zig.
- **FR-2:** GTK4 Window setup utilizing `GtkHeaderBar` for decorations.
- **FR-3:** Layout container (e.g., `GtkBox`) to manage the Sidebar and Canvas.
- **FR-4:** `GtkDrawingArea` used for the Canvas component.
- **FR-5:** GTK Signal handlers (Event Controllers) connected to the Canvas for mouse/pointer input.

## Non-Goals

- Cross-platform builds (Windows/macOS support is postponed).
- Complex docking, tabs, or resizable panes (dynamic layout).
- Loading or saving images.
- Advanced brush dynamics (pressure sensitivity, anti-aliasing, etc.).
- Complete "GIMP-like" functionalities beyond simple pixel placement.

## Technical Considerations

- **Zig Version:** Use the latest stable or agreed-upon nightly (lock in `build.zig.zon` if possible).
- **Interop:** Direct C interop with `@cImport("gtk/gtk.h")`.
- **Memory Management:** Use standard Zig patterns (`defer`, `allocators`) where applicable, while respecting GTK's object ownership model (mostly reference counting).
- **Dependencies:** `gtk4`, `glib-2.0`, `libc`.

## Success Metrics

- Successful compilation on the user's Linux machine without errors.
- Application launches instantaneously (<1s).
- Basic drawing loop runs at 60fps (no obvious lag on simple input).

## Open Questions

- None at this stage. (Scope strictly defined by user selection).
