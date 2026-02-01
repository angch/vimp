const std = @import("std");
const c = @import("c.zig").c;

// Simple struct for JSON serialization
const SerializedColor = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const RecentColorsManager = struct {
    colors: std.ArrayList(c.GdkRGBA),
    allocator: std.mem.Allocator,
    custom_path: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator) RecentColorsManager {
        return .{
            .colors = std.ArrayList(c.GdkRGBA){},
            .allocator = allocator,
            .custom_path = null,
        };
    }

    pub fn deinit(self: *RecentColorsManager) void {
        self.colors.deinit(self.allocator);
        if (self.custom_path) |p| {
            self.allocator.free(p);
        }
    }

    pub fn setCustomPath(self: *RecentColorsManager, path: []const u8) !void {
        if (self.custom_path) |p| {
            self.allocator.free(p);
        }
        self.custom_path = try self.allocator.dupe(u8, path);
    }

    fn getStoragePath(self: *RecentColorsManager) ![]u8 {
        if (self.custom_path) |p| {
            return self.allocator.dupe(u8, p);
        }

        const user_data_dir = c.g_get_user_data_dir();
        if (user_data_dir == null) return error.NoUserDataDir;

        const dir_span = std.mem.span(user_data_dir);
        const vimp_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ dir_span, "vimp" });
        defer self.allocator.free(vimp_dir);

        // Ensure directory exists
        std.fs.cwd().makePath(vimp_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return std.fs.path.join(self.allocator, &[_][]const u8{ vimp_dir, "recent_colors.json" });
    }

    pub fn load(self: *RecentColorsManager) !void {
        self.colors.clearRetainingCapacity();

        const path = self.getStoragePath() catch return;
        defer self.allocator.free(path);

        const file = std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer file.close();

        const stat = try file.stat();
        if (stat.size == 0) return;

        const buffer = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(buffer);

        const bytes_read = try file.readAll(buffer);
        if (bytes_read != stat.size) return;

        const parsed = try std.json.parseFromSlice([]SerializedColor, self.allocator, buffer, .{});
        defer parsed.deinit();

        for (parsed.value) |sc| {
            const rgba = c.GdkRGBA{ .red = sc.r, .green = sc.g, .blue = sc.b, .alpha = sc.a };
            try self.colors.append(self.allocator, rgba);
        }
    }

    pub fn save(self: *RecentColorsManager) !void {
        const path = try self.getStoragePath();
        defer self.allocator.free(path);

        var list = std.ArrayList(SerializedColor){};
        defer list.deinit(self.allocator);

        for (self.colors.items) |rgba| {
            try list.append(self.allocator, .{
                .r = rgba.red,
                .g = rgba.green,
                .b = rgba.blue,
                .a = rgba.alpha,
            });
        }

        // Buffer JSON
        var buf = std.ArrayList(u8){};
        defer buf.deinit(self.allocator);

        // Note: {f} is required for std.json.fmt in this Zig version to invoke the format method
        try buf.writer(self.allocator).print("{f}", .{std.json.fmt(list.items, .{})});

        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();

        try file.writeAll(buf.items);
    }

    pub fn colorsEqual(a: c.GdkRGBA, b: c.GdkRGBA) bool {
        const epsilon = 0.001;
        return @abs(a.red - b.red) < epsilon and
               @abs(a.green - b.green) < epsilon and
               @abs(a.blue - b.blue) < epsilon and
               @abs(a.alpha - b.alpha) < epsilon;
    }

    pub fn add(self: *RecentColorsManager, color: c.GdkRGBA) !void {
        // Remove existing if present (move to front)
        var i: usize = 0;
        while (i < self.colors.items.len) {
            if (colorsEqual(self.colors.items[i], color)) {
                _ = self.colors.orderedRemove(i);
            } else {
                i += 1;
            }
        }

        try self.colors.insert(self.allocator, 0, color);

        // Limit to 20
        while (self.colors.items.len > 20) {
            _ = self.colors.pop();
        }

        self.save() catch |err| {
             std.debug.print("Failed to save recent colors: {}\n", .{err});
        };
    }
};

test "RecentColorsManager logic" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const db_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "logic_test.json" });
    defer allocator.free(db_path);

    var mgr = RecentColorsManager.init(allocator);
    defer mgr.deinit();

    // Set custom path to avoid touching user dir
    try mgr.setCustomPath(db_path);

    // Add color 1
    const c1 = c.GdkRGBA{ .red = 1.0, .green = 0.0, .blue = 0.0, .alpha = 1.0 };
    try mgr.add(c1);
    try std.testing.expectEqual(@as(usize, 1), mgr.colors.items.len);
    try std.testing.expect(RecentColorsManager.colorsEqual(mgr.colors.items[0], c1));

    // Add color 2
    const c2 = c.GdkRGBA{ .red = 0.0, .green = 1.0, .blue = 0.0, .alpha = 1.0 };
    try mgr.add(c2);
    try std.testing.expectEqual(@as(usize, 2), mgr.colors.items.len);
    try std.testing.expect(RecentColorsManager.colorsEqual(mgr.colors.items[0], c2));
    try std.testing.expect(RecentColorsManager.colorsEqual(mgr.colors.items[1], c1));

    // Add color 1 again (should move to front)
    try mgr.add(c1);
    try std.testing.expectEqual(@as(usize, 2), mgr.colors.items.len);
    try std.testing.expect(RecentColorsManager.colorsEqual(mgr.colors.items[0], c1));
    try std.testing.expect(RecentColorsManager.colorsEqual(mgr.colors.items[1], c2));
}

test "RecentColorsManager persistence" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const db_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "colors.json" });
    defer allocator.free(db_path);

    const c1 = c.GdkRGBA{ .red = 0.5, .green = 0.5, .blue = 0.5, .alpha = 1.0 };

    {
        var mgr = RecentColorsManager.init(allocator);
        defer mgr.deinit();
        try mgr.setCustomPath(db_path);
        try mgr.add(c1);
    }

    {
        var mgr = RecentColorsManager.init(allocator);
        defer mgr.deinit();
        try mgr.setCustomPath(db_path);
        try mgr.load();

        try std.testing.expectEqual(@as(usize, 1), mgr.colors.items.len);
        try std.testing.expect(RecentColorsManager.colorsEqual(mgr.colors.items[0], c1));
    }
}
