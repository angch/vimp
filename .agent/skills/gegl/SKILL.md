---
name: gegl
description: "Guidelines and patterns for using GEGL (Generic Graphics Library) in Vimp."
---

# GEGL Usage & Best Practices

## Exporting Images
- **Use `gegl:save`**: For generic image export (JPG, PNG, WEBP, etc.), use the `gegl:save` operation.
  - It automatically infers the format from the file extension.
  - Ideally, prefer `gegl:save` over `cairo_surface_write_to_png` because it handles color depth, metadata, and format delegation properly through Babl.

## Graph Construction
- **Node Chains**: Always ensure nodes are properly connected. If a node is added but not connected to the output (or a sink), it may not process.
- **Reference Counting**: GEGL nodes are GObjects. Release them when no longer needed if you are managing them manually, though often the graph manages child node lifecycles.
