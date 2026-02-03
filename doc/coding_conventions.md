# Coding Conventions

## Naming
- **Vimp vs GIMP**: We are making something that is feature compatible, we are not replacing GIMP. Avoid variables or references with "GIMP" in the codebase (e.g., use `VimpTool` instead of `GimpTool`).
- **Bindings**: The directory `src/vimp/` contains structures that mirror GIMP's memory layout for verification, but they should be named `Vimp...`.

## Zig & C Interop
- **Safety**: Always validate C pointers and return codes. Use `std.debug.print` for errors in GUI context if throwing is not an option.
- **Memory Management**: GTK/GEGL objects are reference-counted.
  - Use `c.g_object_unref(obj)` when you own a reference and are done with it.
  - Be careful with signal callbacks; generally `user_data` can pass pointers to Zig structs.
- **Signals**: Use `c.g_signal_connect_data` to connect signals to Zig functions. The callback must have `callconv(std.builtin.CallingConvention.c)` or `callconv(.c)`.
