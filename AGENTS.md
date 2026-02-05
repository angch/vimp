# Agent Guidelines for Vimp

## 1. Project Overview
Vimp is a GIMP-like application built with **Zig**, **GTK4**, and **GEGL**. It aims to upgrade GIMP concepts to a modern stack while complying with the **GNOME HIG**.

- **Tech Stack**: Zig 0.15+, GTK4 + Libadwaita, GEGL 0.4 / Babl 0.1.
- **Build**: `zig build`

## 2. Core Skills & Patterns
*Detailed technical guidelines for specific domains.*

- [Zig & GTK Interop](.agent/skills/zig_gtk_interop/SKILL.md) - C interop safety, memory management, and string handling.
- [GTK4 UI Patterns](.agent/skills/gtk4_ui/SKILL.md) - Styling, stateful actions, and widget management.
- [GEGL Usage](.agent/skills/gegl/SKILL.md) - Graph construction and export operations.
- [GTK4 Migration](.agent/skills/gtk4_migration/SKILL.md) - Porting legacy patterns to modern GTK4.

## 3. Documentation
*Project-specific architecture and analysis.*

### Key Docs
- [Architecture](doc/architecture.md) - System design and data flow.
- [Development Workflow](doc/development_workflow.md) - Setup and build instructions.
- [Coding Conventions](doc/coding_conventions.md) - Style and best practices.
- [Environment Limitations](doc/environment_limitations.md) - Known runtime issues and workarounds.

### Analysis & Features
- [Vimp Features](doc/vimp_features.md) - Current implementation status.
- [GIMP Reference](doc/gimp_reference.md) - Reference list of GIMP features.
- [GIMP Analysis](doc/gimp-analysis.md) - Deep dive into GIMP architecture.
- [GNOME HIG Analysis](doc/gnome-hig-analysis.md) - UI design guidelines.

## 4. Agent Workflow
- [Ralph Loop Instructions](.agent/skills/ralph/LOOP_INSTRUCTIONS.md) - The prompt for the autonomous agent loop.
- [PRD Creation](.agent/skills/prd/SKILL.md) - Creating feature specs.
- [Ralph PRD Conversion](.agent/skills/ralph/SKILL.md) - Converting specs to JSON.
