# TODO.md

## High-Level Alignment

> Tracks alignment with design docs in `doc/`. Cross-reference when picking up tasks.

### Core Design Docs Status
- [ ] `doc/gimp-file-open-spec.md` - File open/import workflows
- [ ] `doc/ms_paint_spec.md` - Classic paint features
- [ ] `doc/gnome-hig-analysis.md` - GNOME HIG compliance

---

## GNOME HIG Compliance (from `gnome-hig-analysis.md`)

### Accessibility
- [x] Ensure High Contrast mode support
- [x] Verify keyboard navigation for all functionality
- [x] Fix missing mnemonics in Filter Dialogs

---

## GIMP File Open Implementation (from `doc/gimp-file-open-spec.md`)

### 1. Access & Entry Points
- [x] **Welcome Screen Recent Grid:** Implement specific large thumbnails grid view (currently list view).
- [x] **"Open" Action Button**
- [x] **Shortcuts:** `Ctrl+O` and `Ctrl+Alt+O`.

### 2. The File Chooser
- [x] **Standard Navigation** (Native GTK)
- [x] **Format Filtering** ("All Supported Images", specific filters)
- [x] **Preview Pane** (Implemented via `GtkPicture`)

### 3. Import Workflows
- [x] **PDF Import Dialog** (Page selection, resolution)
- [ ] **PDF Import:** Support opening multiple pages as separate images (currently warning/reset).
- [x] **Raw Image Import** (Darktable/RawTherapee delegate)
- [x] **SVG Import** (Dimensions dialog)

### 4. "Open Location" (URI)
- [x] **Header Bar Entry / Dialog**
- [x] **Protocol Support** (http/https via curl)
- [ ] **Clipboard Detection** (Pre-fill URL in Open Location dialog)

### 5. Drag and Drop
- [x] **Canvas Drop Zones** (New vs Layer dialog implemented)
- [x] **Tab Bar Drop** (Implicit via New Image flow).

### 6. Error Handling
- [x] **Non-Blocking Toasts**
- [x] **Recovery / Salvage**

### 7. File Format Support
**Native & Working:**
- [ ] **XCF:** Full layer/channel/path support (currently basic flattened load).

**Professional & Exchange:**
- [x] PSD, OpenRaster, OpenEXR, Radiance HDR, PDF.
- [x] Generic Export (gegl:save).

**Specialized:**
- [x] DDS, Raw, Legacy (PCX, etc).

---

## MS Paint Classic Features (from `doc/ms_paint_spec.md`)

### Toolbox
- [x] **Selection Tools:** Free-Form (Lasso), Select (Rect).
- [x] **Eraser:** With right-click color replacement.
- [x] **Fill With Color** (Bucket).
- [x] **Pick Color** (Eyedropper).
- [x] **Magnifier** (Zoom tool/shortcuts).
- [x] **Drawing:** Pencil, Brush, Airbrush.
- [x] **Text:** Insert text (basic layer support).
- [x] **Shapes:** Line, Curve, Rect, Polygon, Ellipse, Rounded Rect.

### Selection Options
- [x] **Transparent Selection** (Toggle implemented).

### Image Menu Operations
- [x] **Flip/Rotate:** Flip H/V, Rotate 90/180/270.
- [x] **Stretch/Skew:** Dialog implemented.
- [x] **Invert Colors**
- [x] **Attributes:** Canvas Size dialog.
- [x] **Clear Image**
- [x] **Draw Opaque:** Toggle for text box transparency (Text tool feature).

### View Options
- [x] **Zoom:** Custom levels.
- [x] **Show Grid:** Toggle menu item (Logic exists in `drawPixelGrid`, needs UI toggle).
- [x] **Show Thumbnail**
- [x] **View Bitmap** (Fullscreen).

### Colors
- [x] **Color Box** (Palette).
- [x] **Edit Colors** (Dialog).

---

## Archive (Completed Wishlist Items)

<details>
<summary>Click to expand completed wishlist items</summary>

### Tools
- [x] Airbrush: Implement spray-can effect (random scattering)
- [x] Transparent Selection: Implement preview and commit logic (manual pixel manipulation fallback)

### Document Features

</details>
