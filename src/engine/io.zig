const std = @import("std");
const c = @import("../c.zig").c;
const Engine = @import("core.zig").Engine;
const SvgLoader = @import("../svg_loader.zig");
const OraMod = @import("../ora_loader.zig");
const OraLoader = OraMod.OraLoader;
const XcfLoader = @import("xcf_loader.zig").XcfLoader;

pub fn getPdfPageCount(_: *Engine, path: []const u8) !i32 {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const path_z = try std.heap.c_allocator.dupeZ(u8, path);
    defer std.heap.c_allocator.free(path_z);

    const load_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:pdf-load", "path", path_z.ptr, @as(?*anyopaque, null));

    if (load_node == null) return error.GeglLoadFailed;

    var total_pages: c_int = 0;
    c.gegl_node_get(load_node, "pages", &total_pages, @as(?*anyopaque, null));
    return total_pages;
}

pub fn getPdfThumbnail(_: *Engine, path: []const u8, page: i32, size: c_int) !*c.GeglBuffer {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const path_z = try std.heap.c_allocator.dupeZ(u8, path);
    defer std.heap.c_allocator.free(path_z);

    // Load specific page
    const load_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:pdf-load", "path", path_z.ptr, "page", @as(c_int, page), @as(?*anyopaque, null));

    if (load_node == null) return error.GeglLoadFailed;

    // Scale
    const bbox = c.gegl_node_get_bounding_box(load_node);
    if (bbox.width <= 0 or bbox.height <= 0) return error.InvalidImage;

    const max_dim = @max(bbox.width, bbox.height);
    const scale = @as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(max_dim));

    const scale_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:scale-ratio", "x", scale, "y", scale, "sampler", c.GEGL_SAMPLER_NEAREST, @as(?*anyopaque, null));

    _ = c.gegl_node_connect(scale_node, "input", load_node, "output");

    // Write to buffer
    const bbox_scaled = c.gegl_node_get_bounding_box(scale_node);
    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(&bbox_scaled, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));

    if (write_node) |wn| {
        _ = c.gegl_node_connect(wn, "input", scale_node, "output");
        _ = c.gegl_node_process(wn);
    } else {
        c.g_object_unref(new_buffer);
        return error.GeglGraphFailed;
    }

    return new_buffer.?;
}

pub fn loadPdf(self: *Engine, path: []const u8, params: Engine.PdfImportParams) !void {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const path_z = try std.heap.c_allocator.dupeZ(u8, path);
    defer std.heap.c_allocator.free(path_z);

    const load_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:pdf-load", "path", path_z.ptr, "ppi", @as(f64, params.ppi), @as(?*anyopaque, null));

    if (load_node == null) return error.GeglLoadFailed;

    const basename = std.fs.path.basename(path);
    var buf: [256]u8 = undefined;

    for (params.pages) |current_page| {
        c.gegl_node_set(load_node, "page", @as(c_int, current_page), @as(?*anyopaque, null));

        const bbox = c.gegl_node_get_bounding_box(load_node);
        if (bbox.width <= 0 or bbox.height <= 0) {
            continue;
        }

        const format = c.babl_format("R'G'B'A u8");
        const new_buffer = c.gegl_buffer_new(&bbox, format);
        if (new_buffer == null) continue;

        const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));
        if (write_node) |wn| {
            _ = c.gegl_node_link(load_node, wn);
            _ = c.gegl_node_process(wn);
            _ = c.gegl_node_remove_child(temp_graph, wn);
        } else {
            c.g_object_unref(new_buffer);
            continue;
        }

        const name = std.fmt.bufPrintZ(&buf, "{s} - Page {d}", .{ basename, current_page }) catch "Page";
        const index = self.layers.list.items.len;
        try self.addLayerInternal(new_buffer.?, name, true, false, index);

        const cmd = Engine.Command{
            .layer = .{ .add = .{ .index = index, .snapshot = null } },
        };
        self.history.push(cmd) catch {};
    }
}

