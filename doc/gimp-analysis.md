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

## Core Models

Based on analysis of `app/core/`, here are the fundamental data structures representing an image in GIMP.

### Class Hierarchy
GIMP uses GObject for its core types. The hierarchy is deeper than expected, with `GimpItem` inheriting from `GimpFilter`.

*   **`GimpObject`**: Base class for most GIMP types.
    *   **`GimpViewable`**: Base for objects that can be previewed/displayed (Images, items, etc.).
        *   **`GimpImage`**: The top-level container.
        *   **`GimpFilter`**: Base for objects that filter/process (graph-node based).
            *   **`GimpItem`**: Base for items within an image (layers, channels, vectors).
                *   **`GimpDrawable`**: Base for pixel-based items (things you can draw on).
                    *   **`GimpLayer`**: A layer in the image stack.

### Key Structures

#### `GimpImage`
*   **Location**: [`app/core/gimpimage.h`](../ref/gimp/app/core/gimpimage.h)
*   **Role**: represents an open image document.
*   **Key Fields** (from structure definition):
    *   `layers`, `channels`, `vectors` (via `GimpItemTree` or `GimpContainer` accessors in the API).
    *   `width`, `height`.
    *   `gimp` (backlink to the global application instance).

#### `GimpLayer`
*   **Location**: [`app/core/gimplayer.h`](../ref/gimp/app/core/gimplayer.h)
*   **Role**: A single layer.
*   **Key Fields**:
    *   `opacity`, `mode` (blend mode).
    *   `mask` (Layer mask).
    *   `lock_alpha`.

#### `GimpDrawable`
*   **Location**: [`app/core/gimpdrawable.h`](../ref/gimp/app/core/gimpdrawable.h)
*   **Role**: Abstract base for anything with pixels (Layers, Channels, Masks).

#### `GimpItem`
*   **Location**: [`app/core/gimpitem.h`](../ref/gimp/app/core/gimpitem.h)
*   **Role**: Abstract base for structural elements of an image (Layers, Channels, Vectors/Paths).
*   **Key Responsibilities**:
    *   Position and dimensions (`offset_x`, `offset_y`, `width`, `height`).
    *   Transformation methods (scale, rotate, flip).
    *   Visibility and locking.
    *   Attaching to a `GimpImage`.
