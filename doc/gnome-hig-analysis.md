# Gnome HIG Analysis for Vimp

## Introduction

This document summarizes the Gnome Human Interface Guidelines (HIG) with a focus on porting GIMP to a native Gnome experience (Vimp). It uses the [local mirror](../ref/gnome-hig/hig/index.html) as a reference.

## Application Layout

### Window Structure
*Reference: [Windows](../ref/gnome-hig/hig/patterns/containers/windows.html)*
- **Primary Window**: Vimp will use a single Primary Window by default (Single Window Mode).
- **Secondary Windows**: Preferences, About, and temporary dialogs should be secondary windows attached to the primary window.
- **Sizing**: The window must be resizable and adapt to smaller screens where possible, though GIMP needs significant screen real estate.

### Header Bars
*Reference: [Header Bars](../ref/gnome-hig/hig/patterns/containers/header-bars.html)*
- Replace the traditional title bar with a **Header Bar** (Client Side Decoration).
- **Controls**:
    - **Start (Left)**: Primary actions like "New Image", "Open".
    - **Center**: Title or View Switcher (if we implement different "Perspectives" like Edit/Organize).
    - **End (Right)**: Primary Menu (Hamburger), potentially window controls.
- **Tooltips**: All header bar buttons must have tooltips.

## Navigation & Controls

### Menus
*Reference: [Menus](../ref/gnome-hig/hig/patterns/controls/menus.html)*
- **Primary Menu** (Hamburger Icon):
    - Contains app-wide actions: Preferences, Keyboard Shortcuts, Help, About.
    - **Action**: Move "File -> Quit" and general settings here.
- **Secondary Menus**:
    - For specific tool settings or view options, use secondary menus or popovers.
- **Vimp Specific Challenge**: GIMP has hundreds of menu items (Filters, Tools, Layer ops). A simple Primary Menu isn't enough.
    - *Recommendation*: Keep a Menu Bar (File, Edit, Select...) below the Header Bar for deep functionality, OR implement a searchable **Command Palette** as a primary navigation method, reducing reliance on deep menus.

### Lists & Sidebars
- Use **Boxed Lists** for settings/preferences.
- Use **Sidebars** for Tool Options and Layer/Channel dialogues.

## Visual Style

### Icons
*Reference: [UI Icons](../ref/gnome-hig/hig/guidelines/ui-icons.html)*
- Use **Symbolic Icons** (monochrome, 16x16px base) for all UI elements.
- Avoid full-color icons in toolbars.
- Programmatically configurable colors should be used for tool states (e.g., active tool highlight).

### Typography
*Reference: [Typography](../ref/gnome-hig/hig/guidelines/typography.html)*
- Use standard style classes:
    - `.heading`, `.body`, `.caption`, `.title-1` etc.
- **Do not** hardcode font sizes.
- Use correct Unicode characters (e.g., `×` for dimensions, not `x`).

## Vimp Specific Adaptations

### The Canvas
- The main image area should be the focus.
- Avoid cluttering the header bar with too many tools.
- Consider a **Floating Toolbar** or specific **Utility Panes** for the main tools (Brush, Pencil, etc.) following the [Utility Panes](../ref/gnome-hig/hig/patterns/containers/utility-panes.html) pattern.

### Dialogs
- Convert GIMP's many dockable dialogs into **Utility Panes** or Sidebar tabs.
- Use **Modal Dialogs** only when immediate action/decision is required (e.g., "Save changes?").

## Accessibility
*Reference: [Accessibility](../ref/gnome-hig/hig/guidelines/accessibility.html)*
- **High Contrast**: Ensure UI elements are visible in high contrast mode.
- **Keyboard Navigation**: All functionality must be accessible via keyboard. GIMP is keyboard-heavy, so this aligns well, but we must ensure standard GTK focus handling is preserved.
- **Mnemonics**: Use mnemonics (underlined letters) in menus and dialogs.