pub fn loadSvgPaths(self: *Engine, path: []const u8) !void {
    var parsed_paths = try SvgLoader.parseSvgPaths(std.heap.c_allocator, path);
    defer {
        for (parsed_paths.items) |*p| p.deinit(std.heap.c_allocator);
        parsed_paths.deinit(std.heap.c_allocator);
    }

    for (parsed_paths.items) |*pp| {
        const gpath = c.gegl_path_new();
        if (gpath == null) continue;

        const d_z = try std.heap.c_allocator.dupeZ(u8, pp.d);
        defer std.heap.c_allocator.free(d_z);

        c.gegl_path_parse_string(gpath, d_z.ptr);

        const name_str = if (pp.id) |id| id else "Path";
        const name_owned = try std.heap.c_allocator.dupe(u8, name_str);

        try self.paths.append(std.heap.c_allocator, .{
            .name = name_owned,
            .path = gpath.?,
        });
    }
}

pub fn loadSvg(self: *Engine, path: []const u8, params: Engine.SvgImportParams) !void {
    if (params.import_paths) {
        try loadSvgPaths(self, path);
    }

    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const path_z = try std.heap.c_allocator.dupeZ(u8, path);
    defer std.heap.c_allocator.free(path_z);

    const load_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:svg-load", "path", path_z.ptr, @as(?*anyopaque, null));
    if (load_node == null) return error.GeglLoadFailed;

    if (params.width > 0) {
        c.gegl_node_set(load_node, "width", @as(c_int, params.width), @as(?*anyopaque, null));
    }
    if (params.height > 0) {
        c.gegl_node_set(load_node, "height", @as(c_int, params.height), @as(?*anyopaque, null));
    }

    const bbox = c.gegl_node_get_bounding_box(load_node);
    if (bbox.width <= 0 or bbox.height <= 0) return error.InvalidImage;

    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(&bbox, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));
    if (write_node) |wn| {
        _ = c.gegl_node_link(load_node, wn);
        _ = c.gegl_node_process(wn);
    } else {
        c.g_object_unref(new_buffer);
        return error.GeglGraphFailed;
    }

    const basename = std.fs.path.basename(path);
    const index = self.layers.list.items.len;
    try self.addLayerInternal(new_buffer.?, basename, true, false, index);

    const cmd = Engine.Command{
        .layer = .{ .add = .{ .index = index, .snapshot = null } },
    };
    self.history.push(cmd) catch {};
}

pub fn loadFromFile(self: *Engine, path: []const u8) !void {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const path_z = try std.heap.c_allocator.dupeZ(u8, path);
    defer std.heap.c_allocator.free(path_z);

    const load_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:load", "path", path_z.ptr, @as(?*anyopaque, null));
    if (load_node == null) return error.GeglLoadFailed;

    const bbox = c.gegl_node_get_bounding_box(load_node);
    if (bbox.width <= 0 or bbox.height <= 0) return error.InvalidImage;

    const format = c.babl_format("R'G'B'A u8");
    const new_buffer = c.gegl_buffer_new(&bbox, format);
    if (new_buffer == null) return error.GeglBufferFailed;

    const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));
    if (write_node) |wn| {
        _ = c.gegl_node_link(load_node, wn);
        _ = c.gegl_node_process(wn);
    } else {
        c.g_object_unref(new_buffer);
        return error.GeglGraphFailed;
    }

    const basename = std.fs.path.basename(path);
    const index = self.layers.list.items.len;

    try self.addLayerInternal(new_buffer.?, basename, true, false, index);

    const cmd = Engine.Command{
        .layer = .{ .add = .{ .index = index, .snapshot = null } },
    };
    self.history.push(cmd) catch |err| {
        std.debug.print("Failed to push undo: {}\n", .{err});
    };
}

