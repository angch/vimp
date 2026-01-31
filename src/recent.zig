const std = @import("std");
const c = @import("c.zig").c;

pub const RecentManager = struct {
    paths: std.ArrayList([]u8),
    allocator: std.mem.Allocator,
    custom_path: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator) RecentManager {
        return .{
            .paths = std.ArrayList([]u8){},
            .allocator = allocator,
            .custom_path = null,
        };
    }

    pub fn deinit(self: *RecentManager) void {
        for (self.paths.items) |path| {
            self.allocator.free(path);
        }
        self.paths.deinit(self.allocator);
        if (self.custom_path) |p| {
            self.allocator.free(p);
        }
    }

    pub fn setCustomPath(self: *RecentManager, path: []const u8) !void {
        if (self.custom_path) |p| {
            self.allocator.free(p);
        }
        self.custom_path = try self.allocator.dupe(u8, path);
    }

    fn getStoragePath(self: *RecentManager) ![]u8 {
        if (self.custom_path) |p| {
            return self.allocator.dupe(u8, p);
        }

        const user_data_dir = c.g_get_user_data_dir();
        if (user_data_dir == null) return error.NoUserDataDir;

        const dir_span = std.mem.span(user_data_dir);
        const vimp_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ dir_span, "vimp" });
        defer self.allocator.free(vimp_dir);

        // Ensure directory exists
        std.fs.makeDirAbsolute(vimp_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return std.fs.path.join(self.allocator, &[_][]const u8{ vimp_dir, "recent.json" });
    }

    pub fn load(self: *RecentManager) !void {
        // Clear existing
        for (self.paths.items) |path| {
            self.allocator.free(path);
        }
        self.paths.clearRetainingCapacity();

        const path = self.getStoragePath() catch return; // Ignore error if path setup fails
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

        const parsed = try std.json.parseFromSlice([]const []const u8, self.allocator, buffer, .{});
        defer parsed.deinit();

        for (parsed.value) |p| {
            const copy = try self.allocator.dupe(u8, p);
            try self.paths.append(self.allocator, copy);
        }
    }

    pub fn save(self: *RecentManager) !void {
        const path = try self.getStoragePath();
        defer self.allocator.free(path);

        // Buffer JSON in memory
        var list = std.ArrayList(u8){};
        defer list.deinit(self.allocator);

        // Use fmt to serialize with {f} specifier
        try list.writer(self.allocator).print("{f}", .{std.json.fmt(self.paths.items, .{})});

        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();

        try file.writeAll(list.items);
    }

    pub fn add(self: *RecentManager, path: []const u8) !void {
        // Remove existing
        var i: usize = 0;
        while (i < self.paths.items.len) {
            if (std.mem.eql(u8, self.paths.items[i], path)) {
                const old = self.paths.orderedRemove(i);
                self.allocator.free(old);
            } else {
                i += 1;
            }
        }

        // Insert at front
        const copy = try self.allocator.dupe(u8, path);
        try self.paths.insert(self.allocator, 0, copy);

        // Trim
        while (self.paths.items.len > 10) {
            if (self.paths.pop()) |old| {
                self.allocator.free(old);
            }
        }

        // Save
        self.save() catch |err| {
            std.debug.print("Failed to save recent files: {}\n", .{err});
        };
    }
};

test "RecentManager logic" {
    const allocator = std.testing.allocator;
    var mgr = RecentManager.init(allocator);
    defer mgr.deinit();

    try mgr.add("file1.png");
    try std.testing.expectEqual(@as(usize, 1), mgr.paths.items.len);
    try std.testing.expectEqualStrings("file1.png", mgr.paths.items[0]);

    try mgr.add("file2.png");
    try std.testing.expectEqual(@as(usize, 2), mgr.paths.items.len);
    try std.testing.expectEqualStrings("file2.png", mgr.paths.items[0]);
    try std.testing.expectEqualStrings("file1.png", mgr.paths.items[1]);

    try mgr.add("file1.png"); // Re-add file1
    try std.testing.expectEqual(@as(usize, 2), mgr.paths.items.len);
    try std.testing.expectEqualStrings("file1.png", mgr.paths.items[0]); // Moved to front
    try std.testing.expectEqualStrings("file2.png", mgr.paths.items[1]);
}

test "RecentManager persistence" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const db_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "recent_test.json" });
    defer allocator.free(db_path);

    {
        var mgr = RecentManager.init(allocator);
        defer mgr.deinit();
        try mgr.setCustomPath(db_path);

        try mgr.add("test_file_1.png");
        try mgr.add("test_file_2.png");
    }

    {
        var mgr = RecentManager.init(allocator);
        defer mgr.deinit();
        try mgr.setCustomPath(db_path);

        try mgr.load();
        try std.testing.expectEqual(@as(usize, 2), mgr.paths.items.len);
        try std.testing.expectEqualStrings("test_file_2.png", mgr.paths.items[0]);
        try std.testing.expectEqualStrings("test_file_1.png", mgr.paths.items[1]);
    }
}
