const std = @import("std");

const c = @import("c.zig").c;
const Engine = @import("engine.zig").Engine;
const EngineIO = @import("engine.zig").io;
const CanvasUtils = @import("canvas_utils.zig");
const RecentManager = @import("recent.zig").RecentManager;
const RecentColorsManager = @import("recent_colors.zig").RecentColorsManager;
const ImportDialogs = @import("widgets/import_dialogs.zig");
const TextDialog = @import("widgets/text_dialog.zig");
const FileChooser = @import("widgets/file_chooser.zig");
const OpenLocationDialog = @import("widgets/open_location_dialog.zig");
const CanvasDialog = @import("widgets/canvas_dialog.zig");
const FilterDialog = @import("widgets/filter_dialog.zig");
const FullscreenPreview = @import("widgets/fullscreen_preview.zig");
const ThumbnailWindow = @import("widgets/thumbnail_window.zig");
const CommandPalette = @import("widgets/command_palette.zig");
const ColorPalette = @import("widgets/color_palette.zig").ColorPalette;
const RawLoader = @import("raw_loader.zig").RawLoader;
const ToolOptionsPanel = @import("widgets/tool_options_panel.zig").ToolOptionsPanel;
const Sidebar = @import("ui/sidebar.zig").Sidebar;
const SidebarCallbacks = @import("ui/sidebar.zig").SidebarCallbacks;
const Header = @import("ui/header.zig").Header;
const CanvasUI = @import("ui/canvas.zig");
const Tool = @import("tools.zig").Tool;
const ToolInterface = @import("tools/interface.zig").ToolInterface;
const ToolFactory = @import("tools/factory.zig").ToolFactory;
const ToolCreationContext = @import("tools/factory.zig").ToolCreationContext;
const Assets = @import("assets.zig");
const Salvage = @import("salvage.zig").Salvage;

var engine: Engine = .{};
var recent_manager: RecentManager = undefined;
var recent_colors_manager: RecentColorsManager = undefined;
var current_tool: Tool = .brush;

var autosave_timer_id: c_uint = 0;

var thumbnail_ctx: ThumbnailWindow.ThumbnailContext = undefined;

var recent_flow_box: ?*c.GtkWidget = null;

var main_stack: ?*c.GtkWidget = null;
var toast_overlay: ?*c.AdwToastOverlay = null;

var sidebar_ui: *Sidebar = undefined;
var header_ui: *Header = undefined;
var canvas_ui: ?*CanvasUI.Canvas = null;
var cli_page_number: i32 = -1;

fn handle_local_options(
    _: *c.GApplication,
    options: *c.GVariantDict,
    _: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) c_int {
    var page: c_int = -1;
    if (c.g_variant_dict_lookup(options, "page", "i", &page) != 0) {
        cli_page_number = page;
    }
    return -1; // Continue default processing
}

fn open_func(
    _: *c.GApplication,
    files: [*c]?*c.GFile,
    n_files: c_int,
    _: [*c]const u8,
    _: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    var i: usize = 0;
    while (i < n_files) : (i += 1) {
        const file = files[i];
        if (file) |f| {
            const path = c.g_file_get_path(f);
            if (path) |p| {
                const span = std.mem.span(@as([*:0]const u8, @ptrCast(p)));
                openFileFromPath(span, false, true, null);
                c.g_free(p);
            }
        }
    }
}

pub fn main() !void {
    engine.init();
    defer engine.deinit();

    // Construct the graph as per US-002
    engine.setupGraph();

    // Create the application
    // Use NON_UNIQUE to avoid dbus complications in dev, and HANDLES_OPEN to support opening files
    const flags = c.G_APPLICATION_NON_UNIQUE | c.G_APPLICATION_HANDLES_OPEN;
    // Migrate to AdwApplication
    const app = c.adw_application_new("org.vimp.app.dev", flags);
    defer c.g_object_unref(app);

    // Add Options
    const entries = [_]c.GOptionEntry{
        .{
            .long_name = "page",
            .short_name = 'p',
            .flags = 0,
            .arg = c.G_OPTION_ARG_INT,
            .arg_data = null,
            .description = "Page number to open (PDF)",
            .arg_description = "PAGE",
        },
        .{
            .long_name = null,
            .short_name = 0,
            .flags = 0,
            .arg = c.G_OPTION_ARG_NONE,
            .arg_data = null,
            .description = null,
            .arg_description = null,
        },
    };
    c.g_application_add_main_option_entries(@ptrCast(app), &entries);

    // Connect signals
    _ = c.g_signal_connect_data(app, "activate", @ptrCast(&activate), null, null, 0);
    _ = c.g_signal_connect_data(app, "handle-local-options", @ptrCast(&handle_local_options), null, null, 0);
    _ = c.g_signal_connect_data(app, "open", @ptrCast(&open_func), null, null, 0);

    // Run the application
    const status = c.g_application_run(@ptrCast(app), @intCast(std.os.argv.len), @ptrCast(std.os.argv.ptr));
    _ = status;
}

fn show_toast(comptime fmt: []const u8, args: anytype) void {
    if (toast_overlay) |overlay| {
        const msg_z = std.fmt.allocPrintSentinel(std.heap.c_allocator, fmt, args, 0) catch return;
        defer std.heap.c_allocator.free(msg_z);

        const toast = c.adw_toast_new(msg_z.ptr);
        c.adw_toast_overlay_add_toast(overlay, toast);
    }
}

fn show_toast_with_action(action: [:0]const u8, target: [:0]const u8, button_label: [:0]const u8, comptime fmt: []const u8, args: anytype) void {
    if (toast_overlay) |overlay| {
        const msg_z = std.fmt.allocPrintSentinel(std.heap.c_allocator, fmt, args, 0) catch return;
        defer std.heap.c_allocator.free(msg_z);

        const toast = c.adw_toast_new(msg_z.ptr);
        c.adw_toast_set_action_name(toast, action.ptr);
        const variant = c.g_variant_new_string(target.ptr);
        c.adw_toast_set_action_target_value(toast, variant);
        c.adw_toast_set_button_label(toast, button_label.ptr);
        c.adw_toast_overlay_add_toast(overlay, toast);
    }
}

fn update_view_mode() void {
    if (main_stack) |stack| {
        if (engine.layers.list.items.len > 0) {
            c.gtk_stack_set_visible_child_name(@ptrCast(stack), "canvas");
        } else {
            c.gtk_stack_set_visible_child_name(@ptrCast(stack), "welcome");
        }
    }
}

fn refresh_undo_ui_wrapper() void {
    sidebar_ui.refreshUndo();
}

fn reset_transform_ui_wrapper() void {
    if (sidebar_ui.tool_options_panel) |p| p.resetTransformUI();
}


fn new_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.addLayer("Background") catch |err| {
        show_toast("Failed to add layer: {}", .{err});
        return;
    };
    sidebar_ui.refreshLayers();
    sidebar_ui.refreshUndo();
    update_view_mode();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

const OpenContext = struct {
    window: ?*c.GtkWindow,
    as_layers: bool,
};

const ImportContext = struct {
    as_layers: bool,
};

fn generate_thumbnail(path: [:0]const u8) void {
    recent_manager.ensureThumbnailDir() catch |e| {
        std.debug.print("Failed to ensure thumbnail dir: {}\n", .{e});
        return;
    };

    const thumb_path = recent_manager.getThumbnailPath(path) catch |e| {
        std.debug.print("Failed to get thumbnail path: {}\n", .{e});
        return;
    };
    defer std.heap.c_allocator.free(thumb_path);

    EngineIO.saveThumbnail(&engine, thumb_path, 128, 128) catch |e| {
        std.debug.print("Failed to save thumbnail: {}\n", .{e});
    };
}

fn download_callback(source: ?*c.GObject, result: ?*c.GAsyncResult, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    // user_data is path (allocated)
    const path_ptr: [*c]u8 = @ptrCast(@alignCast(user_data));
    const path = std.mem.span(path_ptr);
    defer std.heap.c_allocator.free(path);

    // Check process status?
    // Actually we just check if file exists and has size
    if (std.fs.openFileAbsolute(path, .{})) |file| {
        const stat = file.stat() catch {
            show_toast("Download failed (stat error)", .{});
            file.close();
            return;
        };
        file.close();

        if (stat.size > 0) {
            // Open it (don't add to recent as it's a temp file)
            // But usually we want to "import" it.
            // If we treat it as "Open Location", maybe we DO want it in recent if we supported URI in recent.
            // But RecentManager expects paths.
            // For now: add_to_recent = false.
            // Also as_layers = false for standard open.
            // Convert path to sentinel-terminated for openFileFromPath
            const path_z = std.fmt.allocPrintSentinel(std.heap.c_allocator, "{s}", .{path}, 0) catch return;
            defer std.heap.c_allocator.free(path_z);
            openFileFromPath(path_z, false, false, null);
        } else {
            show_toast("Download failed (empty file)", .{});
        }
    } else |_| {
        var err: ?*c.GError = null;
        if (c.g_subprocess_wait_check_finish(@ptrCast(source), result, &err) == 0) {
            if (err) |e| {
                show_toast("Download failed: {s}", .{e.*.message});
                c.g_error_free(e);
            } else {
                show_toast("Download failed", .{});
            }
        } else {
            show_toast("Download failed (file missing)", .{});
        }
    }
}

