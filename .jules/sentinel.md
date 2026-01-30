## 2026-02-05 - Cairo/GEGL NULL Pointer Vulnerability
**Vulnerability:** `cairo_image_surface_create` returns a valid pointer to an error surface on failure, but `cairo_image_surface_get_data` returns `NULL` for such surfaces. Passing this `NULL` to `gegl_node_blit` (via C interop) causes a segmentation fault (DoS).
**Learning:** Zig's C-interop does not automatically check for library-specific error states (like Cairo's status vs NULL return). The assumption that "non-null surface pointer means valid surface" was false.
**Prevention:** Explicitly check `cairo_surface_status(s) == CAIRO_STATUS_SUCCESS` immediately after creation and before data access. Treat `NULL` data return as a critical error.