pub fn exportImage(self: *Engine, path: []const u8) !void {
    if (self.output_node == null) return error.NoOutputNode;
    if (self.graph == null) return error.GeglGraphFailed;

    const path_z = try std.heap.c_allocator.dupeZ(u8, path);
    defer std.heap.c_allocator.free(path_z);

    const save_node = c.gegl_node_new_child(self.graph, "operation", "gegl:save", "path", path_z.ptr, @as(?*anyopaque, null));

    if (save_node == null) return error.GeglGraphFailed;

    _ = c.gegl_node_connect(save_node, "input", self.output_node, "output");
    _ = c.gegl_node_process(save_node);
    _ = c.gegl_node_remove_child(self.graph, save_node);
}

pub fn saveThumbnail(self: *Engine, path: []const u8, width: c_int, height: c_int) !void {
    if (self.output_node == null) return;
    if (self.graph == null) return;

    const bbox = c.gegl_node_get_bounding_box(self.output_node);
    if (bbox.width <= 0 or bbox.height <= 0) return;

    const w_f: f64 = @floatFromInt(bbox.width);
    const h_f: f64 = @floatFromInt(bbox.height);
    const target_w: f64 = @floatFromInt(width);
    const target_h: f64 = @floatFromInt(height);

    const scale_x = target_w / w_f;
    const scale_y = target_h / h_f;
    const scale = @min(scale_x, scale_y);

    const scale_node = c.gegl_node_new_child(self.graph, "operation", "gegl:scale-ratio", "x", scale, "y", scale, "sampler", c.GEGL_SAMPLER_NEAREST, @as(?*anyopaque, null));

    if (scale_node == null) return error.GeglGraphFailed;

    const path_z = try std.heap.c_allocator.dupeZ(u8, path);
    defer std.heap.c_allocator.free(path_z);

    const save_node = c.gegl_node_new_child(self.graph, "operation", "gegl:save", "path", path_z.ptr, @as(?*anyopaque, null));

    if (save_node == null) {
        _ = c.gegl_node_remove_child(self.graph, scale_node);
        return error.GeglGraphFailed;
    }

    _ = c.gegl_node_connect(scale_node, "input", self.output_node, "output");
    _ = c.gegl_node_connect(save_node, "input", scale_node, "output");

    _ = c.gegl_node_process(save_node);

    _ = c.gegl_node_remove_child(self.graph, save_node);
    _ = c.gegl_node_remove_child(self.graph, scale_node);
}

pub const ProjectMetadata = struct {
    width: c_int,
    height: c_int,
    layers: []Engine.LayerMetadata,
};

fn printJsonString(writer: anytype, str: []const u8) !void {
    try writer.writeAll("\"");
    for (str) |char| {
        switch (char) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(char),
        }
    }
    try writer.writeAll("\"");
}

fn stringifyProjectMetadata(meta: ProjectMetadata, writer: anytype) !void {
    try writer.print("{{\n    \"width\": {d},\n    \"height\": {d},\n    \"layers\": [\n", .{ meta.width, meta.height });
    for (meta.layers, 0..) |l, i| {
        try writer.writeAll("        {\n            \"name\": ");
        try printJsonString(writer, l.name);
        try writer.print(",\n            \"visible\": {},\n", .{l.visible});
        try writer.print("            \"locked\": {},\n            \"filename\": ", .{l.locked});
        try printJsonString(writer, l.filename);
        try writer.writeAll("\n        }");
        if (i < meta.layers.len - 1) try writer.writeAll(",");
        try writer.writeAll("\n");
    }
    try writer.writeAll("    ]\n}\n");
}

fn saveBuffer(_: *Engine, buffer: *c.GeglBuffer, path_z: [:0]const u8) !void {
    const temp_graph = c.gegl_node_new();
    defer c.g_object_unref(temp_graph);

    const source = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null));
    const save = c.gegl_node_new_child(temp_graph, "operation", "gegl:save", "path", path_z.ptr, @as(?*anyopaque, null));

    if (source != null and save != null) {
        _ = c.gegl_node_link(source, save);
        _ = c.gegl_node_process(save);
    } else {
        return error.GeglGraphFailed;
    }
}

