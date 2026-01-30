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

## LibAdwaita / Gnome HIG
- **Rust**: Requires strict version coupling between `gtk4` and `libadwaita` crates (e.g. `gtk4 0.9` -> `libadwaita 0.7`). Mixing major/minor versions causes sys-crate linking conflicts.
- **Zig**: Requires explicit linking of `adwaita-1` system library (`exe.linkSystemLibrary("adwaita-1")`) and usage of `@cInclude("adwaita.h")`. Ensures access to `libadwaita-1-dev` headers.

## Asset Management
- **Icons**: Generated icons are placed in `assets/` directory.
- **Loading**: `gtk_image_new_from_file` works with relative paths (e.g., "assets/brush.png") assuming the binary is executed from the project root.
