# Project History

## High-Level Alignment
### Core Design Docs Status
- `doc/gimp_gnome_hig_gap_analysis.md` - Header Bar, Adaptive Layouts, Save/Export Flow
- `doc/gimp-feature-spec-gnome-hig.md` - Core user stories

## GNOME HIG Compliance (from `gnome-hig-analysis.md`)
### Architecture (Completed)
- Migrate to Libadwaita (AdwApplication)
- Implement Header Bar (Hamburger Menu, Primary Actions)
- Implement Adaptive Layouts (Collapsible Sidebar/Flap)
- Implement Unified Save/Export Flow
### Navigation & Controls
- Implement Command Palette (searchable action interface)
- Add Tooltips to all Header Bar buttons
### Accessibility
- Add Mnemonics (underlined letters) in menus and dialogs
- Implement High Contrast mode support
- Verify keyboard navigation for all functionality

## Canvas & Interaction (from `gimp-feature-spec-gnome-hig.md`)
### Canvas Navigation (Completed)
- Implement Canvas Navigation (Zoom/Scroll)
- Implement Empty State (Welcome Screen)
- Implement Overlay Feedback (OSD)

## Paint & Drawing Tools
### Completed
- Implement Brush Tool
- Implement Pencil Tool (Hard edge painting)
- Implement Airbrush Tool (Variable pressure)
- Implement Eraser Tool (with right-click color replacement)
- Implement Bucket Fill Tool
- Implement Draw Opaque toggle for Text Tool
### From `ms_paint_spec.md`
- Implement Pick Color Tool (Eyedropper)
- Implement Gradient Tool
- Implement Text Tool
- Implement Line Tool (Shift for constrained angles)
- Implement Curve Tool (click to bend)
### Shape Tools (from `ms_paint_spec.md`)
- Implement Rectangle Shape Tool
- Implement Ellipse Shape Tool
- Implement Rounded Rectangle Tool
- Implement Polygon Tool

## Selection Tools
### Completed
- Implement Rectangle Select Tool
- Implement Ellipse Select Tool
### From `ms_paint_spec.md` & `gimp-feature-spec-gnome-hig.md`
- Implement Free-Form Select Tool (Lasso)
- Implement Selection Mode toggle (Opaque/Transparent)
- Implement Marching Ants animation for selections

## Color Features
### Completed
- Implement Color Selection (Foreground/Background)
- Implement Brush Size Control
### From `gimp-feature-spec-gnome-hig.md`
- Implement Recent Colors persistence in color popover
- Implement GNOME standard color picker dialog
### From `ms_paint_spec.md`
- Implement Color Box palette (default colors)
- Implement Edit Colors dialog (RGB/HSL spectrum)

## Transformations
### Completed
- Implement Unified Transform Tool
- Implement Non-destructive preview
### From `ms_paint_spec.md`
- Implement Flip Horizontal
- Implement Flip Vertical
- Implement Rotate by angle (90°, 180°, 270°)
- Implement Stretch/Skew dialog

## Filters & Effects (from `gimp-feature-spec-gnome-hig.md`)
### Completed
- Implement Basic Blur Filters (Gaussian)
- Implement On-Canvas Preview ("Split View")
### Blur Filters
- Implement Motion Blur
- Implement Pixelize/Mosaic
### Enhancement Filters
- Implement Unsharp Mask (Sharpen)
- Implement Noise Reduction
- Implement Red Eye Removal
### Artistic Filters
- Implement Ripple/Waves
- Implement Oilify
- Implement Drop Shadow
### Light & Shadow
- Implement Lighting Effects (Directional, Point, Spot)
- Implement Supernova/Flare effect

## Image Operations (from `ms_paint_spec.md`)
- Implement Invert Colors
- Implement Canvas Attributes dialog (Width/Height/Units)
- Implement Clear Image (Ctrl+Shift+N)

## View Features (from `ms_paint_spec.md`)
- Implement Pixel Grid (visible when zoomed in)
- Implement Thumbnail window (overview while zoomed)
- Implement View Bitmap (fullscreen preview)

## Layers
### Completed
- Implement Layer Management (Visibility, Locks, Reordering)

## Undo/Redo System
### Completed
- Design Command Pattern and History Management
- Implement transaction logic (beginStroke/endStroke)
- Implement PaintCommand (Snapshot strategy)
- Implement LayerCommands
- Implement SelectionCommands
- Add Undo/Redo actions (Ctrl+Z, Ctrl+Y)
- Implement Undo History Panel

## File Operations (from `gimp-file-open-spec.md`)
### Completed
- Implement Basic File Open (Ctrl+O, Native Dialog)
- Implement Open as Layers (Ctrl+Alt+O)
- Implement Drag and Drop Open
- Implement Welcome Screen (Recent Grid)
- Implement Recent Files Persistence
- Implement file type filtering
- Implement PDF Import (Page Selection, Thumbnails)
- Implement SVG Path Import
- Implement Error Handling (Non-blocking Toasts)
- Implement Real Thumbnails for Recent Files
- Implement Open Location (URI)
- Implement Raw Image Import
- Implement "Open pages as separate images" for PDF
- Implement Clipboard Detection for Open Location
- Implement Preview Pane in File Chooser
- Implement Recovery / Salvage for failed loads
- Implement Extended File Format Support (PSD, ORA, EXR, HDR, DDS, PCX, etc)

## Meta Tasks
- Implement Right-Click (Secondary Color) support for Paint Tools
- Ensure colored icons for all tools
- Embed assets/resources into binary
- Fix failing Engine PDF load test

## Archive (Completed Wishlist Items)
### Document Features
- Search and document features in GIMP in markdown (GIMP.md)
- Search and document features implemented in Vimp (VIMP.md)
- Diff GIMP.md and VIMP.md and add to TODO.md