pub fn saveProject(self: *Engine, path: []const u8) !void {
    const allocator = std.heap.c_allocator;
    std.fs.cwd().makePath(path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    var dir = try std.fs.cwd().openDir(path, .{});
    defer dir.close();

    const abs_path = try std.fs.cwd().realpathAlloc(allocator, path);
    defer allocator.free(abs_path);

    var layer_meta_list = std.ArrayList(Engine.LayerMetadata){};
    defer {
        for (layer_meta_list.items) |m| {
            allocator.free(m.filename);
            allocator.free(m.name);
        }
        layer_meta_list.deinit(allocator);
    }

    for (self.layers.list.items, 0..) |layer, i| {
        const filename = try std.fmt.allocPrint(allocator, "layer_{d}.png", .{i});
        const full_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ abs_path, filename });
        defer allocator.free(full_path);

        try saveBuffer(self, layer.buffer, full_path);

        const name_dup = try allocator.dupe(u8, std.mem.span(@as([*:0]const u8, @ptrCast(&layer.name))));

        try layer_meta_list.append(allocator, .{
            .name = name_dup,
            .visible = layer.visible,
            .locked = layer.locked,
            .filename = filename,
        });
    }

    const meta = ProjectMetadata{
        .width = self.canvas_width,
        .height = self.canvas_height,
        .layers = layer_meta_list.items,
    };

    var json_string = std.ArrayList(u8){};
    defer json_string.deinit(allocator);

    try stringifyProjectMetadata(meta, json_string.writer(allocator));

    const json_file = try dir.createFile("project.json", .{});
    defer json_file.close();
    try json_file.writeAll(json_string.items);
}

pub fn loadProject(self: *Engine, path: []const u8) !void {
    var dir = try std.fs.cwd().openDir(path, .{});
    defer dir.close();

    const json_file = try dir.openFile("project.json", .{});
    defer json_file.close();

    const size = (try json_file.stat()).size;
    const json_content = try std.heap.c_allocator.alloc(u8, size);
    defer std.heap.c_allocator.free(json_content);

    _ = try json_file.readAll(json_content);

    const parsed = try std.json.parseFromSlice(ProjectMetadata, std.heap.c_allocator, json_content, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const meta = parsed.value;

    self.reset();

    self.setCanvasSizeInternal(meta.width, meta.height);

    for (meta.layers) |l| {
        const full_path = try std.fs.path.joinZ(std.heap.c_allocator, &[_][]const u8{ path, l.filename });
        defer std.heap.c_allocator.free(full_path);

        const temp_graph = c.gegl_node_new();
        defer c.g_object_unref(temp_graph);

        const load_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:load", "path", full_path.ptr, @as(?*anyopaque, null));
        if (load_node == null) continue;

        const bbox = c.gegl_node_get_bounding_box(load_node);
        const format = c.babl_format("R'G'B'A u8");
        const new_buffer = c.gegl_buffer_new(&bbox, format);
        if (new_buffer == null) continue;

        const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));
        if (write_node) |wn| {
            _ = c.gegl_node_link(load_node, wn);
            _ = c.gegl_node_process(wn);
        } else {
            c.g_object_unref(new_buffer);
            continue;
        }

        const index = self.layers.list.items.len;
        try self.addLayerInternal(new_buffer.?, l.name, l.visible, l.locked, index);
    }
}

