# Doc Directory Instructions

## GIMP Codebase Analysis
- **Core Models Location**: GIMP's core data structures (Image, Layer, Item) are in `app/core/`.
- **Inheritance Hierarchy**:
  - `GimpImage` -> `GimpViewable` -> `GimpObject`
  - `GimpLayer` -> `GimpDrawable` -> `GimpItem` -> `GimpFilter` -> `GimpViewable` -> `GimpObject`
- **Key Files**: `gimpimage.h` and `gimplayer.h` are the primary definitions to look at.

## Architecture Analysis
- Place architecture decision records (ADRs) and technology evaluations in `doc/architecture-analysis/`.
- Use a consistent format: Goal, Criteria, Analysis, Selection.

## Cross-Platform Development
- **Cross-Compilation Constraint**: For GTK4 apps, compiler support (Zig/Rust) allows building binaries, but the *target libraries* (DLLs/Libs) must be manually provided/sysrooted.
- **Packaging Strategy**: Prefer Flatpak for Linux distribution as it handles environment consistency best across distributions.
