
# PRD: GIMP Core Analysis for Vimp Port

## Introduction
Analyze the GIMP codebase to identify core architectural patterns, data structures, and algorithms to facilitate "porting" (re-implementation) into Vimp (a modern GTK4/Rust/Go based GIMP-like application).

## Goals
- Establish a local reference copy of GIMP source code.
- Ensure reference code is isolated from Vimp's own version control.
- Produce initial technical documentation on GIMP's internal structure.
- Identify key components for potential porting: Image model, Plugin system, GEGL integration.

## User Stories

### US-001: Setup Reference Environment
**Description:** As a developer, I want the GIMP source code available locally in a `ref` directory so I can grep/read it, but I don't want it polluting my `git status`.
**Acceptance Criteria:**
- [ ] `ref/gimp` contains GIMP source code.
- [ ] `ref/` is added to `.gitignore`.
- [ ] `git status` in Vimp root does not show `ref/`.

### US-002: Analyze Application Structure
**Description:** As a developer, I want to know the high-level directory structure of GIMP so I know where to look for specific features.
**Acceptance Criteria:**
- [ ] `doc/gimp-analysis.md` created.
- [ ] Section on "Directory Structure" describing key folders (app, libgimp, etc.).
- [ ] Section on "Build System" (briefly).

### US-003: Identify Core Data Structures
**Description:** As a developer, I want to understand how GIMP represents an image and layers so I can design Vimp's model.
**Acceptance Criteria:**
- [ ] `doc/gimp-analysis.md` contains "Core Models" section.
- [ ] specific references to C files/structs defining `GimpImage`, `GimpLayer`, etc.

## Functional Requirements
- FR-1: Clone https://github.com/GNOME/gimp to `ref/gimp`.
- FR-2: Create `doc/` directory if missing.
- FR-3: Generate markdown documentation.

## Non-Goals
- Compiling GIMP locally (we just want to read the code).
- Porting any actual code *yet* (just analysis).

## Success Metrics
- A clear, readable Markdown file describing GIMP's architecture.
- Vimp git repo remains clean.

## Open Questions
- Specifics of Vimp's language stack (assuming Go/Rust/C interaction via GTK4) might influence what we look for (e.g. C headers vs GObject introspection).
