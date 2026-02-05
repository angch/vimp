# Visual Regression Testing

Vimp uses a dedicated visual regression testing suite located in `src/test_visual_regression.zig`. This ensures that rendering operations (drawing, filters, text) produce consistent output across changes.

## How it Works

The test suite uses the `Engine` to perform operations and exports the result to a PNG file. It then compares this output against a "baseline" (golden) image stored in `tests/baselines/`.

- **Output Directory**: `tests/output/` (Current run results)
- **Baseline Directory**: `tests/baselines/` (Reference images)
- **Failures Directory**: `tests/failures/` (Diff images/Failed outputs)

## Running Tests

Visual regression tests are included in the standard test suite:

```bash
zig build test
```

## Adding a New Test

1.  Open `src/test_visual_regression.zig`.
2.  Add a new test case using the `checkBaseline` helper:

```zig
test "Visual: My New Feature" {
    var engine = Engine{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    try engine.addLayer("Background");

    // Perform operations...
    try engine.drawRectangle(10, 10, 50, 50, 0, true);

    // Verify against baseline "my_new_feature.png"
    try checkBaseline(&engine, "my_new_feature");
}
```

3.  Run `zig build test`.
    - The first run will print: `Baseline not found for my_new_feature. Creating new baseline.`
    - It will automatically save the output to `tests/baselines/my_new_feature.png`.
4.  Commit the new baseline image.

## Updating Baselines

If you intentionally change rendering logic (e.g., improve anti-aliasing), existing tests may fail. To update the baselines:

1.  Delete the obsolete baseline image(s) from `tests/baselines/`.
2.  Run `zig build test`.
3.  New baselines will be generated from the current output.
4.  Verify the new images look correct (open `tests/baselines/`).
5.  Commit the updated images.

## Troubleshooting

If a test fails with `error.VisualRegressionFailed`:
1.  Check `tests/failures/` for the `{test_name}_diff.png` (or the actual output).
2.  Compare it with `tests/baselines/{test_name}.png`.
3.  If the change is expected, update the baseline.