fn downloadAndOpen(uri: [:0]const u8, _: ?*anyopaque) void {
    // 1. Get Cache Dir
    const cache_dir = c.g_get_user_cache_dir();
    if (cache_dir == null) {
        show_toast("Cannot get cache directory", .{});
        return;
    }
    const cache_span = std.mem.span(cache_dir);
    const vimp_cache = std.fs.path.join(std.heap.c_allocator, &[_][]const u8{ cache_span, "vimp", "downloads" }) catch return;
    defer std.heap.c_allocator.free(vimp_cache);

    std.fs.cwd().makePath(vimp_cache) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => {
            show_toast("Failed to create cache dir", .{});
            return;
        },
    };

    // 2. Generate Filename (MD5 of URI + Extension)
    var hash: [16]u8 = undefined;
    std.crypto.hash.Md5.hash(uri, &hash, .{});
    const hash_hex = std.fmt.bytesToHex(hash, .lower);

    // Guess extension
    var ext: []const u8 = ".dat";
    if (std.mem.lastIndexOf(u8, uri, ".")) |idx| {
        if (idx < uri.len - 1) {
            const possible_ext = uri[idx..];
            if (possible_ext.len <= 5) {
                ext = possible_ext;
            }
        }
    }

    const filename = std.fmt.allocPrint(std.heap.c_allocator, "{s}{s}", .{ hash_hex, ext }) catch return;
    defer std.heap.c_allocator.free(filename);

    const dest_path = std.fs.path.joinZ(std.heap.c_allocator, &[_][]const u8{ vimp_cache, filename }) catch return;
    // Pass ownership of dest_path to callback

    // 3. Start Subprocess (curl)
    const proc = c.g_subprocess_new(c.G_SUBPROCESS_FLAGS_NONE, null, "curl", "-L", "-f", "-o", dest_path.ptr, uri.ptr, @as(?*anyopaque, null));

    if (proc == null) {
        show_toast("Failed to start curl", .{});
        std.heap.c_allocator.free(dest_path);
        return;
    }

    show_toast("Downloading...", .{});
    c.g_subprocess_wait_check_async(proc, null, @ptrCast(&download_callback), @ptrCast(dest_path));
    c.g_object_unref(proc);
}

const RawContext = struct {
    original_path: [:0]const u8,
    temp_path: [:0]const u8,
    as_layers: bool,
    add_to_recent: bool,
};

fn raw_conversion_callback(source: ?*c.GObject, result: ?*c.GAsyncResult, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *RawContext = @ptrCast(@alignCast(user_data));
    defer {
        std.heap.c_allocator.free(ctx.original_path);
        std.heap.c_allocator.free(ctx.temp_path);
        std.heap.c_allocator.destroy(ctx);
    }

    var err: ?*c.GError = null;
    if (c.g_subprocess_wait_check_finish(@ptrCast(source), result, &err) != 0) {
        // Success
        // Open the temp file
        openFileFromPath(ctx.temp_path, ctx.as_layers, false, null);

        // Clean up temp file
        std.fs.deleteFileAbsolute(ctx.temp_path) catch |e| {
            std.debug.print("Failed to delete temp file: {}\n", .{e});
        };

        // Add ORIGINAL path to recent, if needed
        if (ctx.add_to_recent) {
            recent_manager.add(ctx.original_path) catch {};
            // Generate thumbnail for original path using current engine state
            generate_thumbnail(ctx.original_path);
            refresh_recent_ui();
        }
    } else {
        if (err) |e| {
            show_toast("Raw conversion failed: {s}", .{e.*.message});
            c.g_error_free(e);
        } else {
            show_toast("Raw conversion failed", .{});
        }
    }
}

fn convertRawAndOpen(path: [:0]const u8, as_layers: bool, add_to_recent: bool) void {
    const tool = RawLoader.findRawTool();
    if (tool == .none) {
        show_toast("No RAW developer found (install Darktable or RawTherapee)", .{});
        return;
    }

    const allocator = std.heap.c_allocator;

    // Generate temp output path
    const stem = std.fs.path.stem(path);
    const rnd = std.time.nanoTimestamp();
    const out_name = std.fmt.allocPrint(allocator, "{s}_{d}.png", .{ stem, rnd }) catch return;
    defer allocator.free(out_name);

    const tmp_dir_c = c.g_get_tmp_dir();
    const tmp_dir = std.mem.span(tmp_dir_c);

    const out_path = std.fs.path.joinZ(allocator, &[_][]const u8{ tmp_dir, out_name }) catch return;

    const path_dup = allocator.dupeZ(u8, path) catch {
        allocator.free(out_path);
        return;
    };

    const ctx = allocator.create(RawContext) catch {
        allocator.free(out_path);
        allocator.free(path_dup);
        return;
    };
    ctx.* = .{
        .original_path = path_dup,
        .temp_path = out_path,
        .as_layers = as_layers,
        .add_to_recent = add_to_recent,
    };

    var proc: ?*c.GSubprocess = null;

    if (tool == .darktable) {
        proc = c.g_subprocess_new(c.G_SUBPROCESS_FLAGS_NONE, null, "darktable-cli", path.ptr, out_path.ptr, @as(?*anyopaque, null));
    } else if (tool == .rawtherapee) {
        proc = c.g_subprocess_new(c.G_SUBPROCESS_FLAGS_NONE, null, "rawtherapee-cli", "-o", out_path.ptr, "-c", path.ptr, @as(?*anyopaque, null));
    }

    if (proc) |p| {
        show_toast("Developing RAW image...", .{});
        c.g_subprocess_wait_check_async(p, null, @ptrCast(&raw_conversion_callback), ctx);
        c.g_object_unref(p);
    } else {
        show_toast("Failed to start RAW conversion process", .{});
        allocator.free(out_path);
        allocator.free(path_dup);
        allocator.destroy(ctx);
    }
}

