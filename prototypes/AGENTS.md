# Prototypes

## Build Requirements
- Run `make install-deps` in the project root to install necessary libraries (gtk4, gtkmm-4.0) before attempting to build prototypes.
- Most prototypes use a simple `Makefile`.

## Rust Prototypes
- Located in `prototypes/rust-gtk4`.
- Use `cargo run` to build and run.

## Zig Prototypes
- Located in `prototypes/zig-gtk4`.
- Use `zig build` or `zig build run` to execute.
- Links directly to system `gtk4` via `linkSystemLibrary` (uses pkg-config).
- Uses direct C import (`@cImport`). All GTK types are raw C pointers (often `[*c]T` or `?*T`), requiring explicit `callconv(.c)` for callbacks and manual pointer handling.
- Build times are very fast: Cold ~3s, Warm ~0.1s.

