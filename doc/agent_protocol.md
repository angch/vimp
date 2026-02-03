# Agent Protocol

1.  **Task Selection**: Check `TODO.md` or `prd.json` for active tasks.
2.  **Implementation**:
    - Modify source code in `src/`.
    - Create/Update tests in `src/` to verify changes.
3.  **Verification**:
    - **MUST** run `zig build test` before submitting.
    - If `zig build test` fails, fix the code or the test.
    - Verify GUI changes visually if possible (though agents often can't see, running the code ensures no crashes).
4.  **Documentation**:
    - Update documentation with any new findings, gotchas, or architectural decisions.
    - Update `progress.txt` if working in the Ralph loop.

## Known Issues / Gotchas
- GEGL plugin loading can be tricky in test environments. `build.zig` attempts to set it up correctly.
- Cairo surfaces need `cairo_surface_mark_dirty` after modification by GEGL/CPU before being painted again.
- The overall guiding principle is to be a GIMP-like application following GNOME HIG. This is detailed in the file `doc/gimp_gnome_hig_gap_analysis.md` and should be consulted for long term planning.