fn finish_file_open(path: [:0]const u8, as_layers: bool, success: bool, add_to_recent: bool) void {
    if (success and add_to_recent) {
        recent_manager.add(path) catch |e| {
            std.debug.print("Failed to add to recent: {}\n", .{e});
        };
        generate_thumbnail(path);
        refresh_recent_ui();
    }

    if (success and !as_layers) {
        // If replacing content, set canvas size to first layer
        if (engine.layers.list.items.len > 0) {
            const layer = &engine.layers.list.items[0];
            const extent = c.gegl_buffer_get_extent(layer.buffer);
            engine.setCanvasSize(extent.*.width, extent.*.height);
        }
    }

    // Refresh UI
    sidebar_ui.refreshLayers();
    sidebar_ui.refreshUndo();
    update_view_mode();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

fn on_pdf_import(user_data: ?*anyopaque, path: [:0]const u8, params: ?Engine.PdfImportParams) void {
    const ctx: *ImportContext = @ptrCast(@alignCast(user_data));
    defer std.heap.c_allocator.destroy(ctx);

    if (params) |p| {
        const perform_reset = !ctx.as_layers;

        if (p.split_pages) {
            // "Separate Images": Open first page here, spawn processes for others
            const self_exe = std.fs.selfExePathAlloc(std.heap.c_allocator) catch |err| {
                show_toast("Failed to get executable path: {}", .{err});
                return;
            };
            defer std.heap.c_allocator.free(self_exe);

            for (p.pages, 0..) |page_num, i| {
                if (i == 0) {
                    // Open first page in CURRENT window
                    var single_page = [_]i32{page_num};
                    const single_params = Engine.PdfImportParams{
                        .ppi = p.ppi,
                        .pages = &single_page,
                        .split_pages = false,
                    };

                    if (perform_reset) {
                        engine.reset();
                    }

                    var success = true;
                    EngineIO.loadPdf(&engine, path, single_params) catch |e| {
                        show_toast("Failed to load PDF page {d}: {}", .{ page_num, e });
                        success = false;
                    };
                    finish_file_open(path, !perform_reset, success, true);
                } else {
                    // Open subsequent pages in NEW process
                    var page_buf: [16]u8 = undefined;
                    const page_str = std.fmt.bufPrint(&page_buf, "{d}", .{page_num}) catch "1";

                    const argv = [_][]const u8{
                        self_exe,
                        path,
                        "--page",
                        page_str,
                    };

                    var child = std.process.Child.init(&argv, std.heap.c_allocator);
                    child.spawn() catch |err| {
                        show_toast("Failed to spawn process for page {d}: {}", .{ page_num, err });
                    };
                }
            }
            return;
        }

        if (perform_reset) {
            engine.reset();
        }

        var success = true;
        EngineIO.loadPdf(&engine, path, p) catch |e| {
            show_toast("Failed to load PDF: {}", .{e});
            success = false;
        };
        finish_file_open(path, !perform_reset, success, true);
    }
    // Else cancelled, do nothing (context is freed by defer)
}

fn on_svg_import(user_data: ?*anyopaque, path: [:0]const u8, params: ?Engine.SvgImportParams) void {
    const ctx: *ImportContext = @ptrCast(@alignCast(user_data));
    defer std.heap.c_allocator.destroy(ctx);

    if (params) |p| {
        if (!ctx.as_layers) {
            engine.reset();
        }

        var success = true;
        EngineIO.loadSvg(&engine, path, p) catch |e| {
            show_toast("Failed to load SVG: {}", .{e});
            success = false;
        };
        finish_file_open(path, ctx.as_layers, success, true);
    }
}

fn openFileFromPath(path: [:0]const u8, as_layers: bool, add_to_recent: bool, forced_loader: ?[:0]const u8) void {
    const ext = std.fs.path.extension(path);
    var is_pdf = std.ascii.eqlIgnoreCase(ext, ".pdf");
    var is_svg = std.ascii.eqlIgnoreCase(ext, ".svg");
    var is_ora = std.ascii.eqlIgnoreCase(ext, ".ora");
    var is_xcf = std.ascii.eqlIgnoreCase(ext, ".xcf");
    var is_ps = std.ascii.eqlIgnoreCase(ext, ".ps") or std.ascii.eqlIgnoreCase(ext, ".eps");
    var is_raw = RawLoader.isRawFile(path);

    // Override by loader
    if (forced_loader) |l| {
        is_pdf = std.mem.eql(u8, l, "pdf");
        is_svg = std.mem.eql(u8, l, "svg");
        is_ora = std.mem.eql(u8, l, "ora");
        is_xcf = std.mem.eql(u8, l, "xcf");
        is_ps = std.mem.eql(u8, l, "ps");
        is_raw = std.mem.eql(u8, l, "raw");
        // "gegl" falls through to default loadFromFile
        if (std.mem.eql(u8, l, "gegl")) {
             is_pdf = false; is_svg = false; is_ora = false; is_xcf = false; is_ps = false; is_raw = false;
        }
    }

    if (is_xcf) {
        if (!as_layers) {
            engine.reset();
        }
        var success = true;
        EngineIO.loadXcf(&engine, path) catch |e| {
            show_toast("Failed to load XCF: {}", .{e});
            success = false;
        };
        finish_file_open(path, as_layers, success, add_to_recent);
        return;
    }

    if (is_ora) {
        var success = true;
        EngineIO.loadOra(&engine, path, !as_layers) catch |e| {
            show_toast("Failed to load ORA: {}", .{e});
            success = false;
        };
        finish_file_open(path, as_layers, success, add_to_recent);
        return;
    }

    if (is_ps) {
        if (!as_layers) {
            engine.reset();
        }
        var success = true;
        EngineIO.loadFromFile(&engine, path) catch |e| {
            show_toast("Failed to load PostScript: {}", .{e});
            success = false;
        };
        finish_file_open(path, as_layers, success, add_to_recent);
        return;
    }

    if (is_raw) {
        convertRawAndOpen(path, as_layers, add_to_recent);
        return;
    }

    if (is_pdf) {
        if (cli_page_number != -1) {
            var pages = [_]i32{cli_page_number};
            const params = Engine.PdfImportParams{
                .ppi = 300.0,
                .pages = &pages,
                .split_pages = false,
            };

            if (!as_layers) {
                engine.reset();
            }

            var success = true;
            EngineIO.loadPdf(&engine, path, params) catch |e| {
                show_toast("Failed to load PDF page {d}: {}", .{ cli_page_number, e });
                success = false;
            };
            finish_file_open(path, as_layers, success, add_to_recent);
            return;
        }

        const ctx = std.heap.c_allocator.create(ImportContext) catch return;
        ctx.* = .{ .as_layers = as_layers };

        var parent_window: ?*c.GtkWindow = null;
        if (main_stack) |s| {
            const root = c.gtk_widget_get_root(@ptrCast(s));
            if (root) |r| parent_window = @ptrCast(@alignCast(r));
        }

        ImportDialogs.showPdfImportDialog(parent_window, &engine, path, &on_pdf_import, ctx) catch |e| {
            show_toast("Failed to show import dialog: {}", .{e});
            std.heap.c_allocator.destroy(ctx);
        };
        return;
    }

    if (is_svg) {
        const ctx = std.heap.c_allocator.create(ImportContext) catch return;
        ctx.* = .{ .as_layers = as_layers };

        var parent_window: ?*c.GtkWindow = null;
        if (main_stack) |s| {
            const root = c.gtk_widget_get_root(@ptrCast(s));
            if (root) |r| parent_window = @ptrCast(@alignCast(r));
        }

        ImportDialogs.showSvgImportDialog(parent_window, path, &on_svg_import, ctx) catch |e| {
            show_toast("Failed to show import dialog: {}", .{e});
            std.heap.c_allocator.destroy(ctx);
        };
        return;
    }

    if (!as_layers) {
        engine.reset();
    }

    var load_success = true;
    // Call engine load
    EngineIO.loadFromFile(&engine, path) catch |e| {
        // Offer salvage
        show_toast_with_action("app.salvage", path, "Try to Salvage", "Failed to load file: {}", .{e});
        load_success = false;
    };
    finish_file_open(path, as_layers, load_success, add_to_recent);
}

fn on_file_chosen(user_data: ?*anyopaque, path: ?[:0]const u8, loader: ?[:0]const u8) void {
    const ctx: *OpenContext = @ptrCast(@alignCast(user_data));
    defer std.heap.c_allocator.destroy(ctx);

    if (path) |p| {
        openFileFromPath(p, ctx.as_layers, true, loader);
    }
}

fn open_common(window: ?*c.GtkWindow, as_layers: bool) void {
    const ctx = std.heap.c_allocator.create(OpenContext) catch return;
    ctx.* = .{ .window = window, .as_layers = as_layers };

    const title: [:0]const u8 = if (as_layers) "Open as Layers" else "Open Image";

    FileChooser.showOpenDialog(
        window,
        title,
        as_layers,
        &on_file_chosen,
        ctx,
    ) catch |e| {
        show_toast("Failed to open dialog: {}", .{e});
        std.heap.c_allocator.destroy(ctx);
    };
}

fn open_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    open_common(window, false);
}

fn open_as_layers_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    open_common(window, true);
}

fn open_location_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    OpenLocationDialog.showOpenLocationDialog(window, @ptrCast(&downloadAndOpen), null);
}

fn save_surface_to_file(s: *c.cairo_surface_t, filename: [*c]const u8) void {
    const result = c.cairo_surface_write_to_png(s, filename);
    if (result == c.CAIRO_STATUS_SUCCESS) {
        show_toast("File saved to: {s}", .{filename});
    } else {
        show_toast("Error saving file: {d}", .{result});
    }
}

fn save_file(filename_c: [*c]const u8) void {
    const filename = std.mem.span(filename_c);
    const ext = std.fs.path.extension(filename);
    if (std.ascii.eqlIgnoreCase(ext, ".ora")) {
        EngineIO.saveOra(&engine, filename) catch |err| {
            show_toast("Error saving ORA: {}", .{err});
        };
        show_toast("File saved to: {s}", .{filename});
        return;
    }

    // Try generic export for other formats (JPG, PNG, WEBP, etc.)
    EngineIO.exportImage(&engine, filename) catch |err| {
        show_toast("Error saving file: {}", .{err});
        return;
    };
    show_toast("File saved to: {s}", .{filename});
}

