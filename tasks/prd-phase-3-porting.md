# PRD: Phase 3 - Porting (GIMP Tools to Zig)

## Introduction

This phase focuses on validating the architectural recommendation to use Zig for incrementally rewriting GIMP's C codebase. We will implement a "Zig Eraser Tool" that inherits from the existing C `GimpBrushTool` (or `GimpPaintTool`) but implements its logic in Zig. This establishes the "Golden Path" for migrating the rest of the application.

## Goals

- Prove that Zig can subclass complex GObject hierarchies from GIMP C code.
- Implement a functional tool (Eraser or Simple Brush) in Zig.
- Maintain binary compatibility with the existing GIMP engine.
- Establish patterns for VTable overriding and C/Zig memory layout matching.

## User Stories

### US-001: Zig Bindings for Tool Hierarchy
**Description:** As a developer, I need Zig struct definitions that match the C memory layout of `GimpTool`, `GimpPaintTool`, and `GimpBrushTool` so I can inherit from them.

**Acceptance Criteria:**
- [ ] `src/gimp/tool.zig` defines `GimpTool` and `GimpToolClass` extern structs.
- [ ] `src/gimp/paint_tool.zig` defines `GimpPaintTool` layout.
- [ ] Offsets of fields in Zig match C (verified via `extern` or runtime assertions).
- [ ] Typecheck passes.

### US-002: Zig GObject Registration
**Description:** As a developer, I want to register a new GType `GimpZigEraserTool` from Zig code that the C GObject system recognizes.

**Acceptance Criteria:**
- [ ] Zig function `gimp_zig_eraser_tool_get_type()` returns a valid GType.
- [ ] `class_init` and `instance_init` functions are implemented in Zig and called by GObject.
- [ ] The type is derived from `GIMP_TYPE_BRUSH_TOOL` (or appropriate parent).

### US-003: VTable Overriding in Zig
**Description:** As a developer, I want to override `button_press` and `motion` virtual methods in Zig to define custom behavior.

**Acceptance Criteria:**
- [ ] In `class_init`, the `GimpToolClass.button_press` function pointer is swapped for a Zig function.
- [ ] When the tool is selected and used, the Zig function prints a debug message or executes logic.
- [ ] `parent_class` methods can be called from Zig (chaining up).

### US-004: Functional Eraser Logic
**Description:** As a user, I want the Zig Eraser to actually erase pixels on the canvas.

**Acceptance Criteria:**
- [ ] Implement `GimpPaintToolClass.is_alpha_only` in Zig.
- [ ] reuse `gimp_brush_tool` logic or implement custom painting logic (via GEGL graph manipulation from Phase 2).
- [ ] Verify in browser (if UI capable) or via unit test that pixels are modified.

### US-005: Register Tool in Tool Manager
**Description:** As a user, I want to see "Zig Eraser" in the toolbar.

**Acceptance Criteria:**
- [ ] Call `gimp_tool_register` (or equivalent) to add the new tool to the registry.
- [ ] Assign an icon (reuse existing Eraser icon).
- [ ] Tool appears in the UI and can be selected.

## Functional Requirements

- FR-1: **Zero C Wrapper Files**: The implementation should be 100% Zig (using `@cImport` and `extern` structs), avoiding auxiliary `.c` files if possible.
- FR-2: **Safety**: Use Zig's `extern struct` to guarantee C ABI compatibility.
- FR-3: **Performance**: Usage of the tool should not introduce noticeable lag compared to C.

## Technical Considerations

### GObject Inheritance in Zig
To subclass `GimpBrushTool` in Zig:

1.  **Layout Mirroring**:
    ```zig
    pub const GimpEraserTool = extern struct {
        parent_instance: c.GimpBrushTool,
        // Zig-specific fields can go here, but be careful with size if C relies on it
    };
    ```
2.  **Class Initialization**:
    ```zig
    export fn gimp_zig_eraser_tool_class_init(klass: *c.GimpEraserToolClass) void {
        const tool_class = @ptrCast(*c.GimpToolClass, klass);
        tool_class.button_press = myZigButtonPress;
    }
    ```
3.  **Registration**:
    We might need a small C helper macro for `G_DEFINE_TYPE` if `zig translate-c` doesn't handle the macros well, but we should aim to do it manually in Zig by calling `g_type_register_static`.

### Fine-Grained approach
- We are NOT rewriting `GimpBrushTool` yet. We are inheriting from the *existing C implementation* and only overriding specific methods.
- This minimizes utility code rewriting.

## Success Metrics

- "Zig Eraser" appears in the menu.
- Clicking on canvas triggers Zig code.
- No segfaults when switching tools.
