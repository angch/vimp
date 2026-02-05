# Environment Limitations

This document lists known limitations of the current development and runtime environment for Vimp.

## GEGL Loaders & Operations
- **EPS/PostScript (`image/x-eps`)**:
  - The development environment lacks loaders for these formats.
  - UI filters exist, but `gegl:load` may fail with a warning unless proper delegates (e.g., Ghostscript) or plugins are installed on the host system.

- **Missing Operations**:
  - `gegl:color-to-alpha` appears to be missing or fails to load in the current environment (warns "using a passthrough op instead").
  - **Workaround**: Manual pixel manipulation is required for transparency effects where this operation would normally be used.