fn save_finish(source_object: ?*c.GObject, res: ?*c.GAsyncResult, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    _ = user_data;
    var err: ?*c.GError = null;
    const file = c.gtk_file_dialog_save_finish(@ptrCast(source_object), res, &err);
    if (file) |f| {
        const path = c.g_file_get_path(f);
        if (path) |p| {
            save_file(p);
            c.g_free(p);
        }
        c.g_object_unref(f);
    } else {
        if (err) |e| {
            show_toast("Error saving: {s}", .{e.*.message});
            c.g_error_free(e);
        }
    }
}

fn save_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: *c.GtkWindow = @ptrCast(@alignCast(user_data));
    const dialog = c.gtk_file_dialog_new();
    c.gtk_file_dialog_set_title(dialog, "Save Canvas");
    c.gtk_file_dialog_set_initial_name(dialog, "untitled.png");

    const filters = c.g_list_store_new(c.gtk_file_filter_get_type());

    // PNG
    const filter_png = c.gtk_file_filter_new();
    c.gtk_file_filter_set_name(filter_png, "PNG Image");
    c.gtk_file_filter_add_pattern(filter_png, "*.png");
    c.g_list_store_append(filters, filter_png);
    c.g_object_unref(filter_png);

    // JPEG
    const filter_jpg = c.gtk_file_filter_new();
    c.gtk_file_filter_set_name(filter_jpg, "JPEG Image");
    c.gtk_file_filter_add_pattern(filter_jpg, "*.jpg");
    c.gtk_file_filter_add_pattern(filter_jpg, "*.jpeg");
    c.g_list_store_append(filters, filter_jpg);
    c.g_object_unref(filter_jpg);

    // WEBP
    const filter_webp = c.gtk_file_filter_new();
    c.gtk_file_filter_set_name(filter_webp, "WebP Image");
    c.gtk_file_filter_add_pattern(filter_webp, "*.webp");
    c.g_list_store_append(filters, filter_webp);
    c.g_object_unref(filter_webp);

    // TIFF
    const filter_tiff = c.gtk_file_filter_new();
    c.gtk_file_filter_set_name(filter_tiff, "TIFF Image");
    c.gtk_file_filter_add_pattern(filter_tiff, "*.tif");
    c.gtk_file_filter_add_pattern(filter_tiff, "*.tiff");
    c.g_list_store_append(filters, filter_tiff);
    c.g_object_unref(filter_tiff);

    // BMP
    const filter_bmp = c.gtk_file_filter_new();
    c.gtk_file_filter_set_name(filter_bmp, "BMP Image");
    c.gtk_file_filter_add_pattern(filter_bmp, "*.bmp");
    c.g_list_store_append(filters, filter_bmp);
    c.g_object_unref(filter_bmp);

    // ORA
    const filter_ora = c.gtk_file_filter_new();
    c.gtk_file_filter_set_name(filter_ora, "OpenRaster Image");
    c.gtk_file_filter_add_pattern(filter_ora, "*.ora");
    c.g_list_store_append(filters, filter_ora);
    c.g_object_unref(filter_ora);

    c.gtk_file_dialog_set_filters(dialog, @ptrCast(filters));
    c.g_object_unref(filters);

    c.gtk_file_dialog_save(dialog, window, null, @ptrCast(&save_finish), null);
    c.g_object_unref(dialog);
}

test "save surface" {
    const s = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, 10, 10) orelse return error.CairoFailed;
    defer c.cairo_surface_destroy(s);
    save_surface_to_file(s, "test_save.png");
    // Verify file exists
    const file = std.fs.cwd().openFile("test_save.png", .{}) catch |err| {
        std.debug.print("Failed to open test file: {}\n", .{err});
        return err;
    };
    file.close();
    std.fs.cwd().deleteFile("test_save.png") catch {};
}

test "openFileFromPath integration" {
    // Setup Engine manually since main() is not called
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // Create a dummy PNG file
    const s = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, 100, 100) orelse return error.CairoFailed;
    defer c.cairo_surface_destroy(s);
    // Fill with something to ensure it's not empty/transparent if that matters
    const cr = c.cairo_create(s);
    c.cairo_set_source_rgb(cr, 1.0, 0.0, 0.0);
    c.cairo_paint(cr);
    c.cairo_destroy(cr);

    const test_file = "test_drop.png";
    save_surface_to_file(s, test_file);
    defer std.fs.cwd().deleteFile(test_file) catch {};

    // 1. Open New
    openFileFromPath(test_file, false);
    try std.testing.expectEqual(@as(usize, 1), engine.layers.list.items.len);
    try std.testing.expectEqualStrings("test_drop.png", std.mem.span(@as([*:0]const u8, @ptrCast(&engine.layers.list.items[0].name))));

    // 2. Add as Layer
    openFileFromPath(test_file, true);
    try std.testing.expectEqual(@as(usize, 2), engine.layers.list.items.len);
    // The second layer name might be "test_drop.png" or similar
    // Note: layers are appended. Items[0] is bottom (first loaded), items[1] is top (second loaded).
    try std.testing.expectEqualStrings("test_drop.png", std.mem.span(@as([*:0]const u8, @ptrCast(&engine.layers.list.items[1].name))));
}

fn about_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    std.debug.print("Vimp Application\nVersion 0.1\n", .{});
}

fn inspector_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    c.gtk_window_set_interactive_debugging(1);
}

fn quit_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const app: *c.GtkApplication = @ptrCast(@alignCast(user_data));
    const windows = c.gtk_application_get_windows(app);
    if (windows) |list| {
        const window = list.*.data;
        c.gtk_window_close(@ptrCast(@alignCast(window)));
    }
    // Alternatively: c.g_application_quit(@ptrCast(app));
    // But closing the window is more "Adwaita" friendly if it manages the lifecycle.
    c.g_application_quit(@ptrCast(app));
}

fn salvage_activated(_: *c.GSimpleAction, parameter: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    if (parameter) |p| {
        var len: usize = 0;
        const path_ptr = c.g_variant_get_string(p, &len);
        // path_ptr is not necessarily 0-terminated by GVariant logic?
        // Docs: "Returns a pointer to the constant string data... the string will always be nul-terminated."
        const path = path_ptr[0..len :0];

        Salvage.recoverFile(&engine, path) catch |err| {
            show_toast("Salvage failed: {}", .{err});
            return;
        };

        sidebar_ui.refreshLayers();
        sidebar_ui.refreshUndo();
        update_view_mode();
        if (canvas_ui) |ui| ui.canvas_dirty = true;
        queue_draw();

        show_toast("File salvaged successfully.", .{});
    }
}

fn undo_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.undo();
    sidebar_ui.refreshLayers(); // Layers might change
    update_view_mode();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
    sidebar_ui.refreshUndo();
}

fn redo_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.redo();
    sidebar_ui.refreshLayers(); // Layers might change
    update_view_mode();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
    sidebar_ui.refreshUndo();
}

fn refresh_header_ui() void {
    c.gtk_widget_set_visible(header_ui.apply_btn, if (engine.preview_mode != .none) 1 else 0);
    c.gtk_widget_set_visible(header_ui.discard_btn, if (engine.preview_mode != .none) 1 else 0);
}

fn blur_small_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.setPreviewBlur(5.0);
    refresh_header_ui();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

fn blur_medium_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.setPreviewBlur(10.0);
    refresh_header_ui();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

fn blur_large_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.setPreviewBlur(20.0);
    refresh_header_ui();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

