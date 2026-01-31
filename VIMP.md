# Vimp Implemented Features

This document provides a list of features currently implemented in Vimp.

## Application Infrastructure (`src/main.zig`, `src/engine.zig`)

### UI Framework
- **GTK4 Integration**: Main application window using GTK4.
- **Layout**: 
  - Header bar with Hamburger Menu and Primary Actions.
  - Two-pane layout: Sidebar (Left, Collapsible) and Main Content (Right).
  - Overlay Feedback (OSD) for tools and zoom.
- **CSS Styling**: Basic support for CSS styling of UI components.
- **Dialogs**: Native file dialogs for Open/Save.

### Rendering Engine (`src/engine.zig`)
- **GEGL Integration**: Uses GEGL as the underlying graph-based image processing engine.
- **Graph Pipeline**:
  - **Layers**: Dynamic layer stack (Add, Remove, Reorder, Visibility, Lock).
  - **Compositing**: `gegl:over` node chain.
  - **Preview**: Split-view and destructive previews for filters/transforms.
- **Display**: Blits the GEGL output to a Cairo surface for rendering in `GtkDrawingArea`.

## Tools

### Paint Tools
- **Brush**: Standard painting.
- **Pencil**: Hard-edge painting.
- **Airbrush**: Pressure-sensitive painting (simulated).
- **Eraser**: Erases to transparency.
- **Bucket Fill**: Flood fill with color (dirty-rect optimized).

### Selection Tools
- **Rectangle Select**: Rectangular selection region.
- **Ellipse Select**: Elliptical selection region.
- **Behavior**: Clips paint and fill operations to the selection.

### Transform Tools
- **Unified Transform**: Scale, Rotate, and Translate layers with live preview.

## File Operations
- **New Image**: Creates a new canvas with a "Background" layer (`Ctrl+N`).
- **Open Image**: Loads an image file into a new layer (`Ctrl+O`).
  - **Supported Formats**: PNG, JPG/JPEG, WebP, GIF, TIFF, BMP, AVIF, ICO, TGA, XCF.
- **Save**: Saves the current canvas view to a PNG file (`Ctrl+S`).

## History
- **Undo/Redo**: Command-pattern based system supporting:
  - Paint strokes
  - Layer operations
  - Selection changes
  - Transformations
- **UI**: Undo History panel in the sidebar.
