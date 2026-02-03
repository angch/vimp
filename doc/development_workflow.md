# Development Workflow

## Build & Run
- **Build**: `zig build`
- **Run**: `zig build run`
- **Test**: `zig build test` (Runs unit tests, engine tests, and widget tests).

## Environment
- The project uses vendored headers/libs for GEGL/Babl in `libs/`.
- `build.zig` automatically handles `GEGL_PATH`, `BABL_PATH`, and `LD_LIBRARY_PATH` when running via `zig build run` or `zig build test`.
- If running binaries directly, ensure these environment variables are set (see `build.zig` for details).
- Development environment setup script is available at `setup.sh` (wraps `scripts/setup_dev_machine.sh` logic and library setup).

## Reference Code & Porting
- The directory `ref/gimp` contains a partial or full clone of the GIMP repository (setup by `setup.sh`).
- This directory is **ignored by git**.
- If a task requires modifying code within `ref/gimp` (e.g., fixing deprecations or bugs in the reference implementation to make it compatible or testable), you **must create a patch file**.
  - Make your changes in `ref/gimp`.
  - Run `git diff path/to/changed/file > my-change.patch` from the `ref/gimp` directory (or adjusted path).
  - Save the patch file in the project root.
  - Submit the patch file.