fn refresh_ui_callback() void {
    refresh_header_ui();
    sidebar_ui.refreshUndo();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

fn on_recent_child_activated(_: *c.GtkFlowBox, child: *c.GtkFlowBoxChild, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const widget = c.gtk_flow_box_child_get_child(child);
    const data = c.g_object_get_data(@ptrCast(widget), "file-path");
    if (data) |p| {
        const path: [*c]const u8 = @ptrCast(p);
        const span = std.mem.span(path);
        // Ensure we don't block if open takes time, but openFileFromPath is synchronous currently except for dialogs
        openFileFromPath(span, false, true, null);
    }
}

fn refresh_recent_ui() void {
    if (recent_flow_box) |box| {
        // Clear
        var child = c.gtk_widget_get_first_child(@ptrCast(box));
        while (child != null) {
            const next = c.gtk_widget_get_next_sibling(child);
            c.gtk_flow_box_remove(@ptrCast(box), child);
            child = next;
        }

        // Add recent files
        if (recent_manager.paths.items.len == 0) {
            const label = c.gtk_label_new("(No recent files)");
            c.gtk_widget_add_css_class(label, "dim-label");
            c.gtk_widget_set_margin_top(label, 20);
            c.gtk_widget_set_margin_bottom(label, 20);
            c.gtk_flow_box_append(@ptrCast(box), label);
        } else {
            for (recent_manager.paths.items) |path| {
                const row_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 6);
                c.gtk_widget_set_halign(row_box, c.GTK_ALIGN_CENTER);
                c.gtk_widget_set_margin_top(row_box, 12);
                c.gtk_widget_set_margin_bottom(row_box, 12);
                c.gtk_widget_set_margin_start(row_box, 12);
                c.gtk_widget_set_margin_end(row_box, 12);

                var icon_widget: *c.GtkWidget = undefined;
                var has_thumb = false;

                if (recent_manager.getThumbnailPath(path)) |tp| {
                    if (std.fs.openFileAbsolute(tp, .{})) |f| {
                        f.close();
                        const tp_z = std.fmt.allocPrintSentinel(std.heap.c_allocator, "{s}", .{tp}, 0) catch null;
                        if (tp_z) |z| {
                            icon_widget = c.gtk_image_new_from_file(z);
                            c.gtk_image_set_pixel_size(@ptrCast(icon_widget), 128);
                            std.heap.c_allocator.free(z);
                            has_thumb = true;
                        }
                    } else |_| {}
                    std.heap.c_allocator.free(tp);
                } else |_| {}

                if (!has_thumb) {
                    icon_widget = c.gtk_image_new_from_icon_name("image-x-generic-symbolic");
                    c.gtk_image_set_pixel_size(@ptrCast(icon_widget), 128);
                }
                c.gtk_box_append(@ptrCast(row_box), icon_widget);

                const basename = std.fs.path.basename(path);
                var buf: [256]u8 = undefined;
                const label_text = std.fmt.bufPrintZ(&buf, "{s}", .{basename}) catch "File";

                const label = c.gtk_label_new(label_text.ptr);
                c.gtk_label_set_wrap(@ptrCast(label), 1);
                c.gtk_label_set_max_width_chars(@ptrCast(label), 12);
                c.gtk_label_set_ellipsize(@ptrCast(label), c.PANGO_ELLIPSIZE_END);
                c.gtk_label_set_lines(@ptrCast(label), 2);
                c.gtk_label_set_justify(@ptrCast(label), c.GTK_JUSTIFY_CENTER);

                c.gtk_box_append(@ptrCast(row_box), label);

                // Show full path as tooltip
                var path_buf: [1024]u8 = undefined;
                const path_z = std.fmt.bufPrintZ(&path_buf, "{s}", .{path}) catch "File";
                c.gtk_widget_set_tooltip_text(row_box, path_z.ptr);

                c.gtk_flow_box_append(@ptrCast(box), row_box);

                // Attach data
                const path_dup = std.fmt.allocPrintSentinel(std.heap.c_allocator, "{s}", .{path}, 0) catch continue;
                c.g_object_set_data_full(@ptrCast(row_box), "file-path", @ptrCast(path_dup), @ptrCast(&c.g_free));
            }
        }
    }
}

fn autosave_callback(user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) c.gboolean {
    _ = user_data;
    if (engine.layers.list.items.len == 0) return 1; // Keep running but don't save empty

    const cache_dir_c = c.g_get_user_cache_dir();
    if (cache_dir_c == null) return 1;
    const cache_dir = std.mem.span(cache_dir_c);

    const path = std.fs.path.join(std.heap.c_allocator, &[_][]const u8{ cache_dir, "vimp", "autosave" }) catch return 1;
    defer std.heap.c_allocator.free(path);

    EngineIO.saveProject(&engine, path) catch |err| {
        std.debug.print("Autosave failed: {}\n", .{err});
    };

    return 1; // Continue
}

const RecoveryContext = struct {
    path: [:0]u8,
};

fn recovery_response(
    dialog: *c.AdwMessageDialog,
    response: [*c]const u8,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *RecoveryContext = @ptrCast(@alignCast(user_data));
    defer std.heap.c_allocator.destroy(ctx);
    defer std.heap.c_allocator.free(ctx.path);

    const resp_span = std.mem.span(response);

    if (std.mem.eql(u8, resp_span, "recover")) {
        EngineIO.loadProject(&engine, ctx.path) catch |err| {
            show_toast("Failed to recover project: {}", .{err});
        };
        sidebar_ui.refreshLayers();
        sidebar_ui.refreshUndo();
        update_view_mode();
        if (canvas_ui) |ui| ui.canvas_dirty = true;
        queue_draw();
    } else if (std.mem.eql(u8, resp_span, "discard")) {
        std.fs.cwd().deleteTree(ctx.path) catch {};
    }

    c.gtk_window_destroy(@ptrCast(dialog));
}

fn check_autosave(window: *c.GtkWindow) void {
    const cache_dir_c = c.g_get_user_cache_dir();
    if (cache_dir_c == null) return;
    const cache_dir = std.mem.span(cache_dir_c);

    const path = std.fs.path.joinZ(std.heap.c_allocator, &[_][]const u8{ cache_dir, "vimp", "autosave" }) catch return;
    // Don't free path yet, pass to ctx

    // Check if exists
    var dir = std.fs.cwd().openDir(path, .{}) catch {
        std.heap.c_allocator.free(path);
        return;
    };
    dir.close();

    // Check project.json
    const json_path = std.fs.path.joinZ(std.heap.c_allocator, &[_][]const u8{ path, "project.json" }) catch {
        std.heap.c_allocator.free(path);
        return;
    };
    defer std.heap.c_allocator.free(json_path);

    if (std.fs.cwd().access(json_path, .{})) |_| {
        // Found! Show dialog.
        const ctx = std.heap.c_allocator.create(RecoveryContext) catch {
            std.heap.c_allocator.free(path);
            return;
        };
        ctx.* = .{ .path = path };

        const dialog = c.adw_message_dialog_new(
            window,
            "Unsaved Work Found",
            "A previous session was not closed properly. Do you want to recover your work?",
        );

        c.adw_message_dialog_add_response(@ptrCast(dialog), "discard", "_Discard");
        c.adw_message_dialog_add_response(@ptrCast(dialog), "recover", "_Recover");

        c.adw_message_dialog_set_default_response(@ptrCast(dialog), "recover");
        c.adw_message_dialog_set_close_response(@ptrCast(dialog), "discard");

        _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&recovery_response), ctx, null, 0);

        c.gtk_window_present(@ptrCast(dialog));
    } else |_| {
        std.heap.c_allocator.free(path);
    }
}

const DropConfirmContext = struct {
    path: [:0]u8,
};

const DropContext = struct {
    window: ?*c.GtkWindow,
    canvas: *CanvasUI.Canvas,
};

fn drop_enter(
    _: *c.GtkDropTarget,
    _: f64,
    _: f64,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) c.GdkDragAction {
    const ctx: *DropContext = @ptrCast(@alignCast(user_data));
    if (engine.layers.list.items.len > 0) {
        ctx.canvas.showDropOverlay("Drop to Add Layer or Open New");
    } else {
        ctx.canvas.showDropOverlay("Drop to Open Image");
    }
    return c.GDK_ACTION_COPY;
}

fn drop_leave(
    _: *c.GtkDropTarget,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *DropContext = @ptrCast(@alignCast(user_data));
    ctx.canvas.hideDropOverlay();
}

fn drop_response(
    dialog: *c.AdwMessageDialog,
    response: [*c]const u8,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    const ctx: *DropConfirmContext = @ptrCast(@alignCast(user_data));
    // We must clean up context and path regardless of choice
    const allocator = std.heap.c_allocator;
    defer allocator.destroy(ctx);
    defer allocator.free(ctx.path);

    const resp_span = std.mem.span(response);

    if (std.mem.eql(u8, resp_span, "new")) {
        openFileFromPath(ctx.path, false, true, null);
    } else if (std.mem.eql(u8, resp_span, "layer")) {
        openFileFromPath(ctx.path, true, true, null);
    }
    // "cancel" or others do nothing but cleanup

    // Destroy the dialog
    c.gtk_window_destroy(@ptrCast(dialog));
}

