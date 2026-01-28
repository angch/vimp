# Vimp

Vimp is a learning project to attempt to use agentic coding to come up with a new GIMP-like application
with these extra features:

    - upgrade an existing GTK3 app to GTK4
    - comply with Gnome HIG https://developer.gnome.org/hig/

## Technology Stack Decision

After an architectural analysis (see `doc/architecture-analysis/`), we have selected:
- **Language:** [Zig](https://ziglang.org/)
- **GUI Toolkit:** GTK4 (via direct C interop)

**Why Zig?**
Vimp aims to eventually leverage the massive existing C ecosystem of GIMP (GEGL, babl, libgimp). Zig's unique `guaranteed C ABI compatibility` and `@cImport` features allow us to mix new modern code with legacy C libraries without the friction of writing language bindings or FFI wrappers. It offers the performance of C with safer, more modern ergonomics.