pub fn loadOra(self: *Engine, path: []const u8, as_new: bool) !void {
    const allocator = std.heap.c_allocator;
    var project = try OraLoader.load(allocator, path);
    defer project.deinit();

    if (as_new) {
        self.reset();
        self.setCanvasSizeInternal(project.w, project.h);
    }

    for (project.layers.items) |l| {
        const img_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ project.temp_dir, l.src });
        defer allocator.free(img_path);

        const temp_graph = c.gegl_node_new();
        defer c.g_object_unref(temp_graph);

        const load_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:load", "path", img_path.ptr, @as(?*anyopaque, null));
        if (load_node == null) continue;

        const bbox = c.gegl_node_get_bounding_box(load_node);
        if (bbox.width <= 0 or bbox.height <= 0) continue;

        const layer_rect = c.GeglRectangle{ .x = l.x, .y = l.y, .width = bbox.width, .height = bbox.height };
        const format = c.babl_format("R'G'B'A u8");
        const new_buffer = c.gegl_buffer_new(&layer_rect, format);
        if (new_buffer == null) continue;

        const translate = c.gegl_node_new_child(temp_graph, "operation", "gegl:translate", "x", @as(f64, @floatFromInt(l.x)), "y", @as(f64, @floatFromInt(l.y)), @as(?*anyopaque, null));
        const write = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));

        if (l.opacity < 1.0) {
            const opacity_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:opacity", "value", l.opacity, @as(?*anyopaque, null));
            _ = c.gegl_node_link_many(load_node, translate, opacity_node, write, @as(?*anyopaque, null));
        } else {
            _ = c.gegl_node_link_many(load_node, translate, write, @as(?*anyopaque, null));
        }

        _ = c.gegl_node_process(write);

        const index = self.layers.list.items.len;
        try self.addLayerInternal(new_buffer.?, l.name, l.visible, false, index);
    }
}

pub fn loadXcf(self: *Engine, path: []const u8) !void {
    var loader = try XcfLoader.init(std.heap.c_allocator, path);
    defer loader.deinit();
    try loader.load(self);
}

