# TODO.md

## Wishlist

### Document features from GIMP

- [x] Search and document features in GIMP in markdown. (GIMP.md)

### Document implemented features in Vimp

- [x] Search and document features in that has been implemented in markdown (VIMP.md)

### Implement missing features in Vimp from GIMP

- [x] Diff GIMP.md and VIMP.md and add to TODO.md in medium priority.

### Alignment

- [x] Check and update the TODOs here ensuring that we are on the way towards alignment as described in `doc/gimp_gnome_hig_gap_analysis.md`
- [x] Check and update the TODOs here ensuring that we are on the way towards the user stories as described in `doc/gimp-feature-spec-gnome-hig.md`

### Alignment (GNOME HIG)

- [x] Migrate to Libadwaita (AdwApplication) for modern styling <!-- id: 3 -->
- [x] Implement fully functional Header Bar (Hamburger Menu, Primary Actions)
- [x] Implement Adaptive Layouts (Collapsible Sidebar/Flap)
- [x] Implement Unified Save/Export Flow

### Spec Integration

- [ ] Read and generate TODOs from doc/gimp-file-open-spec.md

## Higher priority

- [x] Ensure there is colored icons for all tools

## Medium priority

- [x] Implement Color Selection (Foreground/Background colors)
- [x] Implement Brush Size Control

- [x] Implement Eraser Tool
- [x] Implement Canvas Navigation (Zoom/Scroll)

## Planned Features

### Undo/Redo System
- [x] Design Command Pattern and History Management in `src/engine.zig`
- [x] Implement `beginStroke` / `endStroke` transaction logic in `Engine` for grouping actions
- [x] Integrate `drag_begin` / `drag_end` in `src/main.zig` with Engine transactions
- [x] Implement `PaintCommand` (Snapshot strategy for undoing pixel changes)
- [x] Implement `BucketFillCommand` (Covered by PaintCommand)
- [x] Implement `LayerCommand`s (Add, Remove, Reorder, Visibility, Lock)
- [x] Implement `SelectionCommand`s
- [x] Add Undo/Redo actions (Ctrl+Z, Ctrl+Y) and UI buttons in `src/main.zig`

### Paint Tools
- [x] Implement Pencil Tool (Hard edge painting)
- [x] Implement Airbrush Tool (Variable pressure)
- [x] Implement Bucket Fill Tool

### Selection Tools
- [x] Implement Rectangle Select Tool
- [x] Implement Ellipse Select Tool

### Layers
- [x] Implement Layer Management (Visibility, Locks, Reordering)

### Transformations
- [x] Implement Unified Transform Tool

### Filters
- [x] Implement Basic Blur Filters (Gaussian)
- [x] Implement On-Canvas Preview ("Split View")

### UI Improvements
- [x] Implement Empty State for Canvas
- [x] Implement Overlay Feedback (OSD)
- [x] Implement Undo History Panel

