
# GIMP Codebase Analysis

## Directory Structure Overview

The GIMP codebase is organized into several top-level directories. For the purpose of porting logic to Vimp, the most relevant are:

- **APP (`app/`)**: This is where the main application logic resides. It is further subdivided into:
    - **`core/`**: The heart of the application. Contains the data models for Images, Layers, Channels, and the Undo system.
    - **`gegl/`**: Code related to the integration with the GEGL image processing graph.
    - **`widgets/`**: GTK widgets specific to GIMP's UI.
    - **`gui/`**: High-level GUI assembly.
    - **`actions/`**: Action definitions (likely GAction/GCommand equivalents).
    - **`pdb/`**: The Procedural DataBase (internal API for scripting/plugins).

- **LIBGIMP (`libgimp*`)**: These libraries (libgimp, libgimpbase, libgimpcolor, etc.) provide the API for plugins. They are less about the core app logic and more about the interface exposed to extensions.

- **MODULES (`modules/`)**: Loadable modules (like color selectors).

- **PLUG-INS (`plug-ins/`)**: The source code for standard plugins distributed with GIMP.

## Core Data Models

### GimpImage (`app/core/gimpimage.c|h`)

`GimpImage` is the central object representing an open image project. It inherits from `GimpViewable`.

**Key Attributes (from `GimpImagePrivate`):**
- **Dimensions**: `width`, `height`.
- **Items**:
    - `GimpItemTree *layers`: A tree structure managing layers (handling groups).
    - `GimpItemTree *channels`: A tree structure for channels.
    - `GimpItemTree *paths`: A tree structure for vector paths.
- **GEGL Graph**: `GeglNode *graph`. GIMP 2.10+ relies heavily on GEGL. The image maintains a GEGL graph that represents the composition of layers.
- **Files**: Stores references to `GFile` for import/export locations.
- **Undo/Redo**: `GimpUndoStack *undo_stack`.

### GimpLayer (`app/core/gimplayer.c|h`)

Represents a single layer. Inherits from `GimpDrawable` (which implies it has pixels/buffers).

**Key Aspects:**
- Layers are nodes in the `GimpItemTree`.
- They have modes (blending modes), opacity, and visibility.
- Actual pixel data is likely managed via `GeglBuffer` (referenced in `GimpDrawable` or related structures).

### GimpItemTree

GIMP uses a tree structure to manage layers, enabling nested layer groups. This is a critical feature to port correctly.

## Porting Considerations for Vimp

1.  **GEGL Dependency**: GIMP is essentially a UI wrapper around a GEGL graph. A successful port or modern "copy" (Vimp) must verify if it intends to use GEGL or its own compositing engine. If using GEGL, the `GimpImage` -> `GeglNode` relationship is the most critical to replicate.
2.  **Object System**: GIMP uses GObject heavily (`GimpImage`, `GimpItem`, etc.). Vimp (assuming Go/Rust/GTK4) will need to map these to native structs, likely without the GObject boilerplate unless using bindings.
3.  **Separation of Core and UI**: The `app/core` vs `app/widgets` separation is clean. Vimp should emulate this by keeping the Image Model strictly separate from the GTK4 Views.

## Next Steps for Deep Dive

- Analyze `gimp-gegl.c` to understand how the graph is constructed.
- Look at `app/actions` to see how user commands are dispatched to the Core model.
