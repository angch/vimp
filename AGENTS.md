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
- `build.zig`: Build configuration and test definitions.
- `scripts/`: Utility scripts (setup, vendoring).
- `libs/`: Vendored libraries (GEGL/Babl) - *Do not modify manually unless necessary*.
- `tasks/` & `prd.json`: Ralph Agent workflow files.

## Development Workflow

### Build & Run
- **Build**: `zig build`
- **Run**: `zig build run`
- **Test**: `zig build test` (Runs both unit tests and engine tests).

### Environment
- The project uses vendored headers/libs for GEGL/Babl in `libs/`.
- `build.zig` automatically handles `GEGL_PATH`, `BABL_PATH`, and `LD_LIBRARY_PATH` when running via `zig build run` or `zig build test`.
- If running binaries directly, ensure these environment variables are set (see `build.zig` for details).
- Development environment setup script is available at `scripts/setup_dev_machine.sh`.

## Coding Conventions

### Zig & C Interop
- Use `@cImport` definitions from `src/c.zig`.
- **Memory Management**: GTK/GEGL objects are reference-counted.
  - Use `c.g_object_unref(obj)` when you own a reference and are done with it.
  - Be careful with signal callbacks; generally `user_data` can pass pointers to Zig structs.
- **Signals**: Use `c.g_signal_connect_data` to connect signals to Zig functions. The callback must have `callconv(std.builtin.CallingConvention.c)`.

### Architecture
- **GUI (src/main.zig)**: Handles windowing, inputs, and drawing the canvas (via Cairo).
- **Engine (src/engine.zig)**: Handles the GEGL graph, buffers, and image operations.
  - *Threading*: GEGL init/exit is not thread-safe. `Engine` handles this with a mutex for initialization if needed.
  - *Data Flow*: GUI inputs -> Engine methods -> Engine updates GEGL buffer -> GUI requests draw -> Engine blits to Cairo surface -> GUI paints Surface.

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
