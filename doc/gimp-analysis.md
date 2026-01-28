# GIMP Application Structure Analysis

## Directory Structure

Based on an analysis of the GIMP source code in `ref/gimp` (specifically the 3.2.0-RC2+git version), the application is structured as follows:

### Root Level
- **`app/`**: This is the core application logic. It is the most important directory for understanding GIMP's internal workings.
- **`libgimp/`**: Libraries for writing GIMP plug-ins.
- **`plug-ins/`**: Standard plug-ins distributed with GIMP.
- **`modules/`**: Loadable modules (like color selectors and display filters).
- **`menus/`**: XML files defining the menu structure.
- **`devel-docs/`**: Developer documentation (useful for reference).
- **`tools/`**: Various utility scripts and tools.

### `app/` Directory Breakdown
The `app/` directory contains the core logic, further organized into:

- **`core/`**: The heart of GIMP. Defines the data model (Image, Layer, Channel, etc.). Crucial for US-003.
- **`gui/`**: High-level GUI setup.
- **`widgets/`**: Reusable custom GTK+ widgets used throughout GIMP.
- **`tools/`**: Implementation of GIMP tools (Paintbrush, Select, Transform, etc.). *Note: Distinct from the root-level `tools/` directory.*
- **`pdb/`**: Procedural Database. This allows scripts and plug-ins to call internal GIMP functions.
- **`operations/`**: GEGL operations integration. GIMP uses GEGL for graph-based image processing.
- **`paint/`**: Paint core logic (brushes, dynamics).
- **`text/`**: Text tool and rendering logic.
- **`display/`**: Code related to the image display window (canvas, shell).
- **`dialogs/`**: Implementations of various dockable dialogs and windows.

## Build System

GIMP uses **Meson** as its primary build system.

- **`meson.build`**: Found in the root and almost every subdirectory. These define the build targets, dependencies, and compilation options.
- **`meson_options.txt`**: Defines build configuration options (features to enable/disable).

To understand how a specific module is built or what its dependencies are, looking at the local `meson.build` file is the best approach.
