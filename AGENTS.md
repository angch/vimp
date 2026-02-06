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

## 3. Testing
*Strategies for verifying functionality.*

- [Headless UI Testing](doc/testing.md) - Using Broadway + Playwright for E2E verification.
- **Binary Execution**: Run `zig build run -- --help` to verify the binary executes and links correctly without runtime errors. Do this before committing code.

## 4. Documentation
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

## 5. Agent Workflow
- [Ralph Loop Instructions](.agent/skills/ralph/LOOP_INSTRUCTIONS.md) - The prompt for the autonomous agent loop.
- [PRD Creation](.agent/skills/prd/SKILL.md) - Creating feature specs.
- [Ralph PRD Conversion](.agent/skills/ralph/SKILL.md) - Converting specs to JSON.

## 5. Critical Learnings & Gotchas
- **Zig std.ArrayList**: In this environment (Zig 0.15.2), `std.ArrayList(T)` behaves like an unmanaged list. It must be initialized with `{}` (e.g. `var list = std.ArrayList(T){}`) and methods like `append` require passing the allocator explicitly (e.g. `list.append(allocator, item)`).
- **Selection Consistency**: The previous implementation of `drawRectangle` (filled) used `gegl:rectangle` which ignored the active selection. The new implementation in `src/engine/paint.zig` uses CPU-side rasterization and correctly respects the selection mask, consistent with other drawing tools.
- **Tool System Refactoring**: The Tool System has been refactored to a polymorphic interface defined in `src/tools/interface.zig`. All tools (Paint, Selection, Shapes, etc.) implement `ToolInterface` and reside in `src/tools/`. `src/main.zig` delegates input events solely to the `active_tool_interface`.
- **Gitignore Pitfall**: The `.gitignore` file contained a `tools/` entry, which coincidentally ignored `src/tools/`, causing build failures when new source files were added there. Always ensure `.gitignore` patterns are rooted (e.g. `/tools/`) if they are meant to target root directories only.
- **Tool Creation Factory**: Tool instantiation logic has been moved from `src/main.zig` to `src/tools/factory.zig`. New tools should be added to the `ToolFactory` struct instead of modifying the switch statement in `main.zig`.
- **CLI & Multi-Process**: Vimp handles "Open as separate images" (SDI behavior) by spawning new processes. `G_APPLICATION_NON_UNIQUE` allows multiple instances. Arguments are passed via `g_application_run` using `std.os.argv`. A custom `handle-local-options` callback parses `--page=N` to support opening specific PDF pages without dialog.
- **Zig Keywords**: Avoid using `opaque` as a variable or parameter name as it is a Zig keyword. Use `is_opaque` instead.
- **Engine Refactoring**: When splitting the `Engine` God Object, avoid circular dependencies by not importing `core.zig` (which defines `Engine`) in sub-modules. Instead, pass necessary data structures (like `std.ArrayList(Layer)`) or types defined in leaf modules (`src/engine/types.zig`, `src/engine/layers.zig`).