fn drop_func(
    target: *c.GtkDropTarget,
    value: *const c.GValue,
    x: f64,
    y: f64,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) c.gboolean {
    _ = target;
    _ = x;
    _ = y;

    const ctx: *DropContext = @ptrCast(@alignCast(user_data));
    ctx.canvas.hideDropOverlay();

    // Check if we have a window handle
    const window = ctx.window;

    const file_obj = c.g_value_get_object(value);
    if (file_obj) |obj| {
        // Safe cast as we requested G_TYPE_FILE
        const file: *c.GFile = @ptrCast(obj);
        const path = c.g_file_get_path(file);
        if (path) |p| {
            const span = std.mem.span(@as([*:0]const u8, @ptrCast(p)));

            // Logic: If layers exist AND we have a window to show dialog on -> Ask User
            if (engine.layers.list.items.len > 0 and window != null) {
                const allocator = std.heap.c_allocator;
                // Copy path
                const path_copy = allocator.dupeZ(u8, span) catch {
                    c.g_free(p);
                    return 0;
                };

                const ctx_confirm = allocator.create(DropConfirmContext) catch {
                    allocator.free(path_copy);
                    c.g_free(p);
                    return 0;
                };
                ctx_confirm.* = .{ .path = path_copy };

                const dialog = c.adw_message_dialog_new(
                    window.?,
                    "Import Image",
                    "How would you like to open this image?",
                );

                c.adw_message_dialog_add_response(@ptrCast(dialog), "cancel", "_Cancel");
                c.adw_message_dialog_add_response(@ptrCast(dialog), "new", "_Open as New Image");
                c.adw_message_dialog_add_response(@ptrCast(dialog), "layer", "_Add as Layer");

                c.adw_message_dialog_set_default_response(@ptrCast(dialog), "layer");
                c.adw_message_dialog_set_close_response(@ptrCast(dialog), "cancel");

                _ = c.g_signal_connect_data(dialog, "response", @ptrCast(&drop_response), ctx_confirm, null, 0);

                c.gtk_window_present(@ptrCast(dialog));
            } else {
                const as_layers = (engine.layers.list.items.len > 0);
                openFileFromPath(span, as_layers, true, null);
            }

            c.g_free(p);
            return 1;
        }
    }

    return 0;
}

fn zoom_in_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    if (canvas_ui) |ui| ui.zoomIn();
}

fn zoom_out_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    if (canvas_ui) |ui| ui.zoomOut();
}

fn pixelize_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showPixelizeDialog(window, &engine, &refresh_ui_callback);
}

fn motion_blur_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showMotionBlurDialog(window, &engine, &refresh_ui_callback);
}

fn unsharp_mask_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showUnsharpMaskDialog(window, &engine, &refresh_ui_callback);
}

fn noise_reduction_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showNoiseReductionDialog(window, &engine, &refresh_ui_callback);
}

fn oilify_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showOilifyDialog(window, &engine, &refresh_ui_callback);
}

fn drop_shadow_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showDropShadowDialog(window, &engine, &refresh_ui_callback);
}

fn red_eye_removal_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showRedEyeRemovalDialog(window, &engine, &refresh_ui_callback);
}

fn waves_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showWavesDialog(window, &engine, &refresh_ui_callback);
}

fn supernova_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showSupernovaDialog(window, &engine, &refresh_ui_callback);
}

fn lighting_effects_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showLightingDialog(window, &engine, &refresh_ui_callback);
}

fn stretch_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    FilterDialog.showStretchSkewDialog(window, &engine, &refresh_ui_callback);
}

fn apply_preview_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.commitPreview() catch |err| {
        show_toast("Commit preview failed: {}", .{err});
    };
    refresh_header_ui();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
    sidebar_ui.refreshUndo();
}

fn discard_preview_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.cancelPreview();
    refresh_header_ui();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

fn invert_colors_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.invertColors() catch |err| {
        show_toast("Invert colors failed: {}", .{err});
        return;
    };
    sidebar_ui.refreshUndo();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

fn clear_image_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.clearActiveLayer() catch |err| {
        show_toast("Clear image failed: {}", .{err});
        return;
    };
    sidebar_ui.refreshUndo();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

fn flip_horizontal_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.flipHorizontal() catch |err| {
        show_toast("Flip horizontal failed: {}", .{err});
        return;
    };
    sidebar_ui.refreshUndo();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

fn flip_vertical_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.flipVertical() catch |err| {
        show_toast("Flip vertical failed: {}", .{err});
        return;
    };
    sidebar_ui.refreshUndo();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

fn rotate_90_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.rotate90() catch |err| {
        show_toast("Rotate 90 failed: {}", .{err});
        return;
    };
    sidebar_ui.refreshUndo();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

fn rotate_180_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.rotate180() catch |err| {
        show_toast("Rotate 180 failed: {}", .{err});
        return;
    };
    sidebar_ui.refreshUndo();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

fn rotate_270_activated(_: *c.GSimpleAction, _: ?*c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    engine.rotate270() catch |err| {
        show_toast("Rotate 270 failed: {}", .{err});
        return;
    };
    sidebar_ui.refreshUndo();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

fn canvas_size_callback(width: c_int, height: c_int, user_data: ?*anyopaque) void {
    _ = user_data;
    engine.setCanvasSize(width, height);
    sidebar_ui.refreshUndo();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

fn canvas_size_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    CanvasDialog.showCanvasSizeDialog(window, engine.canvas_width, engine.canvas_height, @ptrCast(&canvas_size_callback), null);
}

fn view_bitmap_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    if (window) |w| {
        FullscreenPreview.showFullscreenPreview(w, &engine);
    }
}

fn view_thumbnail_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    if (window) |w| {
        ThumbnailWindow.show(w, &thumbnail_ctx);
    }
}

fn command_palette_activated(_: *c.GSimpleAction, _: ?*c.GVariant, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const window: ?*c.GtkWindow = if (user_data) |ud| @ptrCast(@alignCast(ud)) else null;
    // We need the app pointer, which we can get from the window or pass it?
    // user_data is currently the window.
    if (window) |w| {
        const app = c.gtk_window_get_application(w);
        if (app) |a| {
            CommandPalette.showCommandPalette(w, a);
        }
    }
}

fn show_grid_change_state(action: *c.GSimpleAction, value: *c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const enabled = c.g_variant_get_boolean(value) != 0;
    if (canvas_ui) |ui| ui.setShowGrid(enabled);
    c.g_simple_action_set_state(action, value);
}

fn split_view_change_state(action: *c.GSimpleAction, value: *c.GVariant, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    const enabled = c.g_variant_get_boolean(value) != 0;
    if (canvas_ui) |ui| ui.setSplitView(enabled);
    c.g_simple_action_set_state(action, value);
}

fn queue_draw() void {
    if (canvas_ui) |ui| {
        ui.queueDraw();
    }
}

