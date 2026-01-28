# GIMP GTK3 Usage & GTK4 Porting Analysis

## Executive Summary
GIMP 3.0 (imminent release) completes the long-awaited port to GTK3. The GIMP team has explicitly deferred GTK4 migration until after GIMP 3.0/3.2 due to the sheer complexity and breaking changes in GTK4. Porting "Vimp" (a potential fork/rewrite) to GTK4 immediately presents both a high-risk challenge and a high-reward opportunity to leapfrog legacy tech debt.

## GIMP's Current Architecture (GTK3)
*   **Legacy Roots:** Despite the GTK3 port, the codebase retains significant structural patterns from GTK2 (and even GTK1), including custom widget subclassing that doesn't align with modern GTK composition patterns.
*   **Custom Widgets:** GIMP relies heavily on a massive library of custom widgets (`libgimpwidgets`) which are tightly coupled to GTK3 APIs.
*   **Rendering:** GIMP 3.0 introduces better GEGL integration, but the UI rendering is still largely traditional GTK3 (Cairo-based in many places) rather than the GPU-accelerated node graph of GTK4.

## GTK4 Porting Challenges
1.  **Breaking API Changes:** GTK4 is not source-compatible with GTK3. It requires a significant rewrite, not just a "port".
    *   Removal of `GtkContainer` (replaced by strict parent-child inclusions).
    *   Event controllers replacing signal-based event handling.
    *   Removal of blocking dialogs (all dialogs must be async).
2.  **Rendering Model:** GTK4 uses a scene graph (GSK). GIMP's custom canvas drawing needs to be adapted to efficient GSK nodes or OpenGL textures within GSK, rather than simply drawing to a surface.
3.  **Composition vs Subclassing:** Modern GTK4 encourages composition. GIMP's deep inheritance hierarchies for tools and widgets are an anti-pattern in GTK4.

## Opportunity for Vimp
Starting a new project (or soft-fork) on GTK4 allows us to:
*   **Skip GTK3 Legacy:** Avoid the "sunk cost" of GIMP's GTK3 port.
*   **Native Performance:** Leverage GSK for 60fps+ UI animations and GPU compositing.
*   **Modernizing Logic:** Decouple logic from widgets immediately, using modern C++ (RAII, smart pointers) instead of managing GObject ref-counting manually where possible (via `gtkmm`).

## Conclusion
Porting existing GIMP *code* to GTK4 is a massive refactor. A "rewrite" strategy where we pick core logic (GEGL/babl usage) but rebuild the UI layer from scratch in GTK4 is likely more viable/efficient than trying to patch GIMP's GTK3 UI code up to GTK4.
