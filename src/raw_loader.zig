const std = @import("std");
const c = @import("c.zig").c;

pub const RawLoader = struct {
    pub const RawTool = enum {
        darktable,
        rawtherapee,
        none,
    };

    pub const raw_exts = [_][]const u8{
        ".cr2", ".nef", ".arw", ".dng", ".orf", ".rw2", ".raf", ".cr3", ".srw", ".pef", ".3fr", ".iiq", ".sr2", ".srf",
    };

    pub fn isRawFile(path: []const u8) bool {
        const ext = std.fs.path.extension(path);
        if (ext.len == 0) return false;

        for (raw_exts) |e| {
            if (std.ascii.eqlIgnoreCase(ext, e)) return true;
        }
        return false;
    }

    pub fn findRawTool() RawTool {
        // g_find_program_in_path returns a newly allocated string or NULL.
        if (c.g_find_program_in_path("darktable-cli")) |ptr| {
            c.g_free(ptr);
            return .darktable;
        }
        if (c.g_find_program_in_path("rawtherapee-cli")) |ptr| {
            c.g_free(ptr);
            return .rawtherapee;
        }
        return .none;
    }
};

test "RawLoader isRawFile" {
    try std.testing.expect(RawLoader.isRawFile("image.CR2"));
    try std.testing.expect(RawLoader.isRawFile("image.nef"));
    try std.testing.expect(RawLoader.isRawFile("image.ARW"));
    try std.testing.expect(RawLoader.isRawFile("image.dng"));
    try std.testing.expect(RawLoader.isRawFile("/path/to/image.ORF"));

    try std.testing.expect(!RawLoader.isRawFile("image.jpg"));
    try std.testing.expect(!RawLoader.isRawFile("image.png"));
    try std.testing.expect(!RawLoader.isRawFile("image"));
    try std.testing.expect(!RawLoader.isRawFile(""));
}
