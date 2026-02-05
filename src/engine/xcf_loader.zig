const std = @import("std");
const c = @import("../c.zig").c;
const Engine = @import("core.zig").Engine;
const Consts = @import("xcf_consts.zig");

const PropType = Consts.PropType;
const XcfCompressionType = Consts.XcfCompressionType;

pub const XcfLoader = struct {
    file: std.fs.File,
    version: i32 = 0,
    bytes_per_offset: u8 = 4,
    compression: XcfCompressionType = .COMPRESS_NONE,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !XcfLoader {
        const file = try std.fs.cwd().openFile(path, .{});
        return XcfLoader{
            .file = file,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *XcfLoader) void {
        self.file.close();
    }

    fn readInt32(self: *XcfLoader) !i32 {
        var buf: [4]u8 = undefined;
        const n = try self.file.readAll(&buf);
        if (n < 4) return error.EndOfStream;
        return std.mem.readInt(i32, &buf, .big);
    }

    fn readUInt32(self: *XcfLoader) !u32 {
        var buf: [4]u8 = undefined;
        const n = try self.file.readAll(&buf);
        if (n < 4) return error.EndOfStream;
        return std.mem.readInt(u32, &buf, .big);
    }

    fn readUInt8(self: *XcfLoader) !u8 {
        var buf: [1]u8 = undefined;
        const n = try self.file.readAll(&buf);
        if (n < 1) return error.EndOfStream;
        return buf[0];
    }

    fn readFloat(self: *XcfLoader) !f32 {
        var buf: [4]u8 = undefined;
        const n = try self.file.readAll(&buf);
        if (n < 4) return error.EndOfStream;
        const val = std.mem.readInt(u32, &buf, .big);
        return @bitCast(val);
    }

    fn readString(self: *XcfLoader) ![]u8 {
        const len = try self.readUInt32();
        if (len == 0) return try self.allocator.alloc(u8, 0);

        if (len > 1024 * 1024) return error.StringTooLong; // Safety

        const buf = try self.allocator.alloc(u8, len);
        const read = try self.file.readAll(buf);
        if (read != len) {
            self.allocator.free(buf);
            return error.EndOfStream;
        }
        return buf;
    }

    fn readOffset(self: *XcfLoader) !u64 {
        if (self.bytes_per_offset == 8) {
            var buf: [8]u8 = undefined;
            const n = try self.file.readAll(&buf);
            if (n < 8) return error.EndOfStream;
            return std.mem.readInt(u64, &buf, .big);
        } else {
            var buf: [4]u8 = undefined;
            const n = try self.file.readAll(&buf);
            if (n < 4) return error.EndOfStream;
            return @as(u64, std.mem.readInt(u32, &buf, .big));
        }
    }

    fn seek(self: *XcfLoader, pos: u64) !void {
        try self.file.seekTo(pos);
    }

    fn tell(self: *XcfLoader) !u64 {
        return try self.file.getPos();
    }

    pub fn load(self: *XcfLoader, engine: *Engine) !void {
        // Magic
        var magic: [14]u8 = undefined;
        const read = try self.file.readAll(&magic);
        if (read < 14) return error.EndOfStream;
        if (!std.mem.startsWith(u8, &magic, "gimp xcf ")) return error.InvalidMagic;

        // Version
        // "gimp xcf file" -> v0
        // "gimp xcf v001" -> v1
        if (std.mem.eql(u8, magic[9..13], "file")) {
            self.version = 0;
        } else if (magic[9] == 'v') {
            const v_str = magic[10..13];
            self.version = std.fmt.parseInt(i32, v_str, 10) catch return error.InvalidVersion;
        } else {
            return error.InvalidMagic;
        }

        if (self.version >= 11) {
            self.bytes_per_offset = 8;
        }

        // Header
        const width = try self.readUInt32();
        const height = try self.readUInt32();
        _ = try self.readInt32(); // GimpImageBaseType

        if (width > 20000 or height > 20000) return error.ImageTooLarge;

        // Set Canvas Size
        engine.setCanvasSizeInternal(@intCast(width), @intCast(height));

        // Read Properties
        try self.readProps(null); // Image props

        // Read Layer Offsets
        while (true) {
            const offset = try self.readOffset();
            if (offset == 0) break;

            const saved_pos = try self.tell();
            try self.seek(offset);
            try self.loadLayer(engine);
            try self.seek(saved_pos);
        }

        // Channels (skip for now)
        while (true) {
            const offset = try self.readOffset();
            if (offset == 0) break;
        }
    }

    fn readProps(self: *XcfLoader, layer: ?*Engine.Layer) !void {
        while (true) {
            const prop_type_val = try self.readUInt32();
            const prop_size = try self.readUInt32();
            const prop_type: PropType = @enumFromInt(prop_type_val);

            if (prop_type == .PROP_END) break;

            const end_pos = (try self.tell()) + prop_size;

            switch (prop_type) {
                .PROP_OPACITY => {
                    if (layer) |_| {
                        const opacity = try self.readUInt32();
                        _ = opacity;
                    } else {
                        try self.seek(end_pos);
                    }
                },
                .PROP_VISIBLE => {
                    if (layer) |l| {
                        const visible = try self.readUInt32();
                        l.visible = (visible != 0);
                    } else {
                        try self.seek(end_pos);
                    }
                },
                .PROP_OFFSETS => {
                    if (layer) |_| {
                        const x = try self.readInt32();
                        const y = try self.readInt32();
                        _ = x;
                        _ = y;
                    } else {
                        try self.seek(end_pos);
                    }
                },
                .PROP_COMPRESSION => {
                    const comp = try self.readUInt8();
                    self.compression = @enumFromInt(comp);
                },
                .PROP_MODE => {
                     try self.seek(end_pos);
                },
                else => {
                    try self.seek(end_pos);
                },
            }
            try self.seek(end_pos);
        }
    }

    fn loadLayer(self: *XcfLoader, engine: *Engine) !void {
        const width = try self.readUInt32();
        const height = try self.readUInt32();
        const type_code = try self.readInt32();
        const name = try self.readString();
        defer self.allocator.free(name);

        var visible = true;
        var offset_x: i32 = 0;
        var offset_y: i32 = 0;
        var opacity: u32 = 255;

        while (true) {
            const prop_type_val = try self.readUInt32();
            const prop_size = try self.readUInt32();
            const prop_type: PropType = @enumFromInt(prop_type_val);

            if (prop_type == .PROP_END) break;
            const end_pos = (try self.tell()) + prop_size;

            switch (prop_type) {
                .PROP_VISIBLE => visible = (try self.readUInt32()) != 0,
                .PROP_OFFSETS => {
                    offset_x = try self.readInt32();
                    offset_y = try self.readInt32();
                },
                .PROP_OPACITY => opacity = try self.readUInt32(),
                else => {}, // Skip others
            }
            try self.seek(end_pos);
        }

        const hierarchy_offset = try self.readOffset();
        const layer_mask_offset = try self.readOffset();
        _ = layer_mask_offset;

        var format_str: [:0]const u8 = "R'G'B'A u8";

        switch (type_code) {
            0 => { format_str = "R'G'B' u8"; },
            1 => { format_str = "R'G'B'A u8"; },
            2 => { format_str = "Y' u8"; },
            3 => { format_str = "Y'A u8"; },
            4 => { format_str = "R'G'B' u8"; },
            5 => { format_str = "R'G'B'A u8"; },
            else => {},
        }

        const rect = c.GeglRectangle{
            .x = @intCast(offset_x),
            .y = @intCast(offset_y),
            .width = @intCast(width),
            .height = @intCast(height)
        };
        const format = c.babl_format(format_str);
        const buffer = c.gegl_buffer_new(&rect, format);
        if (buffer == null) return error.GeglBufferFailed;

        if (hierarchy_offset != 0) {
            const saved = try self.tell();
            try self.seek(hierarchy_offset);
            try self.loadHierarchy(buffer.?);
            try self.seek(saved);
        }

        try engine.addLayerInternal(buffer.?, name, visible, false, engine.layers.items.len);
    }

    fn loadHierarchy(self: *XcfLoader, buffer: *c.GeglBuffer) !void {
        const width = try self.readUInt32();
        const height = try self.readUInt32();
        const bpp = try self.readUInt32();

        const offset = try self.readOffset();
        if (offset != 0) {
            const saved = try self.tell();
            try self.seek(offset);
            try self.loadLevel(buffer, width, height, bpp);
            try self.seek(saved);
        }
    }

    fn loadLevel(self: *XcfLoader, buffer: *c.GeglBuffer, width: u32, height: u32, bpp: u32) !void {
        const l_width = try self.readUInt32();
        const l_height = try self.readUInt32();
        if (l_width != width or l_height != height) return error.DimensionMismatch;

        var tile_offsets = std.ArrayList(u64){};
        defer tile_offsets.deinit(self.allocator);

        while (true) {
            const off = try self.readOffset();
            if (off == 0) break;
            try tile_offsets.append(self.allocator, off);
        }

        const tile_w = Consts.XCF_TILE_WIDTH;
        const tile_h = Consts.XCF_TILE_HEIGHT;
        const cols = (width + tile_w - 1) / tile_w;
        const rows = (height + tile_h - 1) / tile_h;

        const num_tiles = cols * rows;
        _ = num_tiles;

        for (tile_offsets.items, 0..) |off, i| {
            if (off == 0) continue;

            const saved = try self.tell();
            try self.seek(off);

            const row = i / cols;
            const col = i % cols;

            const x = @as(u32, @intCast(col)) * tile_w;
            const y = @as(u32, @intCast(row)) * tile_h;
            var w: u32 = tile_w;
            var h: u32 = tile_h;
            if (x + w > width) w = width - x;
            if (y + h > height) h = height - y;

            const extent = c.gegl_buffer_get_extent(buffer);
            const abs_rect = c.GeglRectangle{
                .x = extent.*.x + @as(c_int, @intCast(x)),
                .y = extent.*.y + @as(c_int, @intCast(y)),
                .width = @intCast(w),
                .height = @intCast(h),
            };

            var size: usize = 0;
            if (i + 1 < tile_offsets.items.len) {
                size = tile_offsets.items[i+1] - off;
            } else {
                size = w * h * bpp * 2;
            }

            try self.loadTile(buffer, &abs_rect, bpp, size);
            try self.seek(saved);
        }
    }

    fn loadTile(self: *XcfLoader, buffer: *c.GeglBuffer, rect: *const c.GeglRectangle, bpp: u32, len: usize) !void {
        switch (self.compression) {
            .COMPRESS_NONE => {
                const size = @as(usize, @intCast(rect.width * rect.height)) * bpp;
                const data = try self.allocator.alloc(u8, size);
                defer self.allocator.free(data);
                _ = try self.file.readAll(data);
                c.gegl_buffer_set(buffer, rect, 0, null, data.ptr, c.GEGL_AUTO_ROWSTRIDE);
            },
            .COMPRESS_RLE => {
                try self.loadTileRle(buffer, rect, bpp, len);
            },
            else => {},
        }
    }

    fn loadTileRle(self: *XcfLoader, buffer: *c.GeglBuffer, rect: *const c.GeglRectangle, bpp: u32, len: usize) !void {
        const compressed = try self.allocator.alloc(u8, len);
        defer self.allocator.free(compressed);
        const bytes_read = try self.file.readAll(compressed);

        const pixels = @as(usize, @intCast(rect.width * rect.height));
        const final_size = pixels * bpp;
        const data = try self.allocator.alloc(u8, final_size);
        defer self.allocator.free(data);

        var cursor: usize = 0;

        var i: usize = 0;
        while (i < bpp) : (i += 1) {
            var pixel_idx: usize = 0;
            while (pixel_idx < pixels) {
                if (cursor >= bytes_read) break;

                const val = compressed[cursor];
                cursor += 1;

                var length: usize = 0;

                if (val >= 128) {
                    length = 255 - (@as(usize, val) - 1);
                    if (length == 128) {
                        if (cursor + 2 > bytes_read) break;
                        length = std.mem.readInt(u16, compressed[cursor..][0..2], .big);
                        cursor += 2;
                    }

                    var k: usize = 0;
                    while (k < length) : (k += 1) {
                        if (cursor >= bytes_read) break;
                        if (pixel_idx >= pixels) break;

                        data[pixel_idx * bpp + i] = compressed[cursor];
                        cursor += 1;
                        pixel_idx += 1;
                    }
                } else {
                    length = @as(usize, val) + 1;
                    if (length == 128) {
                        if (cursor + 2 > bytes_read) break;
                        length = std.mem.readInt(u16, compressed[cursor..][0..2], .big);
                        cursor += 2;
                    }

                    if (cursor >= bytes_read) break;
                    const repeat = compressed[cursor];
                    cursor += 1;

                    var k: usize = 0;
                    while (k < length) : (k += 1) {
                        if (pixel_idx >= pixels) break;
                        data[pixel_idx * bpp + i] = repeat;
                        pixel_idx += 1;
                    }
                }
            }
        }

        c.gegl_buffer_set(buffer, rect, 0, null, data.ptr, c.GEGL_AUTO_ROWSTRIDE);
    }
};

test "XcfLoader integration" {
    var engine = Engine{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    const path = "ref/gimp/app/tests/files/gimp-2-6-file.xcf";
    if (std.fs.cwd().access(path, .{}) catch null) |_| {
        var loader = try XcfLoader.init(std.testing.allocator, path);
        defer loader.deinit();

        try loader.load(&engine);

        try std.testing.expect(engine.layers.items.len > 0);
    } else {
        std.debug.print("Skipping XCF test: reference file not found\n", .{});
    }
}
