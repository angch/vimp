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

This project uses **Ralph**, an autonomous coding agent workflow for iterative development.

### How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│  1. Create PRD        →  tasks/prd-[feature].md                 │
│  2. Convert to JSON   →  prd.json                               │
│  3. Run Ralph Loop    →  Agent implements stories one-by-one    │
│  4. Merge to main     →  git merge ralph/[feature]              │
└─────────────────────────────────────────────────────────────────┘
```

### Step-by-Step

1. **Create a PRD** using the `prd` skill:
   ```
   Load the prd skill and create a PRD for [feature description]
   ```
   Output: `tasks/prd-[feature-name].md`

2. **Convert PRD to Ralph format** using the `ralph` skill:
   ```
   Load the ralph skill and convert tasks/prd-[feature-name].md to prd.json
   ```
   Output: `prd.json` with user stories

3. **Run the Ralph agent loop** - paste `.agent/skills/ralph/LOOP_INSTRUCTIONS.md` contents as prompt. The agent:
   - Reads `prd.json` and `progress.txt`
   - Checks out the feature branch
   - Picks highest-priority story with `passes: false`
   - Implements it, runs checks, commits
   - Updates `prd.json` and `progress.txt`
   - Repeat until all stories pass

4. **Merge completed feature**:
   ```bash
   git switch main
   git merge ralph/[feature-name]
   ```

### Key Files

| File | Purpose |
|------|---------|
| `prd.json` | Current PRD in Ralph format |
| `progress.txt` | Agent progress log with learnings |
| `.agent/skills/ralph/LOOP_INSTRUCTIONS.md` | Agent loop instructions (prompt) |
| `.agent/skills/prd/` | PRD creation skill |
| `.agent/skills/ralph/` | PRD-to-JSON converter skill |
| `tasks/*.md` | Archived/completed PRDs |
| `archive/` | Historical prd.json + progress.txt |

---

## Project Structure

```
vimp/
├── src/                    # Zig source code
│   ├── main.zig           # Entry point
│   ├── engine.zig         # Image engine (GEGL integration)
│   └── c.zig              # C interop definitions
├── libs/                   # Vendored GEGL/Babl libraries
├── doc/                    # Documentation & analysis
├── tasks/                  # PRD markdown files
├── scripts/               
│   └── setup_dev_machine.sh  # Dev environment setup
├── tools/
│   └── setup_libs.sh      # Download vendored libs
├── build.zig              # Zig build configuration
├── prd.json               # Current Ralph PRD
└── progress.txt           # Agent progress log
```

---

## License

MIT
