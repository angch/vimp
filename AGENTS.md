The overall guiding principle is to be a GIMP-like application
following GNOME HIG. This is detailed in the file
`doc/gimp_gnome_hig_gap_analysis.md` and should be consulted for long
term planning.

## Engineering Notes

### 2026-01-30: Bucket Fill Optimization
- Implemented dirty rectangle tracking for `bucketFill` in `src/engine.zig`.
- Reduced memory bandwidth usage by only writing back changed pixels to GEGL.
- Benchmark: ~18% speedup for small fills (87ms -> 71ms).
- Bottleneck remains reading the full buffer from GEGL to perform the flood fill client-side. Future optimization should look into tiling the read or using GEGL iterators.