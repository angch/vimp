# Vimp Implemented Features

This document provides a list of features currently implemented in Vimp.

## Application Infrastructure (`src/main.zig`, `src/engine.zig`)

### UI Framework
- **GTK4 Integration**: Main application window using GTK4.
- **Layout**: 
  - Header bar
  - Two-pane layout: Sidebar (Left) and Main Content (Right).
- **CSS Styling**: Basic support for CSS styling of UI components.

### Rendering Engine (`src/engine.zig`)
- **GEGL Integration**: Uses GEGL as the underlying graph-based image processing engine.
- **Graph Pipeline**:
  - **Background**: Solid color background (RGB 0.9, 0.9, 0.9).
  - **Canvas**: Fixed 800x600 canvas size via crop node.
  - **Compositing**: Overlays a transparent paint buffer on top of the background.
- **Display**: Blits the GEGL output to a Cairo surface for rendering in `GtkDrawingArea`.

## Tools

### Paint Tools
- **Basic Brush**: 
  - **Type**: Simple pixel-based drawing.
  - **Shape**: Square brush (3x3 pixels).
  - **Color**: Black (Fixed).
  - **Input**: Mouse drag gestures via `GtkGestureDrag`.
  - **Interpolation**: Linear interpolation between events to prevent gaps (line drawing).
