# Doc Directory Instructions

## GIMP Codebase Analysis
- **Core Models Location**: GIMP's core data structures (Image, Layer, Item) are in `app/core/`.
- **Inheritance Hierarchy**:
  - `GimpImage` -> `GimpViewable` -> `GimpObject`
  - `GimpLayer` -> `GimpDrawable` -> `GimpItem` -> `GimpFilter` -> `GimpViewable` -> `GimpObject`
- **Key Files**: `gimpimage.h` and `gimplayer.h` are the primary definitions to look at.
