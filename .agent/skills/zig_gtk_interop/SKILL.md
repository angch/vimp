---
name: zig_gtk_interop
description: Guidelines and patterns for Zig and GTK/C library interoperability
---

# Zig & GTK Interoperability

## Core Principles
- **Safety First**: Always validate C pointers and return codes. Use `std.debug.print` for errors in GUI context if throwing is not an option.
- **Conventions**: Use `@cImport` definitions from `src/c.zig` (or equivalent centralization).

## Memory Management
GTK and GEGL objects are reference-counted (GObject system).
- **Ownership**: When you own a reference and are done with it, you MUST release it.
  ```zig
  c.g_object_unref(obj);
  ```
- **Callbacks**: Be careful with signal callbacks; generally `user_data` can pass pointers to Zig structs. Ensure lifecycles match.

## Signals
Use `c.g_signal_connect_data` to connect signals to Zig functions.
- The callback must use the C calling convention:
  ```zig
  fn myCallback(...) callconv(.c) void { ... }
  ```
- Use `c.G_CALLBACK` macro equivalent or cast function pointers appropriately.

## Data Conversion & Formats

### Strings: Slices vs C-Strings
- **Zig Slices to C Strings**: When passing Zig string slices (e.g. from `std.mem.trim`) to C functions like `gtk_editable_set_text`, **ensure they are null-terminated**.
  - Zig slices are *not* guaranteed to have a null terminator at `slice.ptr + slice.len`.
  - Use `std.fmt.allocPrintZ` (or `allocPrintSentinel`) to create a temporary null-terminated string (Z-string) if needed before passing to C.

### Texture Formats
- **GDK to GEGL**: When using `gdk_texture_download` to extract bytes for GEGL, rely on `c.babl_format("cairo-ARGB32")` as the source format.
  - Rationale: GDK/Cairo often use **BGRA** memory layout on little-endian systems (typical desktop), whereas `R'G'B'A u8` expects RGBA order. Using the explicit Cairo format ensures correct channel mapping.
