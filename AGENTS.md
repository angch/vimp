# Agent Guidelines for Vimp

## Project Overview
Vimp is a learning project attempting to create a GIMP-like application using **Zig** and **GTK4**, complying with the **GNOME HIG**.
Goal: Upgrade GIMP concepts to a modern stack (Zig, GTK4, GEGL/Babl).

## Documentation
- [Architecture](doc/architecture.md) - Directory structure, key components, and data flow.
- [Development Workflow](doc/development_workflow.md) - Build instructions, environment setup, and reference code.
- [Coding Conventions](doc/coding_conventions.md) - Naming, memory management, and C interop guidelines.
- [Agent Protocol](doc/agent_protocol.md) - Task selection, implementation, verification, and documentation steps.
- [Dev Log / Engineering Notes](doc/dev_log.md) - History of changes, decisions, and technical notes.

## Skills (Generic)
- [Zig & GTK Interop](.agent/skills/zig_gtk_interop/SKILL.md) - Guidelines for interacting with GObject/C from Zig.
- [GTK4 Migration](.agent/skills/gtk4_migration/SKILL.md) - Patterns for migrating from older GTK versions.

## Feature Specs & Analysis
- [GIMP Analysis](doc/gimp-analysis.md)
- [GNOME HIG Analysis](doc/gnome-hig-analysis.md)
- [GAP Analysis](doc/gimp_gnome_hig_gap_analysis.md)

## Tech Stack Summary
- **Language**: Zig 0.15+
- **Toolkit**: GTK4 + Libadwaita
- **Engine**: GEGL 0.4 / Babl 0.1
- **Build**: `zig build`

## Environment Limitations
- **GEGL Loaders**: The development environment lacks loaders for certain formats like EPS/PostScript (`image/x-eps`). While filters are implemented in the UI, `gegl:load` may fail with a warning unless proper delegates (Ghostscript) or plugins are installed.
