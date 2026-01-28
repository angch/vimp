# Architecture & Strategy Final Recommendation

## Executive Summary

After evaluating C++/GTK4, Rust (gtk4-rs), Zig, Go, and Dart, the recommendation for the **Vimp** project (Modern GIMP Port/Rewrite) is to use **Zig** with **GTK4**.

## Comparative Analysis Matrix

| Feature | **Rust (gtk4-rs)** | **Zig (Direct Interop)** | **C++ (gtkmm)** | **Go/Dart** |
| :--- | :--- | :--- | :--- | :--- |
| **Safety** | High (Borrow Checker) | Moderate (Better C) | Low (Manual) | High (GC) |
| **Dev Loop (Compile Time)** | Slow | **Fast** | Slow | Fast |
| **GIMP Core Interop (Legacy C)** | FFI / Bindgen (Friction) | **Native (@cImport)** | Native | High Friction (Cgo) |
| **GTK4 Bindings** | Mature (Safe Wrappers) | **Raw C API** | Mature (Native) | Immature / None |
| **Packaging/Cross-Compile** | Mature (Cargo) | **Excellent (Zig Build)** | Standard | Mixed |
| **Ecosystem** | Huge (Crates.io) | Small (Growing) | Massive (System) | Huge |

## The Decision: Zig

### Why Zig?

1.  **The "GIMP Problem" is a C Integration Problem**
    GIMP consists of hundreds of thousands of lines of C code (GEGL, Babl, GIMP Core).
    *   **Rust** requires strict `unsafe` blocks and generating bindings to interact with these. It creates a "Wall" between the new code and the old code.
    *   **Zig** dissolves this wall. We can `@cImport("libgimp/gimp.h")` and immediately subclass GIMP objects, call GIMP functions, and manipulate GIMP buffers as if we were writing C, but with Zig's modern safety features (slices, error handling, defer, comptime).

2.  **Development Velocity**
    Zig's build times are fully incremental and near-instant (~0.1s warm builds). Rust's compile times (~30s+ cold, ~2-5s warm) significantly hamper UI iteration speed.

3.  **Deployment Simplicity**
    Zig's compiler is also a C compiler (`zig cc`). This allows us to compile the remaining legacy C parts of GIMP *using the Zig toolchain* comfortably, cross-compiling the entire mixed C/Zig codebase to Windows/Linux/macOS from a single machine without complex Docker setups.

### Specific Trade-offs & Mitigations

*   **Risk:** Zig is pre-1.0.
    *   *Mitigation:* Lock compiler version in `build.zig.zon`. The surface area we use (C interop) is stable.
*   **Risk:** No "Safe" GTK4 wrapper.
    *   *Mitigation:* We will write a thin, domain-specific shim for the GTK widgets we use most (Canvas, Dockables) rather than trying to wrap the whole library.
*   **Risk:** Manual Memory Management.
    *   *Mitigation:* Zig's `defer` and `errdefer` make manual management significantly safer than C++ RII or raw C.

## Implementation Strategy

1.  **Phase 1: The Shell (Current)**
    *   Build the main window, canvas, and dock system in pure Zig + GTK4.
    *   Establish the build system to link against system GTK4.

2.  **Phase 2: The Core (Interop)**
    *   Link against `libgegl` and `libbabl`.
    *   Implement a pixel buffer engine using GEGL nodes driven by Zig control logic.

3.  **Phase 3: Porting**
    *   Incrementally rewrite complex GIMP C tools into Zig structs.

## Conclusion

**Vimp will be a Zig application.** This choice maximizes our ability to leverage the existing GIMP legacy (C code) while providing a modern, high-performance developer experience that C++ cannot match and a flexibility that Rust's strictness hinders in this specific "Brownfield Port" context.
