# TODO.md

## High-Level Alignment

> Tracks alignment with design docs in `doc/`. Cross-reference when picking up tasks.

### Core Design Docs Status
- [x] `doc/gimp_gnome_hig_gap_analysis.md` - Header Bar, Adaptive Layouts, Save/Export Flow
- [x] `doc/gimp-feature-spec-gnome-hig.md` - Core user stories
- [ ] `doc/gimp-file-open-spec.md` - File open/import workflows
- [ ] `doc/ms_paint_spec.md` - Classic paint features
- [ ] `doc/gnome-hig-analysis.md` - GNOME HIG compliance

---

## GNOME HIG Compliance (from `gnome-hig-analysis.md`)

### Architecture (Completed)
- [x] Migrate to Libadwaita (AdwApplication)
- [x] Implement Header Bar (Hamburger Menu, Primary Actions)
- [x] Implement Adaptive Layouts (Collapsible Sidebar/Flap)
- [x] Implement Unified Save/Export Flow

### Navigation & Controls
- [ ] Implement Command Palette (searchable action interface)
- [ ] Add Tooltips to all Header Bar buttons

### Accessibility
- [ ] Ensure High Contrast mode support
- [ ] Verify keyboard navigation for all functionality
- [ ] Add Mnemonics (underlined letters) in menus and dialogs

---

## Canvas & Interaction (from `gimp-feature-spec-gnome-hig.md`)

### Canvas Navigation (Completed)
- [x] Implement Canvas Navigation (Zoom/Scroll)
- [x] Implement Empty State (Welcome Screen)
- [x] Implement Overlay Feedback (OSD)

### Canvas Navigation (Pending)
- [ ] Implement pinch-to-zoom gesture support
- [ ] Implement two-finger pan gesture support

### Tool Palette Improvements
- [ ] Implement Tool Grouping (popovers/long-press revealers)
- [ ] Implement Properties Sidebar (contextual tool options)

### Selection Feedback
- [ ] Implement HUD for live dimensions during selection/transform

---

## Paint & Drawing Tools

### Completed
- [x] Implement Brush Tool
- [x] Implement Pencil Tool (Hard edge painting)
- [x] Implement Airbrush Tool (Variable pressure)
- [x] Implement Eraser Tool
- [x] Implement Bucket Fill Tool

### From `ms_paint_spec.md`
- [x] Implement Pick Color Tool (Eyedropper)
- [ ] Implement Gradient Tool
- [ ] Implement Text Tool
- [ ] Implement Line Tool (Shift for constrained angles)
- [ ] Implement Curve Tool (click to bend)

### Shape Tools (from `ms_paint_spec.md`)
- [ ] Implement Rectangle Shape Tool
- [ ] Implement Ellipse Shape Tool
- [ ] Implement Rounded Rectangle Tool
- [ ] Implement Polygon Tool

---

## Selection Tools

### Completed
- [x] Implement Rectangle Select Tool
- [x] Implement Ellipse Select Tool

### From `ms_paint_spec.md` & `gimp-feature-spec-gnome-hig.md`
- [ ] Implement Free-Form Select Tool (Lasso)
- [ ] Implement Selection Mode toggle (Opaque/Transparent)
- [ ] Implement Marching Ants animation for selections

---

## Color Features

### Completed
- [x] Implement Color Selection (Foreground/Background)
- [x] Implement Brush Size Control

### From `gimp-feature-spec-gnome-hig.md`
- [ ] Implement Recent Colors persistence in color popover
- [ ] Implement GNOME standard color picker dialog

### From `ms_paint_spec.md`
- [ ] Implement Color Box palette (default colors)
- [ ] Implement Edit Colors dialog (RGB/HSL spectrum)

---

## Transformations

### Completed
- [x] Implement Unified Transform Tool
- [x] Implement Non-destructive preview

