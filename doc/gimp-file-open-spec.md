# GIMP File Open Feature Specification (GNOME HIG Edition)

## 1. Access & Entry Points
* **Welcome Screen (Empty State)**
    * **Recent Grid:** Specific large thumbnails for the most recently opened documents displayed in the center of the window when no image is open.
    * **"Open" Action Button:** A prominent, suggested action button displayed in the empty state placeholder.
* **Global Shortcuts**
    * **Standard Shortcut:** `Ctrl + O` triggers the native file chooser dialog immediately.
    * **Open as Layers:** `Ctrl + Alt + O` triggers the chooser with the specific intent to insert the file into the current layer stack.

## 2. The File Chooser (Native GTK Integration)
* **Standard Navigation**
    * **Sidebar:** Quick access to "Recent", "Starred", "Home", and mounted external volumes.
    * **Search:** Type-ahead search functionality to filter files by name immediately.
    * **View Modes:** Toggle between List View (details) and Grid View (thumbnails).
* **Format Filtering**
    * **"All Supported Images":** Default filter showing only compatible file types to reduce clutter.
    * **Type Dropdown:** Allow users to enforce specific format parsing (e.g., "Select File Type (By Extension)" vs. forcing "Raw Image Data").
* **Preview Pane**
    * Display a high-resolution preview of the selected file within the chooser dialog before opening to confirm selection.

## 3. Import Workflows (Format-Specific)
* **PDF Import Dialog**
    * **Presentation:** Displayed as a modal dialog if a multi-page PDF is selected.
    * **Page Selection:** Clickable grid of page thumbnails to select which pages to import (Select All / Range).
    * **Open Mode:** Toggle switch for "Open pages as layers" vs. "Open pages as separate images".
    * **Resolution:** Spinbutton to define the import DPI (default to 300 for print, 72 for screen).
* **Raw Image Import**
    * Detect RAW formats (CR2, NEF) and seamlessly hand off to a delegate raw developer (Darktable/RawTherapee) if installed, or open a native adjustment dialog.
* **SVG (Vector) Import**
    * **Render Dimensions:** Dialog prompting for the target rasterization size (Width/Height) or scale ratio.
    * **Path Import:** Option to import paths directly rather than rasterizing the image.

## 4. "Open Location" (URI)
* **Header Bar Entry:** Accessible via the application menu or a dedicated "Open Location" dialog.
* **Protocol Support:** Direct support for `http://`, `https://`, `ftp://`, and `smb://` to fetch images directly from the web or network shares.
* **Clipboard Detection:** If a URL is on the clipboard, pre-fill the entry field.

## 5. Drag and Drop Interaction
* **Canvas Drop Zones**
    * **Empty Canvas:** Dropping a file creates a new project.
    * **Existing Canvas:** Dropping a file displays an overlay offering to "Add as New Layer" or "Open as New Image".
* **Tab Bar Drop:** Dropping a file onto the tab bar (if multiple images are open) opens it as a distinct new tab.

## 6. Error Handling & Feedback
* **Non-Blocking Toasts:** If a file fails to open (corruption, unsupported format), display a toast notification at the bottom of the window ("Could not open 'image.jpg'") rather than a modal error popup that requires clicking "OK".
* **Recovery:** For partially corrupted files, offer a distinct "Try to salvage data" action bar if the loader supports partial reading.

## 7. Supported File Formats
* **Native & Working Formats**
    * **XCF (`.xcf`, `.xcfbz2`, `.xcfgz`):** GIMP's native format supporting all layer, channel, path, and selection data.
* **Common Web & Display**
    * **JPEG (`.jpg`, `.jpeg`, `.jpe`):** Standard photographic format.
    * **PNG (`.png`):** Lossless raster format with alpha transparency support.
    * **GIF (`.gif`):** Indexed color format; supports importing animation frames as layers.
    * **WebP (`.webp`) & AVIF (`.avif`):** Modern web formats supporting high compression and transparency.
* **Professional & Exchange**
    * **TIFF (`.tif`, `.tiff`):** High-quality format supporting layers and 16/32-bit floating point depth.
    * **PSD (`.psd`):** Adobe Photoshop documents (Layer support is attempted but may be limited).
    * **OpenRaster (`.ora`):** Open interchange format for preserving layers between open-source apps.
    * **PDF (`.pdf`):** Portable Document Format (Imported as raster layers).
* **Raw & HDR**
    * **Raw Photo Data:** (via plugins like Darktable/RawTherapee) `.cr2`, `.nef`, `.arw`, `.dng`, `.orf`, etc.
    * **OpenEXR (`.exr`) & Radiance HDR (`.hdr`):** High Dynamic Range imaging formats.
* **Specialized & Legacy**
    * **Vector:** SVG (`.svg`), PostScript (`.ps`, `.eps`).
    * **Icon:** Microsoft ICO (`.ico`), BMP (`.bmp`).
    * **Texture:** DDS (`.dds`), TGA (`.tga`).
    * **Legacy:** PCX, PIX, SGI, XPM, Sun Raster.
