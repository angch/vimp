# Architecture

## GUI (src/main.zig)
Handles windowing, inputs, and drawing the canvas (via Cairo).

## Engine (src/engine.zig)
Handles the GEGL graph, buffers, and image operations.
- *Threading*: GEGL init/exit is not thread-safe. `Engine` handles this with a mutex for initialization if needed.
- *Data Flow*: GUI inputs -> Engine methods -> Engine updates GEGL buffer -> GUI requests draw -> Engine blits to Cairo surface -> GUI paints Surface.

## Directory Structure
- `src/main.zig`: Application entry point and GUI logic.
- `src/engine/`: Refactored image processing engine modules.
- `src/tools/`: Tool implementations.
- `src/ui/`: UI components (sidebar, header, etc.).
- `src/c.zig`: C import definitions (GTK, GEGL, Babl, Adwaita).
- `src/widgets/`: GTK4 widget implementations.
- `build.zig`: Build configuration and test definitions.
- `scripts/`: Utility scripts (setup, vendoring).
- `libs/`: Vendored libraries (GEGL/Babl).
- `ref/gimp`: Clone of the GIMP repository for reference and tests. **Ignored by git**.

## Architecture Analysis
- Place architecture decision records (ADRs) and technology evaluations in `doc/architecture-analysis/`.
- Use a consistent format: Goal, Criteria, Analysis, Selection.
