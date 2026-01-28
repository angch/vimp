# Alternative Languages Review & Selection

## Goal
Evaluate modern alternatives to C++ (Zig, Rust, Go, Dart) to select the top 2 candidates for prototyping a GIMP-like application (Vimp) using GTK4.

## Criteria
1.  **GTK4 Bindings Maturity**: Are the bindings stable, maintained, and feature-complete?
2.  **C Interoperability**: How easy is it to interface with existing C libraries (libgimp, GEGL, babl)?
3.  **Developer Experience**: tooling, compile times, strictness vs flexibility.

## Language Analysis

### 1. Rust
*   **GTK4 Bindings**: **Excellent**. `gtk-rs` is the gold standard for non-C GTK development. It is officially endorsed by GNOME, highly active, and feature-complete.
*   **C Interop**: **Good**. `bindgen` automatically generates bindings. Writing safe wrappers is time-consuming but results in high-quality, safe APIs.
*   **Pros**: Memory safety, strong ecosystem, mature GUI story (Relm4, GTK4-rs).
*   **Cons**: Slow compile times, steep learning curve, "Cgo" equivalent overhead is low but bridging safety gaps is manual work.

### 2. Go
*   **GTK4 Bindings**: **Moderate**. `gotk4` is active but pre-v1. `puregotk` offers a Cgo-free experience but has limitations. Functional but rough edges expected.
*   **C Interop**: **Poor/Fair**. `Cgo` introduces performance overhead and complicates the build process. Go's GC and GObject's ref-counting can be tricky to manage together.
*   **Pros**: Fast compilation, simple language, good concurrency.
*   **Cons**: Garbage collection paus times (potentially), clunky C interop, bindings less mature than Rust.

### 3. Zig
*   **GTK4 Bindings**: **Immature**. No stable, dominant high-level binding. `zig-gobject` exists but is experimental.
*   **C Interop**: **Excellent**. Best-in-class. Zig can import C headers directly (`@cImport`) and compile C code. No "FFI" overhead; it treats C types as native.
*   **Pros**: "Better C" philosophy, amazing C interop (crucial for GIMP porting), fast compilation, manual memory management (predictable).
*   **Cons**: Language not yet 1.0 (breaking changes), ecosystem smaller than Rust/Go, manual GObject management required (can be verbose).

### 4. Dart
*   **GTK4 Bindings**: **Non-existent / Irrelevant**. Dart's desktop story is **Flutter**. Flutter draws its own widgets (Skia/Impeller) and does not map 1:1 to native GTK4 widgets. Using Dart with raw GTK4 via FFI `art:ffi` is theoretically possible but practically unsupported and effectively "write your own bindings".
*   **Pros**: Flutter is productive for UI.
*   **Cons**: Not a "native GTK4" app (lacks Adwaita native behavior unless mimicked), heavy runtime, "write your own bindings" for everything else.

## Selection

Based on the research, we select the following two languages for prototyping:

1.  **Rust**: The "Safe" Choice.
    *   *Reason*: Most mature GTK4 bindings (`gtk-rs`). If we want a reliable, modern GTK4 app today, Rust is the proven path.
2.  **Zig**: The "Interop/Performance" Choice.
    *   *Reason*: Unmatched C interoperability. Since GIMP is massive C codebase, Zig's ability to include C headers and mix code could make "porting" significantly easier than writing mostly-safe Rust wrappers. It represents a "High risk, High reward" path.

**Discarded**:
*   **Go**: `cgo` friction and GC concerns make it less attractive than Rust (safety) or Zig (interop).
*   **Dart**: Not suitable for a "Native GTK4" requirement; implies using Flutter which changes the architectural goal.

## Next Steps
*   Proceed to US-003: Prototype in **Rust**.
*   Proceed to US-004: Prototype in **Zig**.
