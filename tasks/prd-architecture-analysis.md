# PRD: Vimp Architecture & Strategy Analysis

## Introduction

Vimp aims to be a next-generation, GIMP-like image manipulation application, leveraging agentic coding. This feature (the analysis phase) is dedicated to evaluating and selecting the optimal architectural path and technology stack to achieve the project goals: upgrading to GTK4, enforcing Gnome HIG compliance, ensuring native performance, and simplifying multiplatform deployment.

## Goals

- **Determine Strategy:** Decide between upgrading/porting the existing GIMP codebase/concepts vs. building from scratch.
- **Select Tech Stack:** Evaluate and select the primary programming language (C++, Zig, Rust, Go, Dart) and UI framework (likely GTK4 or wrappers).
- **Ensure Core Requirements:** Verify candidates against performance, multiplatform support, and packaging ease.
- **Optimize Dev Experience:** Prioritize stacks that offer fast compilation and feedback loops.

## User Stories

### US-001: Evaluate GIMP Source Upgrade Strategy (C++/GTK4)
**Description:** As a developer, I want to assess the feasibility of porting existing GIMP concepts/code to a modern C++/GTK4 stack.
**Acceptance Criteria:**
- [ ] Review GIMP's current GTK3 usage and codebase complexity.
- [ ] Implement a minimal "Hello World" window using C++ and GTK4 to test setup.
- [ ] Document pros/cons of sticking to C++/GTK4 (legacy compat vs modern maintainability).
- [ ] Verify packaging pipeline (Flatpak/Snap) for a C++ GTK4 app.

### US-002: Evaluate Alternative Languages (Zig, Rust, Go, Dart)
**Description:** As a developer, I want to evaluate modern alternatives to C++ to see if they offer better safety, ergonomics, or performance.
**Acceptance Criteria:**
- [ ] Research GTK4 bindings maturity for Zig, Rust, Go, and Dart.
- [ ] Create a minimal "Canvas" prototype in the top 2 promising languages.
- [ ] Measure compile times and feedback loop speed for each.
- [ ] Assess interop costs if using C libraries (GIMP is heavily C).

### US-003: Assess Multiplatform & Packaging Capabilities
**Description:** As a maintainer, I want to ensure the chosen stack can be easily packaged for all major targets.
**Acceptance Criteria:**
- [ ] Verify cross-compilation support for Windows from Linux for candidates.
- [ ] Check tooling support for generating Deb, RPM, Flatpak, and Snap.
- [ ] Identify any "deal-breaker" platform limitations for each stack.

### US-004: Compare Performance & Gnome HIG Compliance
**Description:** As a product owner, I want to ensure the app feels "native" and looks correct on Gnome.
**Acceptance Criteria:**
- [ ] Verify "Native Performance" (startup time, rendering latency) in prototypes.
- [ ] Confirm access to full Gnome HIG widget set (Adwaita, etc.) in the chosen bindings.

### US-005: Produce Final Recommendation
**Description:** As the project lead, I want a consolidated report to make the final decision.
**Acceptance Criteria:**
- [ ] Create a comparison matrix (Language vs Criteria).
- [ ] Write a summary recommendation (Stack + Strategy).
- [ ] Update README.md with the decision.

## Functional Requirements

- FR-1: The analysis must produce a Comparison Matrix.
- FR-2: Prototypes must demonstrate a basic window with a button or drawing area to prove binding viability.
- FR-3: Packaging analysis must cover at least 3 formats (e.g., Flatpak, Deb, Windows Exe).

## Non-Goals

- Implementing actual image editing features (Analysis only).
- Porting the entire GIMP codebase.
- Designing the final UI (just verifying HIG capabilities).

## Technical Considerations

- **GObject Introspection:** Most interaction with GTK4 will rely on GIR. Bindings must handle this well.
- **Legacy Code:** GIMP has massive legacy C code. If "Porting", C interoperability is paramount.
- **Agentic Coding:** The chosen stack should be "friendly" for AI agents to write (popular, standard boilerplate).

## Success Metrics

- **Decision Confidence:** 100% confidence in the chosen stack (no "maybe"s).
- **Prototype Latency:** Chosen stack prototype should start in <200ms.
- **Build Time:** Incremental build time < 2s for optimal dev loop.

## Open Questions

- Does "upgrading GIMP" mean using the actual GIMP source tree, or just imitating its architecture? (Assumed: Investigating both).
- Which specific "extra features" from GIMP are priority? (Assumed: Core editing first).
