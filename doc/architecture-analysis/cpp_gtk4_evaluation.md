# C++/GTK4 Strategy Evaluation

## Pros & Cons of C++ with GTK4

### Pros
*   **Native Fidelity:** GTK4 is written in C. C++ (`gtkmm`) provides the closest high-level binding without the overhead of a managed runtime (like Python/JS) or the maturity gaps of newer language bindings (Rust/Go bindings for GTK4 are good but can lag).
*   **Performance:** Zero-cost abstractions. Critical for an image editor where canvas rendering speed is paramount.
*   **Legacy Interop:** integration with GIMP's existing C libraries (GEGL, bubl, libgimp) is trivial in C++. No complex FFI needed.
*   **Maturity:** `gtkmm` is the official C++ binding, maintained in lock-step with GTK.

### Cons
*   **Developer Experience:** C++ compile times are slow. The feedback loop is longer compared to Go or Dart.
*   **Complexity:** Memory safety is manual (though `Glib::RefPtr` helps). Segfaults are possible.
*   **Boilerplate:** GTK4 + C++ requires significant boilerplate for headers/implementation files compared to modern declarative UI frameworks.

## Packaging Verification (Flatpak)

Packaging a C++/GTK4 app is well-supported in the Linux ecosystem.

### Flatpak
*   **Runtime:** `org.gnome.Platform//46` (or latest) contains GTK4 and `gtkmm` usually (or can be easily added).
*   **Builder:** `flatpak-builder` handles C++ autotools/cmake/meson builds natively.
*   **Manifest Example:**
    See `prototypes/cpp-gtk4/org.vimp.Hello.json` for a working manifest structure.

### Snap
*   **Plugin:** The `gnome` extension for `snapcraft` supports GTK4 fully.
*   **Build:** Similar to Flatpak, standard C++ build systems works out of the box.

## maintainability
Using C++/GTK4 ensures likely the best longevity for a "GIMP-like" app on Linux, as it aligns exactly with the GNOME platform's native tools. However, it raises the barrier to entry for contributors who might prefer Rust or JS.
