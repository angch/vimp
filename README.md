# Vimp

Vimp is a learning project to attempt to use **agentic coding** to come up with a new GIMP-like application with these extra features:

- Upgrade an existing GTK3 app to GTK4
- Comply with [Gnome HIG](https://developer.gnome.org/hig/)

---

## Technology Stack

After an architectural analysis (see [`doc/architecture-analysis/`](doc/architecture-analysis/)), we have selected:

| Component | Choice |
|-----------|--------|
| **Language** | [Zig](https://ziglang.org/) 0.15+ |
| **GUI Toolkit** | GTK4 (via direct C interop) |
| **Image Processing** | GEGL / Babl |

**Why Zig?** Vimp leverages the existing GIMP C ecosystem (GEGL, Babl, libgimp). Zig's `@cImport` allows seamless interop with legacy C libraries without FFI friction.

---

## Development Setup

### Quick Setup (Fresh Ubuntu 24.04)

```bash
# Clone and run setup script
git clone git@github.com:angch/vimp.git ~/project/vimp
cd ~/project/vimp
bash setup.sh
source ~/.bashrc
```

### What Gets Installed

The setup script (`setup.sh`) installs:

- **Build Tools**: `build-essential`, `git`, `curl`, `pkg-config`
- **GTK4**: `libgtk-4-dev`, `libadwaita-1-dev`
- **GEGL/Babl**: `libgegl-dev`, `libbabl-dev`
- **Zig 0.15.2**: Installed to `~/.local/zig`, added to PATH
- **Vendored Libs**: GEGL/Babl libs downloaded to `libs/` (via `scripts/setup_libs.sh`)

### Build & Run

```bash
# Build
make build
# or
zig build

# Run
make run
# or
zig build run
```

---

## Agentic Development Workflow

Vimp is developed using an **agent-centric** approach. While we don't follow a rigid loop, we use agents to:

-   **Plan Features**: Creating Product Requirements Documents (PRDs) for new functionality.
-   **Implement Stories**: Breaking down features into actionable tasks and implementing them iteratively.
-   **Verify Correctness**: Using automated tests and manual walkthroughs to ensure high quality.

### Core Development Skills

The project defines several "skills" for agents to ensure consistency:

-   [`gegl`](.agent/skills/gegl/SKILL.md): Guidelines for using GEGL in Vimp.
-   [`gtk4_ui`](.agent/skills/gtk4_ui/SKILL.md): Best practices for GTK4 UI development.
-   [`zig_gtk_interop`](.agent/skills/zig_gtk_interop/SKILL.md): Safety patterns for Zig and C interop.

---

## Project Structure

```
vimp/
├── src/                    # Zig source code
│   ├── main.zig           # UI Entry point
│   ├── engine.zig         # Image engine (GEGL integration)
│   ├── engine/            # Refactored engine modules
│   ├── tools/             # Tool implementations
│   ├── ui/                # UI components
│   └── c.zig              # C interop definitions
├── libs/                   # Vendored GEGL/Babl libraries
├── doc/                    # Documentation & analysis
├── .agent/                 # Agent-specific instructions and skills
├── build.zig              # Zig build configuration
└── TODO.md                # Project roadmap and tasks
```

---

## License

MIT