fn on_sidebar_content_change() void {
    update_view_mode();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

fn on_palette_color_changed() void {
    sidebar_ui.updateColorButton();
    queue_draw();
}

fn on_text_tool_complete() void {
    sidebar_ui.refreshLayers();
    sidebar_ui.refreshUndo();
    update_view_mode();
    if (canvas_ui) |ui| ui.canvas_dirty = true;
    queue_draw();
}

fn on_color_picked(color: [4]u8) void {
    _ = color;
    sidebar_ui.updateColorButton();
}

fn tool_toggled(
    button: *c.GtkToggleButton,
    user_data: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    if (c.gtk_toggle_button_get_active(button) == 1) {
        const tool_ptr = @as(*Tool, @ptrCast(@alignCast(user_data)));
        current_tool = tool_ptr.*;
        std.debug.print("Tool switched to: {}\n", .{current_tool});

        const is_transform = (current_tool == .unified_transform);
        if (sidebar_ui.tool_options_panel) |p| p.update(current_tool);
        if (canvas_ui) |ui| ui.updateTransformActionBar(is_transform);

        var ctx = ToolCreationContext{
            .window = null,
            .color_picked_cb = &on_color_picked,
            .text_complete_cb = &on_text_tool_complete,
        };

        if (current_tool == .text) {
            const root = c.gtk_widget_get_root(@ptrCast(button));
            if (root) |r| {
                ctx.window = @ptrCast(@alignCast(r));
            }
        }

        if (ToolFactory.createTool(std.heap.c_allocator, current_tool, ctx)) |tool| {
            if (canvas_ui) |ui| {
                ui.setActiveTool(tool);
                const name = ToolFactory.getToolName(current_tool);
                ui.showOSD(name);
            } else {
                tool.destroy(std.heap.c_allocator);
            }
        } else |err| {
            std.debug.print("Failed to create tool: {}\n", .{err});
        }
    }
}

fn on_paned_notify_position(
    paned: *c.GtkPaned,
    _: *c.GParamSpec,
    _: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    const width = c.gtk_widget_get_width(@ptrCast(@alignCast(paned)));
    if (width <= 0) return;

    var min_w: c_int = 0;
    var min_h: c_int = 0;
    const sidebar = c.gtk_paned_get_start_child(paned);
    if (sidebar) |s| {
        c.gtk_widget_get_size_request(s, &min_w, &min_h);
    }
    if (min_w < 0) min_w = 0;

    const constraint_max = @divTrunc(width, 5); // 20%
    const effective_max = if (constraint_max > min_w) constraint_max else min_w;

    const pos = c.gtk_paned_get_position(paned);

    if (pos > effective_max) {
        _ = c.g_signal_handlers_block_matched(
            @ptrCast(paned),
            c.G_SIGNAL_MATCH_FUNC | c.G_SIGNAL_MATCH_DATA,
            0,
            0,
            null,
            @ptrCast(@constCast(&on_paned_notify_position)),
            null,
        );
        c.gtk_paned_set_position(paned, effective_max);
        _ = c.g_signal_handlers_unblock_matched(
            @ptrCast(paned),
            c.G_SIGNAL_MATCH_FUNC | c.G_SIGNAL_MATCH_DATA,
            0,
            0,
            null,
            @ptrCast(@constCast(&on_paned_notify_position)),
            null,
        );
    }
}

fn on_paned_size_allocate(
    paned: *c.GtkPaned,
    width: c_int,
    _: c_int,
    _: c_int,
    _: ?*anyopaque,
) callconv(std.builtin.CallingConvention.c) void {
    if (width <= 0) return;

    var min_w: c_int = 0;
    var min_h: c_int = 0;
    const sidebar = c.gtk_paned_get_start_child(paned);
    if (sidebar) |s| {
        c.gtk_widget_get_size_request(s, &min_w, &min_h);
    }
    if (min_w < 0) min_w = 0;

    const constraint_max = @divTrunc(width, 5); // 20%
    const effective_max = if (constraint_max > min_w) constraint_max else min_w;

    const pos = c.gtk_paned_get_position(paned);

    if (pos > effective_max) {
        c.gtk_paned_set_position(paned, effective_max);
    }
}

fn activate(app: *c.GtkApplication, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    _ = user_data;

    // Init recent manager
    recent_manager = RecentManager.init(std.heap.c_allocator);
    recent_manager.load() catch |err| {
        std.debug.print("Failed to load recent files: {}\n", .{err});
    };

    // Init recent colors
    recent_colors_manager = RecentColorsManager.init(std.heap.c_allocator);
    recent_colors_manager.load() catch |err| {
        std.debug.print("Failed to load recent colors: {}\n", .{err});
    };

    // Start Autosave Timer (every 30 seconds)
    if (autosave_timer_id == 0) {
        autosave_timer_id = c.g_timeout_add_seconds(30, @ptrCast(&autosave_callback), null);
    }

    // Use AdwApplicationWindow
    const window = c.adw_application_window_new(app);
    c.gtk_window_set_title(@ptrCast(window), "Vimp");
    c.gtk_window_set_default_size(@ptrCast(window), 800, 600);

    // Actions Setup
    const add_action = struct {
        fn func(application: *c.GtkApplication, name: [:0]const u8, callback: c.GCallback, data: ?*anyopaque) void {
            const action = c.g_simple_action_new(name, null);
            _ = c.g_signal_connect_data(action, "activate", callback, data, null, 0);
            c.g_action_map_add_action(@ptrCast(application), @ptrCast(action));
        }
    }.func;

    add_action(app, "new", @ptrCast(&new_activated), null);
    add_action(app, "open", @ptrCast(&open_activated), window);
    add_action(app, "open-as-layers", @ptrCast(&open_as_layers_activated), window);
    add_action(app, "open-location", @ptrCast(&open_location_activated), window);
    add_action(app, "save", @ptrCast(&save_activated), window);
    add_action(app, "about", @ptrCast(&about_activated), null);
    add_action(app, "inspector", @ptrCast(&inspector_activated), null);
    add_action(app, "quit", @ptrCast(&quit_activated), app);

    // Salvage Action (Parameter: String)
    const salvage_action = c.g_simple_action_new("salvage", c.g_variant_type_new("s"));
    _ = c.g_signal_connect_data(salvage_action, "activate", @ptrCast(&salvage_activated), null, null, 0);
    c.g_action_map_add_action(@ptrCast(app), @ptrCast(salvage_action));

    add_action(app, "undo", @ptrCast(&undo_activated), null);
    add_action(app, "redo", @ptrCast(&redo_activated), null);
    add_action(app, "blur-small", @ptrCast(&blur_small_activated), null);
    add_action(app, "blur-medium", @ptrCast(&blur_medium_activated), null);
    add_action(app, "blur-large", @ptrCast(&blur_large_activated), null);
    add_action(app, "pixelize", @ptrCast(&pixelize_activated), window);
    add_action(app, "motion-blur", @ptrCast(&motion_blur_activated), window);
    add_action(app, "unsharp-mask", @ptrCast(&unsharp_mask_activated), window);
    add_action(app, "noise-reduction", @ptrCast(&noise_reduction_activated), window);
    add_action(app, "oilify", @ptrCast(&oilify_activated), window);
    add_action(app, "drop-shadow", @ptrCast(&drop_shadow_activated), window);
    add_action(app, "red-eye-removal", @ptrCast(&red_eye_removal_activated), window);
    add_action(app, "waves", @ptrCast(&waves_activated), window);
    add_action(app, "supernova", @ptrCast(&supernova_activated), window);
    add_action(app, "lighting-effects", @ptrCast(&lighting_effects_activated), window);
    add_action(app, "stretch", @ptrCast(&stretch_activated), window);
    add_action(app, "apply-preview", @ptrCast(&apply_preview_activated), null);
    add_action(app, "discard-preview", @ptrCast(&discard_preview_activated), null);
    add_action(app, "invert-colors", @ptrCast(&invert_colors_activated), null);
    add_action(app, "clear-image", @ptrCast(&clear_image_activated), null);
    add_action(app, "flip-horizontal", @ptrCast(&flip_horizontal_activated), null);
    add_action(app, "flip-vertical", @ptrCast(&flip_vertical_activated), null);
    add_action(app, "rotate-90", @ptrCast(&rotate_90_activated), null);
    add_action(app, "rotate-180", @ptrCast(&rotate_180_activated), null);
    add_action(app, "rotate-270", @ptrCast(&rotate_270_activated), null);
    add_action(app, "canvas-size", @ptrCast(&canvas_size_activated), window);
    add_action(app, "view-bitmap", @ptrCast(&view_bitmap_activated), window);
    add_action(app, "view-thumbnail", @ptrCast(&view_thumbnail_activated), window);
    add_action(app, "command-palette", @ptrCast(&command_palette_activated), window);
    add_action(app, "zoom-in", @ptrCast(&zoom_in_activated), null);
    add_action(app, "zoom-out", @ptrCast(&zoom_out_activated), null);

    // Split View Action (Stateful)
    const split_action = c.g_simple_action_new_stateful("split-view", null, c.g_variant_new_boolean(0));
    _ = c.g_signal_connect_data(split_action, "change-state", @ptrCast(&split_view_change_state), null, null, 0);
    c.g_action_map_add_action(@ptrCast(app), @ptrCast(split_action));

    // Show Grid Action (Stateful)
    const grid_action = c.g_simple_action_new_stateful("show-grid", null, c.g_variant_new_boolean(1));
    _ = c.g_signal_connect_data(grid_action, "change-state", @ptrCast(&show_grid_change_state), null, null, 0);
    c.g_action_map_add_action(@ptrCast(app), @ptrCast(grid_action));

    // Keyboard Shortcuts
    const set_accel = struct {
        fn func(application: *c.GtkApplication, action: [:0]const u8, accel: [:0]const u8) void {
            const accels = [_]?[*:0]const u8{ accel, null };
            c.gtk_application_set_accels_for_action(application, action, @ptrCast(&accels));
        }
    }.func;
    set_accel(app, "app.quit", "<Ctrl>q");
    set_accel(app, "app.new", "<Ctrl>n");
    set_accel(app, "app.open", "<Ctrl>o");
    set_accel(app, "app.open-as-layers", "<Ctrl><Alt>o");
    set_accel(app, "app.open-location", "<Ctrl>l");
    set_accel(app, "app.save", "<Ctrl>s");
    set_accel(app, "app.undo", "<Ctrl>z");
    set_accel(app, "app.redo", "<Ctrl>y");
    set_accel(app, "app.invert-colors", "<Ctrl>i");
    set_accel(app, "app.clear-image", "<Ctrl><Shift>n");
    set_accel(app, "app.rotate-90", "<Ctrl>r");
    set_accel(app, "app.command-palette", "<Ctrl>k");
    set_accel(app, "app.inspector", "<Ctrl><Shift>i");
    const zoom_in_accels = [_]?[*:0]const u8{ "<Ctrl>plus", "<Ctrl>equal", null };
    c.gtk_application_set_accels_for_action(app, "app.zoom-in", @ptrCast(&zoom_in_accels));
    set_accel(app, "app.zoom-out", "<Ctrl>minus");

    const toolbar_view = c.adw_toolbar_view_new();
    c.adw_application_window_set_content(@ptrCast(window), toolbar_view);

    // AdwToastOverlay
    const t_overlay = c.adw_toast_overlay_new();
    toast_overlay = @ptrCast(t_overlay);
    c.adw_toolbar_view_set_content(@ptrCast(toolbar_view), t_overlay);

    // GtkPaned
    const paned = c.gtk_paned_new(c.GTK_ORIENTATION_HORIZONTAL);
    c.adw_toast_overlay_set_child(@ptrCast(t_overlay), paned);

    // Connect constraints
    _ = c.g_signal_connect_data(paned, "notify::position", @ptrCast(&on_paned_notify_position), null, null, 0);
    _ = c.g_signal_connect_data(paned, "size-allocate", @ptrCast(&on_paned_size_allocate), null, null, 0);

    const callbacks = SidebarCallbacks{
        .tool_toggled = @ptrCast(&tool_toggled),
        .request_update = &on_sidebar_content_change,
        .palette_color_changed = &on_palette_color_changed,
    };

    sidebar_ui = Sidebar.create(std.heap.c_allocator, &engine, &recent_colors_manager, callbacks, @ptrCast(window)) catch |err| {
        std.debug.print("Failed to create sidebar: {}\n", .{err});
        return;
    };
    sidebar_ui.activateDefaultTool();

    header_ui = Header.create(std.heap.c_allocator, sidebar_ui.widget) catch |err| {
        std.debug.print("Failed to create header: {}\n", .{err});
        return;
    };
    c.adw_toolbar_view_add_top_bar(@ptrCast(toolbar_view), header_ui.widget);

    // Set sidebar as start child
    c.gtk_paned_set_start_child(@ptrCast(paned), sidebar_ui.widget);
    c.gtk_paned_set_resize_start_child(@ptrCast(paned), 1);
    c.gtk_paned_set_shrink_start_child(@ptrCast(paned), 0);
    c.gtk_paned_set_position(@ptrCast(paned), 200);

    // Main Content (Right / Content Pane)
    const content = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    c.gtk_widget_set_hexpand(content, 1);
    c.gtk_widget_add_css_class(content, "content");

    // Set as content in split view
    c.gtk_paned_set_end_child(@ptrCast(paned), content);
    c.gtk_paned_set_resize_end_child(@ptrCast(paned), 1);
    c.gtk_paned_set_shrink_end_child(@ptrCast(paned), 0);

    // Stack
    const stack = c.gtk_stack_new();
    main_stack = stack;
    c.gtk_widget_set_vexpand(stack, 1);
    c.gtk_widget_set_hexpand(stack, 1);
    c.gtk_box_append(@ptrCast(content), stack);

    // Welcome Page
    const welcome_page = c.adw_status_page_new();
    c.adw_status_page_set_icon_name(@ptrCast(welcome_page), "camera-photo-symbolic");
    c.adw_status_page_set_title(@ptrCast(welcome_page), "Welcome to Vimp");
    c.adw_status_page_set_description(@ptrCast(welcome_page), "Create a new image or open an existing one to get started.");

    const welcome_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_halign(welcome_box, c.GTK_ALIGN_CENTER);

    const welcome_new_btn = c.gtk_button_new_with_mnemonic("_New Image");
    c.gtk_widget_add_css_class(welcome_new_btn, "pill");
    c.gtk_widget_add_css_class(welcome_new_btn, "suggested-action");
    c.gtk_actionable_set_action_name(@ptrCast(welcome_new_btn), "app.new");
    c.gtk_box_append(@ptrCast(welcome_box), welcome_new_btn);

    const welcome_open_btn = c.gtk_button_new_with_mnemonic("_Open Image");
    c.gtk_widget_add_css_class(welcome_open_btn, "pill");
    c.gtk_actionable_set_action_name(@ptrCast(welcome_open_btn), "app.open");
    c.gtk_box_append(@ptrCast(welcome_box), welcome_open_btn);

    const welcome_open_loc_btn = c.gtk_button_new_with_mnemonic("Open _Location");
    c.gtk_widget_add_css_class(welcome_open_loc_btn, "pill");
    c.gtk_actionable_set_action_name(@ptrCast(welcome_open_loc_btn), "app.open-location");
    c.gtk_box_append(@ptrCast(welcome_box), welcome_open_loc_btn);

    // Recent Label
    const recent_label = c.gtk_label_new("Recent Files");
    c.gtk_widget_set_margin_top(recent_label, 20);
    c.gtk_widget_add_css_class(recent_label, "dim-label");
    c.gtk_box_append(@ptrCast(welcome_box), recent_label);

    // Recent List
    const recent_scrolled = c.gtk_scrolled_window_new();
    c.gtk_widget_set_vexpand(recent_scrolled, 1);
    c.gtk_widget_set_size_request(recent_scrolled, 400, 250);

    const recent_list = c.gtk_flow_box_new();
    c.gtk_flow_box_set_selection_mode(@ptrCast(recent_list), c.GTK_SELECTION_NONE);
    c.gtk_flow_box_set_max_children_per_line(@ptrCast(recent_list), 6);
    c.gtk_flow_box_set_min_children_per_line(@ptrCast(recent_list), 3);
    c.gtk_flow_box_set_row_spacing(@ptrCast(recent_list), 20);
    c.gtk_flow_box_set_column_spacing(@ptrCast(recent_list), 20);
    c.gtk_widget_set_valign(recent_list, c.GTK_ALIGN_START);

    c.gtk_scrolled_window_set_child(@ptrCast(recent_scrolled), recent_list);
    c.gtk_box_append(@ptrCast(welcome_box), recent_scrolled);

    recent_flow_box = recent_list;
    _ = c.g_signal_connect_data(recent_list, "child-activated", @ptrCast(&on_recent_child_activated), null, null, 0);

    refresh_recent_ui();

    c.adw_status_page_set_child(@ptrCast(welcome_page), welcome_box);
    _ = c.gtk_stack_add_named(@ptrCast(stack), welcome_page, "welcome");

    const canvas_callbacks = CanvasUI.CanvasCallbacks{
        .refresh_undo_ui = &refresh_undo_ui_wrapper,
        .reset_transform_ui = &reset_transform_ui_wrapper,
    };

    canvas_ui = CanvasUI.Canvas.create(std.heap.c_allocator, &engine, canvas_callbacks) catch |err| {
        std.debug.print("Failed to create canvas: {}\n", .{err});
        return;
    };
    _ = c.gtk_stack_add_named(@ptrCast(stack), canvas_ui.?.widget, "canvas");

    // Init Thumbnail Context
    thumbnail_ctx = .{
        .engine = &engine,
        .view_x = &canvas_ui.?.view_x,
        .view_y = &canvas_ui.?.view_y,
        .view_scale = &canvas_ui.?.view_scale,
        .main_drawing_area = canvas_ui.?.drawing_area,
        .queue_draw_main = &queue_draw,
    };

    // Drop Target (Attach to canvas drawing area)
    const drop_ctx = std.heap.c_allocator.create(DropContext) catch return;
    drop_ctx.* = .{
        .window = @ptrCast(window),
        .canvas = canvas_ui.?,
    };

    const drop_target = c.gtk_drop_target_new(c.g_file_get_type(), c.GDK_ACTION_COPY);
    _ = c.g_signal_connect_data(drop_target, "enter", @ptrCast(&drop_enter), drop_ctx, null, 0);
    _ = c.g_signal_connect_data(drop_target, "leave", @ptrCast(&drop_leave), drop_ctx, null, 0);
    _ = c.g_signal_connect_data(drop_target, "drop", @ptrCast(&drop_func), drop_ctx, null, 0);
    c.gtk_widget_add_controller(canvas_ui.?.drawing_area, @ptrCast(drop_target));

    // Refresh Layers UI initially
    sidebar_ui.refreshLayers();
    sidebar_ui.refreshUndo();
    update_view_mode();

    // CSS Styling
    const css_provider = c.gtk_css_provider_new();
    const css =
        \\.sidebar { padding: 10px; }
    ;
    // Note: Adwaita handles colors better, using shared variables
    c.gtk_css_provider_load_from_data(css_provider, css, -1);

    const display = c.gtk_widget_get_display(@ptrCast(window));
    c.gtk_style_context_add_provider_for_display(display, @ptrCast(css_provider), c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    c.g_object_unref(css_provider);

    c.gtk_window_present(@ptrCast(window));

    check_autosave(@ptrCast(window));
}
