# GIMP Feature Specification (GNOME HIG Edition)

## 1. Application Architecture & Navigation
* **Primary Window**
    * **Header Bar:** Consolidate window title, window controls, and global actions (New, Open, Save, Menu) into a single top bar to maximize vertical screen space for the canvas.
    * **Application Menu (Hamburger):** Place secondary and less frequently used actions (Preferences, Help, About) in the primary menu at the end of the Header Bar.
    * **Single-Window Mode:** Enforce a unified window container for all panels and the canvas to prevent window clutter.
* **Canvas Interaction**
    * **Empty State:** Display a welcoming "No Image Open" status with explicit action buttons ("Create New Image", "Open Existing...") when the canvas is empty.
    * **Zoom & Pan:** Support pinch-to-zoom and two-finger pan gestures on touchpads/touchscreens for fluid navigation.
    * **Overlay Feedback:** Display transient, semi-transparent overlays (OSD) for zoom levels or tool changes to maintain focus on content.

## 2. Panels & Sidebars
* **Tool Palette (Sidebar)**
    * Organize tools into a consistent grid or list within a collapsible sidebar.
    * **Tool Grouping:** Use popovers or long-press revealers to group related tools (e.g., grouping all selection tools) to reduce visual noise.
* **Properties Sidebar**
    * Contextually display options for the currently selected tool (e.g., Brush Size, Opacity) in a dedicated sidebar pane.
    * Use standard GNOME controls: Sliders for ranges (Opacity), Spinbuttons for precise values (Size), and Toggle Buttons for boolean states.
* **Layer Management (List Box)**
    * Present layers as a rich list box.
    * **Row Actions:** Include inline toggle icons for "Visibility" (Eye) and "Lock" within each row.
    * **Drag-and-Drop:** Allow reordering rows via direct manipulation.
    * **Selection Mode:** Support multi-row selection for group operations.

## 3. Selection & Manipulation
* **Direct Manipulation**
    * Render selection bounds (marching ants) immediately upon interaction.
    * **Handles:** Specific tools (Crop, Perspective) should spawn on-canvas handles for resizing and shaping, rather than relying solely on numeric input dialogs.
* **Heads-Up Display (HUD)**
    * When manipulating a selection (e.g., resizing), display a small, floating tooltip near the cursor showing live dimensions ($W \times H$) to provide immediate context without eye movement.

## 4. Creation & Editing Tools
* **Drawing Interaction**
    * **Pointer Precision:** Ensure cursor icons accurately reflect the active tool and brush size outline.
    * **Pressure Sensitivity:** Map stylus pressure to opacity or size seamlessly without requiring modal configuration.
* **Color Selection**
    * **Color Popover:** Use the standard GNOME color picker dialog/popover, featuring a palette, spectrum, and hex entry field.
    * **Recent Colors:** Persist a row of recently used colors within the popover.

## 5. Transformations
* **Unified Transform Tool**
    * Combine Scale, Rotate, and Shear into one interaction model to reduce tool switching.
    * **Apply/Cancel:** Use a floating action bar or an overlay overlay within the viewport to "Confirm" or "Cancel" the transformation, avoiding modal dialog blocking.
* **Non-Destructive Preview:** Render a live preview of the transformation (Rotate, Scale) on the canvas in real-time before committing the pixel changes.

## 6. Filters & Effects
* **Interaction Model**
    * **On-Canvas Preview:** All filters must render a live preview ("Split View" toggle supported) directly on the canvas before applying.
    * **Non-Blocking Dialogs:** Filter settings should appear in a dialog or sidebar that allows the user to pan/zoom the canvas while adjusting parameters.
* **Blur Filters**
    * **Gaussian Blur:** Standard blur with X/Y radius linking.
    * **Motion Blur:** Directional blur with angle and length controls.
    * **Pixelize:** Group pixels into large blocks to simulate low resolution.
* **Enhancement Filters**
    * **Unsharp Mask:** Sharpen edges by increasing contrast along boundaries.
    * **Noise Reduction:** Smooth out graininess while preserving edges.
    * **Red Eye Removal:** Automatic detection and correction of flash reflection.
* **Artistic & Distort**
    * **Ripple/Waves:** Displace pixels in a wave pattern with amplitude and period controls.
    * **Oilify:** Smear pixels to simulate an oil painting texture.
    * **Drop Shadow:** Generate a shadow layer behind the current selection with offset, blur radius, and color controls.
* **Light & Shadow**
    * **Lighting Effects:** Simulate a 3D light source (Directional, Point, Spot) shining on the image.
    * **Supernova:** Create a starburst flare effect centered on a user-chosen point.

## 7. Color Adjustment
* **Live Previews**
    * When a dialog (e.g., Levels, Gaussian Blur) is open, automatically apply the effect to the canvas behind the dialog ("Split View" option preferred to compare Before/After).
* **Dialog Design**
    * Use non-modal windows or sidebar panels for complex adjustments (Curves, Levels) so users can interact with the canvas zoom/pan while adjusting parameters.
    * **Cancel/Apply:** Follow standard GNOME dialog button order (Cancel on left, Affirmative action on right).

## 8. History & Undo
* **System Notifications**
    * Use standard in-app notifications (toasts) for feedback on background operations ("Export Complete").
* **Undo History**
    * Present history as a timeline list. Allow clicking a previous state to revert instantly.

## 9. File Operations
* **Native File Chooser:** Integrate the standard GTK file chooser for Open/Save operations.
* **Export Popover:** For quick exports, use a streamlined popover or dialog focusing on format selection and quality, with "Advanced Options" hidden behind a revealer to keep the interface simple.
