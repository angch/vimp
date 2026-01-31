const std = @import("std");
const c = @import("c.zig").c;

pub const ParsedPath = struct {
    id: ?[]u8,
    d: []u8,

    pub fn deinit(self: *ParsedPath, allocator: std.mem.Allocator) void {
        if (self.id) |id| allocator.free(id);
        allocator.free(self.d);
    }
};

const ParseContext = struct {
    allocator: std.mem.Allocator,
    paths: std.ArrayList(ParsedPath),
    err: ?anyerror,
};

fn start_element(
    _: ?*c.GMarkupParseContext,
    element_name: [*c]const u8,
    attribute_names: [*c][*c]const u8,
    attribute_values: [*c][*c]const u8,
    user_data: ?*anyopaque,
    _: [*c][*c]c.GError
) callconv(.c) void {
    const ctx: *ParseContext = @ptrCast(@alignCast(user_data));
    const name_span = std.mem.span(element_name);

    if (std.mem.eql(u8, name_span, "path")) {
        var id: ?[]u8 = null;
        var d: ?[]u8 = null;

        var i: usize = 0;
        while (true) {
            const attr_name_c = attribute_names[i];
            if (attr_name_c == 0) break;
            const attr_val_c = attribute_values[i];
            if (attr_val_c == 0) break;

            const attr_name = std.mem.span(attr_name_c);
            const attr_val = std.mem.span(attr_val_c);

            if (std.mem.eql(u8, attr_name, "id")) {
                id = ctx.allocator.dupe(u8, attr_val) catch {
                    ctx.err = error.OutOfMemory;
                    return;
                };
            } else if (std.mem.eql(u8, attr_name, "d")) {
                d = ctx.allocator.dupe(u8, attr_val) catch {
                     if (id) |i_d| ctx.allocator.free(i_d);
                     ctx.err = error.OutOfMemory;
                     return;
                };
            }
            i += 1;
        }

        if (d) |d_str| {
            const p = ParsedPath{ .id = id, .d = d_str };
            ctx.paths.append(ctx.allocator, p) catch {
                var mut_p = p;
                mut_p.deinit(ctx.allocator);
                ctx.err = error.OutOfMemory;
            };
        } else {
            if (id) |i_d| ctx.allocator.free(i_d);
        }
    }
}

pub fn parseSvgPaths(allocator: std.mem.Allocator, path: []const u8) !std.ArrayList(ParsedPath) {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const size = (try file.stat()).size;
    const content = try allocator.alloc(u8, size);
    defer allocator.free(content);

    _ = try file.readAll(content);

    var ctx = ParseContext{
        .allocator = allocator,
        .paths = std.ArrayList(ParsedPath){},
        .err = null,
    };
    errdefer {
        for (ctx.paths.items) |*p| p.deinit(allocator);
        ctx.paths.deinit(allocator);
    }

    var parser = std.mem.zeroes(c.GMarkupParser);
    parser.start_element = start_element;

    const parse_context = c.g_markup_parse_context_new(&parser, 0, &ctx, null);
    defer c.g_markup_parse_context_free(parse_context);

    var g_err: ?*c.GError = null;
    const result = c.g_markup_parse_context_parse(parse_context, content.ptr, @intCast(content.len), &g_err);

    if (result == 0) {
        if (g_err) |err| {
             c.g_error_free(err);
        }
        // If parsing failed but we got some paths, should we return them?
        // Usually markup error means invalid SVG.
        // We will return error.
        return error.ParseError;
    }

    if (ctx.err) |e| return e;

    return ctx.paths;
}
