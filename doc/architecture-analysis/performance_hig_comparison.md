# Performance & Gnome HIG Compliance Comparison

## 1. Native Performance Verification

**Objective:** Verify startup time and responsiveness.

**Methodology:**
- Measured process startup time in standard build configuration (Debug).
- Attempted to verify "Time to First Paint" by instrumenting the main loop to exit immediately after the first draw call.

**Results:**
- **Environment Constraint:** Direct measurement of rendering latency was not possible in the current headless environment (failed to open display).
- **Startup Overhead:**
  - Rust: ~0.04s execution time until display failure.
  - Zig: ~0.01s execution time until display failure.
- **Qualitative Assessment:** Both languages produce native binaries with minimal runtime overhead. Zig likely has a slight edge in startup time due to lighter standard library and direct C bindings, but Rust is well within "Native" expectations.

## 2. Gnome HIG (LibAdwaita) Availability

**Objective:** Confirm access to full Gnome HIG widget set (Adwaita) in chosen bindings.

**Rust (`gtk4-rs` + `libadwaita-rs`):**
- **Availability:** Yes, via `libadwaita` crate.
- **Maturity:** Strong, but "Strict Version Coupling" is a minor friction point.
  - `libadwaita 0.7` requires `gtk4 0.9`.
  - `gtk4 0.10` requires `libadwaita 0.9.0-alpha` (or similar newer version).
  - Mixing versions results in cargo dependency resolution errors on `gtk4-sys`.
- **Usage:** Standard Rust crate usage. Requires `libadwaita-1-dev` system dependency.

**Zig (Direct C Interop):**
- **Availability:** Yes, via direct import of C headers (`adwaita.h`) and linking (`-ladwaita-1`).
- **Maturity:** 100% feature parity with C API (since it IS the C API).
- **Usage:**
  - Add `exe.linkSystemLibrary("adwaita-1");` in `build.zig`.
  - Add `@cInclude("adwaita.h");` in `main.zig`.
  - Requires `libadwaita-1-dev` system dependency.

## 3. Findings & Recommendations

| Feature | Rust (`gtk-rs`) | Zig (C Interop) |
| :--- | :--- | :--- |
| **Startup Time** | Fast (Native) | Very Fast (Native) |
| **HIG Access** | High-level Safe Bindings | Direct C API Access |
| **Configuration** | Cargo.toml (Crate versions must match) | build.zig (pkg-config) |
| **Friction** | Version conflicts between crates | Manual pointer handling / C patterns |

**Recommendation:**
- **Rust** provides a safer, more "Rustic" API for Adwaita but requires careful dependency management.
- **Zig** offers zero-overhead access to the latest Adwaita features immediately (no binding wait time) but requires writing C-style UI code.

**Action Required:**
- Install `libadwaita-1-dev` on development machines to enable HIG features.