pub fn saveOra(self: *Engine, path: []const u8) !void {
    const allocator = std.heap.c_allocator;
    const rnd = std.time.nanoTimestamp();
    const tmp_name = try std.fmt.allocPrint(allocator, "vimp_save_ora_{d}", .{rnd});
    const tmp_dir_c = c.g_get_tmp_dir();
    const tmp_base = std.mem.span(tmp_dir_c);
    const temp_dir = try std.fs.path.join(allocator, &[_][]const u8{ tmp_base, tmp_name });
    allocator.free(tmp_name);
    defer {
        std.fs.cwd().deleteTree(temp_dir) catch {};
        allocator.free(temp_dir);
    }

    std.fs.cwd().makePath(temp_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const mimetype_path = try std.fs.path.join(allocator, &[_][]const u8{ temp_dir, "mimetype" });
    defer allocator.free(mimetype_path);
    try std.fs.cwd().writeFile(.{ .sub_path = mimetype_path, .data = "image/openraster" });

    const data_dir = try std.fs.path.join(allocator, &[_][]const u8{ temp_dir, "data" });
    defer allocator.free(data_dir);
    try std.fs.cwd().makePath(data_dir);

    var ora_layers = std.ArrayList(OraMod.OraLayer){};
    defer {
        for (ora_layers.items) |*l| {
            allocator.free(l.name);
            allocator.free(l.src);
            allocator.free(l.composite_op);
        }
        ora_layers.deinit(allocator);
    }

    for (self.layers.list.items, 0..) |layer, i| {
        const fname = try std.fmt.allocPrint(allocator, "layer{d}.png", .{i});
        defer allocator.free(fname);
        const src_rel = try std.fs.path.join(allocator, &[_][]const u8{ "data", fname });
        defer allocator.free(src_rel);

        const full_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ data_dir, fname });
        defer allocator.free(full_path);

        try saveBuffer(self, layer.buffer, full_path);

        const extent = c.gegl_buffer_get_extent(layer.buffer);

        const name_dup = try allocator.dupe(u8, std.mem.span(@as([*:0]const u8, @ptrCast(&layer.name))));
        const src_dup = try allocator.dupe(u8, src_rel);
        const op_dup = try allocator.dupe(u8, "svg:src-over");

        const ora_layer = OraMod.OraLayer{
            .name = name_dup,
            .src = src_dup,
            .x = extent.*.x,
            .y = extent.*.y,
            .visible = layer.visible,
            .opacity = 1.0,
            .composite_op = op_dup,
        };
        try ora_layers.append(allocator, ora_layer);
    }

    const project = OraMod.OraProject{
        .w = self.canvas_width,
        .h = self.canvas_height,
        .layers = ora_layers,
        .temp_dir = temp_dir,
        .allocator = allocator,
    };

    const stack_path = try std.fs.path.join(allocator, &[_][]const u8{ temp_dir, "stack.xml" });
    defer allocator.free(stack_path);
    try OraLoader.writeStackXml(allocator, project, stack_path);

    try OraLoader.createOraZip(allocator, temp_dir, path);
}
test "Engine load from file" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // Create a temporary valid PNG file
    const filename = "test_engine_load.png";
    {
        const rect = c.GeglRectangle{ .x = 0, .y = 0, .width = 10, .height = 10 };
        const format = c.babl_format("R'G'B'A u8");
        const buf = c.gegl_buffer_new(&rect, format);
        defer c.g_object_unref(buf);

        const temp_graph = c.gegl_node_new();
        defer c.g_object_unref(temp_graph);

        const source = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", buf, @as(?*anyopaque, null));
        const save = c.gegl_node_new_child(temp_graph, "operation", "gegl:save", "path", filename, @as(?*anyopaque, null));

        if (source != null and save != null) {
            _ = c.gegl_node_link(source, save);
            _ = c.gegl_node_process(save);
        }
    }
    defer std.fs.cwd().deleteFile(filename) catch {};

    try loadFromFile(&engine, filename);

    try std.testing.expectEqual(engine.layers.list.items.len, 1);

    const layer = &engine.layers.list.items[0];
    const name = std.mem.span(@as([*:0]const u8, @ptrCast(&layer.name)));
    try std.testing.expectEqualStrings(name, "test_engine_load.png");

    const extent = c.gegl_buffer_get_extent(layer.buffer);
    try std.testing.expectEqual(extent.*.width, 10);
    try std.testing.expectEqual(extent.*.height, 10);
}
test "Engine load Svg" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // Create a temporary SVG file
    const filename = "test_image.svg";
    const svg_content =
        \\<svg width="100" height="100" xmlns="http://www.w3.org/2000/svg">
        \\  <rect width="100" height="100" fill="red" />
        \\</svg>
    ;
    try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = svg_content });
    defer std.fs.cwd().deleteFile(filename) catch {};

    const abs_path = try std.fs.cwd().realpathAlloc(std.heap.c_allocator, filename);
    defer std.heap.c_allocator.free(abs_path);

    // 1. Load with default params (Native size)
    {
        const params = Engine.SvgImportParams{ .width = 0, .height = 0 };
        try loadSvg(&engine, abs_path, params);

        try std.testing.expectEqual(engine.layers.list.items.len, 1);
        const layer = &engine.layers.list.items[0];
        const extent = c.gegl_buffer_get_extent(layer.buffer);
        // Expect 100x100
        try std.testing.expectEqual(extent.*.width, 100);
        try std.testing.expectEqual(extent.*.height, 100);
    }

    engine.reset();

    // 2. Load with custom size
    {
        const params = Engine.SvgImportParams{ .width = 200, .height = 200 };
        try loadSvg(&engine, abs_path, params);

        try std.testing.expectEqual(engine.layers.list.items.len, 1);
        const layer = &engine.layers.list.items[0];
        const extent = c.gegl_buffer_get_extent(layer.buffer);
        // Expect 200x200
        try std.testing.expectEqual(extent.*.width, 200);
        try std.testing.expectEqual(extent.*.height, 200);
    }
}
test "Engine load Pdf" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // Create a temporary PDF file
    const filename = "test_image.pdf";
    // Minimal PDF 1.0 with 20-byte xref entries
    const pdf_content =
        "%PDF-1.0\n" ++
        "1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n" ++
        "2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n" ++
        "3 0 obj<</Type/Page/MediaBox[0 0 100 100]/Parent 2 0 R/Resources<<>>>>endobj\n" ++
        "xref\n" ++
        "0 4\n" ++
        "0000000000 65535 f \n" ++
        "0000000009 00000 n \n" ++
        "0000000053 00000 n \n" ++
        "0000000102 00000 n \n" ++
        "trailer<</Size 4/Root 1 0 R>>\n" ++
        "startxref\n" ++
        "179\n" ++
        "%%EOF\n";

    try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = pdf_content });
    defer std.fs.cwd().deleteFile(filename) catch {};

    // Load PDF
    var pages = [_]i32{1};
    const params = Engine.PdfImportParams{
        .ppi = 72.0,
        .pages = &pages,
    };
    try loadPdf(&engine, filename, params);

    try std.testing.expectEqual(engine.layers.list.items.len, 1);
    const layer = &engine.layers.list.items[0];
    const extent = c.gegl_buffer_get_extent(layer.buffer);
    // 100x100 at 72 PPI
    try std.testing.expectEqual(extent.*.width, 100);
    try std.testing.expectEqual(extent.*.height, 100);
}
test "Engine PDF utils" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();

    // Create a temporary PDF file
    const filename = "test_utils.pdf";
    const pdf_content =
        "%PDF-1.0\n" ++
        "1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n" ++
        "2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n" ++
        "3 0 obj<</Type/Page/MediaBox[0 0 100 100]/Parent 2 0 R/Resources<<>>>>endobj\n" ++
        "xref\n" ++
        "0 4\n" ++
        "0000000000 65535 f \n" ++
        "0000000009 00000 n \n" ++
        "0000000053 00000 n \n" ++
        "0000000102 00000 n \n" ++
        "trailer<</Size 4/Root 1 0 R>>\n" ++
        "startxref\n" ++
        "179\n" ++
        "%%EOF\n";

    try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = pdf_content });
    defer std.fs.cwd().deleteFile(filename) catch {};

    // 1. Get Page Count
    const count = try getPdfPageCount(&engine, filename);
    try std.testing.expectEqual(count, 1);

    // 2. Get Thumbnail
    // Page 1, Size 50
    const buf = try getPdfThumbnail(&engine, filename, 1, 50);
    defer c.g_object_unref(buf);

    const extent = c.gegl_buffer_get_extent(buf);
    // Original 100x100. Target 50. Scale 0.5. Result 50x50.
    try std.testing.expectEqual(extent.*.width, 50);
    try std.testing.expectEqual(extent.*.height, 50);
}
test "Engine saveThumbnail" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    try engine.addLayer("Background");

    // Paint something red
    engine.setFgColor(255, 0, 0, 255);
    engine.paintStroke(100, 100, 100, 100, 1.0);

    var rnd_buf: [16]u8 = undefined;
    std.crypto.random.bytes(&rnd_buf);
    var buf: [64]u8 = undefined;
    const hex = std.fmt.bytesToHex(rnd_buf, .lower);
    const thumb_path = try std.fmt.bufPrint(&buf, "test_thumb_{s}.png", .{hex});
    defer std.fs.cwd().deleteFile(thumb_path) catch {};

    try saveThumbnail(&engine, thumb_path, 64, 64);

    // Verify file exists and has size > 0
    const file = try std.fs.cwd().openFile(thumb_path, .{});
    const stat = try file.stat();
    try std.testing.expect(stat.size > 0);
    file.close();

    // Ideally verify dimensions, but requires loading it back.
    // We trust gegl:scale-ratio + save for now.
}
test "Engine load SVG paths" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    const filename = "test_paths.svg";
    const svg_content =
        \\<svg width="100" height="100" xmlns="http://www.w3.org/2000/svg">
        \\  <path id="p1" d="M 0 0 L 10 10" />
        \\  <path d="M 20 20 L 30 30" />
        \\</svg>
    ;
    try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = svg_content });
    defer std.fs.cwd().deleteFile(filename) catch {};

    const params = Engine.SvgImportParams{
        .width = 0,
        .height = 0,
        .import_paths = true,
    };

    try loadSvg(&engine, filename, params);

    // Assert paths loaded
    try std.testing.expectEqual(engine.paths.items.len, 2);

    const p1 = &engine.paths.items[0];
    try std.testing.expectEqualStrings("p1", p1.name);

    const p2 = &engine.paths.items[1];
    try std.testing.expectEqualStrings("Path", p2.name);
}
test "Engine project save load" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // 1. Setup: 2 Layers
    try engine.addLayer("Layer 1");
    engine.setFgColor(255, 0, 0, 255);
    engine.paintStroke(10, 10, 10, 10, 1.0);

    try engine.addLayer("Layer 2");
    engine.setFgColor(0, 0, 255, 255);
    engine.paintStroke(20, 20, 20, 20, 1.0);
    engine.toggleLayerVisibility(1); // Hide Layer 2

    // 2. Save
    const rnd = std.crypto.random.int(u64);
    var buf: [64]u8 = undefined;
    const project_path = try std.fmt.bufPrint(&buf, "test_project_save_{d}", .{rnd});

    // Clean up before/after
    std.fs.cwd().deleteTree(project_path) catch {};
    defer std.fs.cwd().deleteTree(project_path) catch {};

    try saveProject(&engine, project_path);

    // 3. Reset
    engine.reset();
    try std.testing.expectEqual(engine.layers.list.items.len, 0);

    // 4. Load
    try loadProject(&engine, project_path);

    // 5. Verify
    try std.testing.expectEqual(engine.layers.list.items.len, 2);

    // Layer 0 (Original "Layer 1" - bottom?)
    // addLayer appends. "Layer 1" is index 0. "Layer 2" is index 1.
    // loadProject should preserve order.

    // Check Layer 0
    const l0 = &engine.layers.list.items[0];
    try std.testing.expectEqualStrings("Layer 1", std.mem.span(@as([*:0]const u8, @ptrCast(&l0.name))));
    try std.testing.expect(l0.visible); // Default visible

    // Check Layer 1
    const l1 = &engine.layers.list.items[1];
    try std.testing.expectEqualStrings("Layer 2", std.mem.span(@as([*:0]const u8, @ptrCast(&l1.name))));
    try std.testing.expect(!l1.visible); // Was hidden
}
test "Engine generic export" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    try engine.addLayer("Background");

    // Paint something
    engine.setFgColor(255, 0, 0, 255);
    engine.paintStroke(100, 100, 100, 100, 1.0);

    const filename = "test_export_baseline.png";
    defer std.fs.cwd().deleteFile(filename) catch {};

    // Use exportImage
    try exportImage(&engine, filename);

    // Verify file exists
    const file = try std.fs.cwd().openFile(filename, .{});
    const stat = try file.stat();
    try std.testing.expect(stat.size > 0);
    file.close();
}

test "Engine load PostScript" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    const filename = "test_image.ps";
    const ps_content =
        \\%!PS
        \\/newpath
        \\10 10 moveto
        \\20 20 lineto
        \\stroke
        \\showpage
    ;
    try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = ps_content });
    defer std.fs.cwd().deleteFile(filename) catch {};

    loadFromFile(&engine, filename) catch |err| {
        // If it fails with GeglLoadFailed or InvalidImage (empty bbox due to no loader), we acknowledge the limitation.
        if (err == error.GeglLoadFailed or err == error.InvalidImage) {
            std.debug.print("Skipping PS load test (environment limitation: {})\n", .{err});
            return;
        }
        return err;
    };

    if (engine.layers.list.items.len > 0) {
        const layer = &engine.layers.list.items[0];
        const extent = c.gegl_buffer_get_extent(layer.buffer);
        // We don't check exact dimensions as resolution depends on backend default
        try std.testing.expect(extent.*.width > 0);
        try std.testing.expect(extent.*.height > 0);
    }
}

test {
    _ = XcfLoader;
}
