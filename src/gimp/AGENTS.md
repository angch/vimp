# src/gimp Agents Guide

## GTK Version Mismatch
The `ref/gimp` headers are based on GTK2/3, but Vimp uses GTK4.
- **Verification**: When `@cImport`ing GIMP headers for offset verification, you MUST mock types removed in GTK4 (e.g., `GtkMenu`, `GdkEventKey`) if they are referenced.
- **Mock Header**: Use `src/gimp/mock_gtk3.h` to provide these typedefs.

## Struct Layouts
Zig structs in this directory MUST match `ref/gimp` C memory layouts exactly.
- Use `extern struct`.
- Verify offsets using `src/test_hierarchy.zig`.
- Use `c.gint` / `c.gboolean` instead of `c.int` to ensure ABI match.