### From `ms_paint_spec.md`
- [x] Implement Flip Horizontal
- [x] Implement Flip Vertical
- [x] Implement Rotate by angle (90°, 180°, 270°)
- [ ] Implement Stretch/Skew dialog

---

## Filters & Effects (from `gimp-feature-spec-gnome-hig.md`)

### Completed
- [x] Implement Basic Blur Filters (Gaussian)
- [x] Implement On-Canvas Preview ("Split View")

### Blur Filters
- [ ] Implement Motion Blur
- [ ] Implement Pixelize/Mosaic

### Enhancement Filters
- [ ] Implement Unsharp Mask (Sharpen)
- [ ] Implement Noise Reduction
- [ ] Implement Red Eye Removal

### Artistic Filters
- [ ] Implement Ripple/Waves
- [ ] Implement Oilify
- [ ] Implement Drop Shadow

### Light & Shadow
- [ ] Implement Lighting Effects (Directional, Point, Spot)
- [ ] Implement Supernova/Flare effect

---

## Image Operations (from `ms_paint_spec.md`)

- [ ] Implement Invert Colors
- [ ] Implement Canvas Attributes dialog (Width/Height/Units)
- [ ] Implement Clear Image (Ctrl+Shift+N)

---

## View Features (from `ms_paint_spec.md`)

- [ ] Implement Pixel Grid (visible when zoomed in)
- [ ] Implement Thumbnail window (overview while zoomed)
- [ ] Implement View Bitmap (fullscreen preview)

---

## Layers

### Completed
- [x] Implement Layer Management (Visibility, Locks, Reordering)

---

## Undo/Redo System

### Completed
- [x] Design Command Pattern and History Management
- [x] Implement transaction logic (beginStroke/endStroke)
- [x] Implement PaintCommand (Snapshot strategy)
- [x] Implement LayerCommands
- [x] Implement SelectionCommands
- [x] Add Undo/Redo actions (Ctrl+Z, Ctrl+Y)
- [x] Implement Undo History Panel

---

## File Operations (from `gimp-file-open-spec.md`)

### Completed
- [x] Implement Basic File Open (Ctrl+O, Native Dialog)
- [x] Implement Open as Layers (Ctrl+Alt+O)
- [x] Implement Drag and Drop Open
- [x] Implement Welcome Screen (Recent Grid)
- [x] Implement Recent Files Persistence
- [x] Implement file type filtering
- [x] Implement PDF Import (Page Selection, Thumbnails)
- [x] Implement SVG Path Import
- [x] Implement Error Handling (Non-blocking Toasts)
- [x] Implement Real Thumbnails for Recent Files
- [x] Implement Open Location (URI)
- [x] Implement Raw Image Import
- [x] Implement "Open pages as separate images" for PDF

### Pending
- [ ] Implement Clipboard Detection for Open Location
- [x] Investigate/Implement Preview Pane in File Chooser
- [ ] Implement File Recovery/Salvage actions

### File Format Support (from `gimp-file-open-spec.md`)
> Check VIMP.md for currently supported formats.

**Native & Working:**
- [ ] XCF with full layer/channel/path support (currently basic)

**Professional & Exchange:**
- [ ] PSD (Adobe Photoshop) layer support
- [ ] OpenRaster (.ora) format
- [ ] OpenEXR (.exr) HDR format
- [ ] Radiance HDR (.hdr) format

**Specialized:**
- [ ] DDS texture format
- [ ] PostScript (.ps, .eps) import

---

## Meta Tasks

- [ ] Generate detailed TODOs from `doc/gimp-file-open-spec.md`
- [ ] Generate detailed TODOs from `doc/ms_paint_spec.md`
- [ ] Ensure colored icons for all tools

---

## Archive (Completed Wishlist Items)

<details>
<summary>Click to expand completed wishlist items</summary>

### Document Features
- [x] Search and document features in GIMP in markdown (GIMP.md)
- [x] Search and document features implemented in Vimp (VIMP.md)
- [x] Diff GIMP.md and VIMP.md and add to TODO.md

</details>
