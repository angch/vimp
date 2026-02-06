# Visual Feedback Testing Guidelines

As a UI-heavy application, Vimp requires rigorous verification of its visual output. While automated tests cover logic, visual feedback is crucial for validating rendering correctness, layout, and interaction.

## 1. Automated Visual Regression Testing

We use a combination of in-process verification and external tools.

### In-Process (Unit Tests)
- **GEGL Graph Verification**: Inspect the `GeglBuffer` content directly in tests using `gegl_buffer_get`.
- **Pixel Assertions**: Check specific pixels for expected color values.
- **Reference Comparison**: Compare the entire buffer against a known-good buffer or hash.

Example:
```zig
const rect = c.GeglRectangle{ .x = 10, .y = 10, .width = 1, .height = 1 };
c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
try std.testing.expectEqual(pixel[0], 255); // Red
```

### External (Headless UI)
- **Broadway + Playwright**: Run the application with `GDK_BACKEND=broadway` and use Playwright to capture screenshots of the browser-rendered UI.
- **Benefits**: Verifies GTK rendering, widget states, and complex interactions not easily scriptable in unit tests.

## 2. Manual Visual Verification (During Development)

When developing new tools or UI features:

1.  **Debug OSD**: Use the On-Screen Display (OSD) or HUD to show live values (e.g., dimensions, coordinates).
2.  **Debug Colors**: Temporarily use distinct, high-contrast colors (e.g., Magenta #FF00FF) to visualize invisible boundaries or hit-test areas.
3.  **GTK Inspector**:
    -   Run with `GTK_DEBUG=interactive` or press `Ctrl+Shift+I`.
    -   Inspect widget hierarchy, CSS properties, and layout bounds.
4.  **GEGL Graph Dump**:
    -   Use `gegl_node_to_xml` (if available via C interop) or print the node structure to debug graph topology.
    -   Export intermediate nodes to PNG using `gegl_node_blit` + Cairo save to check pipeline stages.

## 3. Tool-Specific Feedback

- **Selection Tools**: Marching ants should animate. Ensure geometry matches the mouse drag exactly.
- **Transform Tools**: Preview should update in real-time. Verify the preview overlay matches the final result.
- **Paint Tools**: Stroke should follow the cursor without lag. Verify anti-aliasing and opacity blending (check for double-draw artifacts).

## 4. Accessibility Visualization

- **Accerciser**: Use Accerciser to inspect the accessibility tree.
- **High Contrast**: Test with High Contrast system themes to ensure icons and text remain visible.
