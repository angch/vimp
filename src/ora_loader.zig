const std = @import("std");
const c = @import("c.zig").c;

pub const OraLayer = struct {
    name: []const u8 = "Layer",
    src: []const u8 = "",
    x: c_int = 0,
    y: c_int = 0,
    visible: bool = true,
    opacity: f64 = 1.0,
    composite_op: []const u8 = "svg:src-over",
};

pub const OraProject = struct {
    w: c_int = 0,
    h: c_int = 0,
    layers: std.ArrayList(OraLayer),
    temp_dir: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *OraProject) void {
        // Clean up layers
        for (self.layers.items) |*l| {
            self.allocator.free(l.name);
            self.allocator.free(l.src);
            self.allocator.free(l.composite_op);
        }
        self.layers.deinit(self.allocator);

        // Delete temp dir
        std.fs.cwd().deleteTree(self.temp_dir) catch |err| {
            std.debug.print("Failed to delete temp dir {s}: {}\n", .{self.temp_dir, err});
        };
        self.allocator.free(self.temp_dir);
    }
};

pub const OraLoader = struct {
    fn unzip(allocator: std.mem.Allocator, zip_path: []const u8, dest_dir: []const u8) !void {
        const args = [_][]const u8{ "unzip", "-q", "-d", dest_dir, zip_path };

        var proc = std.process.Child.init(&args, allocator);
        proc.stdin_behavior = .Ignore;
        proc.stdout_behavior = .Ignore;
        proc.stderr_behavior = .Ignore;

        const term = try proc.spawnAndWait();
        switch (term) {
            .Exited => |code| {
                if (code != 0) return error.UnzipFailed;
            },
            else => return error.UnzipFailed,
        }
    }

    fn parseAttribute(allocator: std.mem.Allocator, key: []const u8, value: []const u8, layer: *OraLayer) !void {
        if (std.mem.eql(u8, key, "name")) {
            layer.name = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "src")) {
            layer.src = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "x")) {
            layer.x = std.fmt.parseInt(c_int, value, 10) catch 0;
        } else if (std.mem.eql(u8, key, "y")) {
            layer.y = std.fmt.parseInt(c_int, value, 10) catch 0;
        } else if (std.mem.eql(u8, key, "visibility")) {
            layer.visible = !std.mem.eql(u8, value, "hidden");
        } else if (std.mem.eql(u8, key, "opacity")) {
            layer.opacity = std.fmt.parseFloat(f64, value) catch 1.0;
        } else if (std.mem.eql(u8, key, "composite-op")) {
            layer.composite_op = try allocator.dupe(u8, value);
        }
    }

    fn parseImageAttribute(key: []const u8, value: []const u8, img: *OraProject) void {
        if (std.mem.eql(u8, key, "w")) {
            img.w = std.fmt.parseInt(c_int, value, 10) catch 0;
        } else if (std.mem.eql(u8, key, "h")) {
            img.h = std.fmt.parseInt(c_int, value, 10) catch 0;
        }
    }

    fn parseStackXml(allocator: std.mem.Allocator, content: []const u8, project: *OraProject) !void {
        var it = std.mem.tokenizeAny(u8, content, "<>");
        while (it.next()) |token| {
            // Trim
            const trimmed = std.mem.trim(u8, token, " \t\r\n");
            if (trimmed.len == 0) continue;

            var parts = std.mem.tokenizeAny(u8, trimmed, " \t\r\n");
            const tag = parts.next() orelse continue;

            if (std.mem.eql(u8, tag, "image")) {
                // Parse attributes manually
                const rest_of_token = trimmed[tag.len..];
                var i: usize = 0;
                while (i < rest_of_token.len) {
                    if (std.ascii.isWhitespace(rest_of_token[i])) {
                        i += 1;
                        continue;
                    }
                    const start = i;
                    while (i < rest_of_token.len and rest_of_token[i] != '=') : (i += 1) {}
                    if (i >= rest_of_token.len) break;
                    const key = rest_of_token[start..i];
                    i += 1; // skip =
                    if (i >= rest_of_token.len) break;

                    if (rest_of_token[i] == '"') {
                        i += 1;
                        const val_start = i;
                        while (i < rest_of_token.len and rest_of_token[i] != '"') : (i += 1) {}
                        const val = rest_of_token[val_start..i];
                        if (i < rest_of_token.len) i += 1;
                        parseImageAttribute(key, val, project);
                    }
                }
            } else if (std.mem.eql(u8, tag, "layer")) {
                var layer = OraLayer{
                    .name = try allocator.dupe(u8, "Layer"),
                    .src = try allocator.dupe(u8, ""),
                    .composite_op = try allocator.dupe(u8, "svg:src-over"),
                };
                errdefer {
                    allocator.free(layer.name);
                    allocator.free(layer.src);
                    allocator.free(layer.composite_op);
                }

                const rest_of_token = trimmed[tag.len..];
                var i: usize = 0;
                while (i < rest_of_token.len) {
                    if (std.ascii.isWhitespace(rest_of_token[i])) {
                        i += 1;
                        continue;
                    }
                    const start = i;
                    while (i < rest_of_token.len and rest_of_token[i] != '=') : (i += 1) {}
                    if (i >= rest_of_token.len) break;
                    const key = rest_of_token[start..i];
                    i += 1; // skip =
                    if (i >= rest_of_token.len) break;

                    if (rest_of_token[i] == '"') {
                        i += 1;
                        const val_start = i;
                        while (i < rest_of_token.len and rest_of_token[i] != '"') : (i += 1) {}
                        const val = rest_of_token[val_start..i];
                        if (i < rest_of_token.len) i += 1;

                        // If key exists in struct, clean up old value if string
                        if (std.mem.eql(u8, key, "name")) allocator.free(layer.name);
                        if (std.mem.eql(u8, key, "src")) allocator.free(layer.src);
                        if (std.mem.eql(u8, key, "composite-op")) allocator.free(layer.composite_op);

                        try parseAttribute(allocator, key, val, &layer);
                    }
                }
                try project.layers.append(allocator, layer);
            }
        }
    }

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !OraProject {
        // Create temp dir
        const rnd = std.time.nanoTimestamp();
        const tmp_name = try std.fmt.allocPrint(allocator, "vimp_ora_{d}", .{rnd});
        const tmp_dir_c = c.g_get_tmp_dir();
        const tmp_base = std.mem.span(tmp_dir_c);
        const temp_dir = try std.fs.path.join(allocator, &[_][]const u8{ tmp_base, tmp_name });
        allocator.free(tmp_name);
        errdefer allocator.free(temp_dir);

        std.fs.cwd().makePath(temp_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
        // Ensure cleanup if fail
        errdefer {
            std.fs.cwd().deleteTree(temp_dir) catch {};
        }

        // Unzip
        try unzip(allocator, path, temp_dir);

        // Read stack.xml
        const stack_path = try std.fs.path.join(allocator, &[_][]const u8{ temp_dir, "stack.xml" });
        defer allocator.free(stack_path);

        const xml_content = try std.fs.cwd().readFileAlloc(allocator, stack_path, 1024 * 1024); // 1MB limit for stack.xml
        defer allocator.free(xml_content);

        var project = OraProject{
            .allocator = allocator,
            .temp_dir = temp_dir, // Transfer ownership
            .layers = std.ArrayList(OraLayer){},
        };

        try parseStackXml(allocator, xml_content, &project);

        return project;
    }

    fn escapeXml(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        var list = std.ArrayList(u8){};
        errdefer list.deinit(allocator);
        var writer = list.writer(allocator);
        for (input) |char| {
            switch (char) {
                '<' => try writer.writeAll("&lt;"),
                '>' => try writer.writeAll("&gt;"),
                '&' => try writer.writeAll("&amp;"),
                '"' => try writer.writeAll("&quot;"),
                '\'' => try writer.writeAll("&apos;"),
                else => try writer.writeByte(char),
            }
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn writeStackXml(allocator: std.mem.Allocator, project: OraProject, path: []const u8) !void {
        var list = std.ArrayList(u8){};
        defer list.deinit(allocator);
        var writer = list.writer(allocator);

        try writer.print("<image w=\"{d}\" h=\"{d}\">\n", .{ project.w, project.h });
        try writer.writeAll("  <stack>\n");

        for (project.layers.items) |layer| {
            const vis = if (layer.visible) "visible" else "hidden";
            const name_esc = try escapeXml(allocator, layer.name);
            defer allocator.free(name_esc);

            try writer.print("    <layer name=\"{s}\" src=\"{s}\" x=\"{d}\" y=\"{d}\" visibility=\"{s}\" opacity=\"{d}\" composite-op=\"{s}\" />\n",
                .{ name_esc, layer.src, layer.x, layer.y, vis, layer.opacity, layer.composite_op });
        }

        try writer.writeAll("  </stack>\n");
        try writer.writeAll("</image>\n");

        try std.fs.cwd().writeFile(.{ .sub_path = path, .data = list.items });
    }

    pub fn createOraZip(allocator: std.mem.Allocator, source_dir: []const u8, dest_path: []const u8) !void {
        // Resolve absolute destination path
        var full_dest_path: []u8 = undefined;
        if (std.fs.path.isAbsolute(dest_path)) {
            full_dest_path = try allocator.dupe(u8, dest_path);
        } else {
            const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
            defer allocator.free(cwd_path);
            full_dest_path = try std.fs.path.join(allocator, &[_][]const u8{ cwd_path, dest_path });
        }
        defer allocator.free(full_dest_path);

        // Remove existing file
        std.fs.cwd().deleteFile(full_dest_path) catch {};

        // 1. Zip mimetype (store uncompressed)
        // zip -0 -q -X dest mimetype
        {
            const args = [_][]const u8{ "zip", "-0", "-q", "-X", full_dest_path, "mimetype" };
            var proc = std.process.Child.init(&args, allocator);
            proc.cwd = source_dir;
            proc.stdin_behavior = .Ignore;
            proc.stdout_behavior = .Ignore;
            proc.stderr_behavior = .Ignore;
            const term = try proc.spawnAndWait();
            switch (term) {
                .Exited => |code| if (code != 0) return error.ZipFailed,
                else => return error.ZipFailed,
            }
        }

        // 2. Zip rest (stack.xml and data/)
        // zip -r -q dest stack.xml data
        {
            const args = [_][]const u8{ "zip", "-r", "-q", full_dest_path, "stack.xml", "data" };
            var proc = std.process.Child.init(&args, allocator);
            proc.cwd = source_dir;
            proc.stdin_behavior = .Ignore;
            proc.stdout_behavior = .Ignore;
            proc.stderr_behavior = .Ignore;
            const term = try proc.spawnAndWait();
            switch (term) {
                .Exited => |code| if (code != 0) return error.ZipFailed,
                else => return error.ZipFailed,
            }
        }
    }
};
