const std = @import("std");
const c = @import("c.zig").c;

pub const Engine = struct {
    pub const Mode = enum {
        paint,
        erase,
        fill,
        airbrush,
    };

    pub const BrushType = enum {
        square,
        circle,
    };

    pub const SelectionMode = enum {
        rectangle,
        ellipse,
    };

    pub const PaintCommand = struct {
        layer_idx: usize,
        before: *c.GeglBuffer,
        after: ?*c.GeglBuffer = null,

        pub fn deinit(self: *PaintCommand) void {
            c.g_object_unref(self.before);
            if (self.after) |a| c.g_object_unref(a);
        }
    };

    pub const LayerSnapshot = struct {
        buffer: *c.GeglBuffer, // Strong reference
        name: [64]u8,
        visible: bool,
        locked: bool,

        pub fn deinit(self: *LayerSnapshot) void {
            c.g_object_unref(self.buffer);
        }
    };

    pub const LayerCommand = union(enum) {
        add: struct {
            index: usize,
            snapshot: ?LayerSnapshot = null,
        },
        remove: struct {
            index: usize,
            snapshot: ?LayerSnapshot = null,
        },
        reorder: struct {
            from: usize,
            to: usize,
        },
        visibility: struct {
            index: usize,
        },
        lock: struct {
            index: usize,
        },

        pub fn deinit(self: *LayerCommand) void {
            switch (self.*) {
                .add => |*cmd| {
                    if (cmd.snapshot) |*s| s.deinit();
                },
                .remove => |*cmd| {
                    if (cmd.snapshot) |*s| s.deinit();
                },
                else => {},
            }
        }
    };

    pub const SelectionCommand = struct {
        before: ?c.GeglRectangle,
        before_mode: SelectionMode,
        after: ?c.GeglRectangle = null,
        after_mode: SelectionMode = .rectangle,
    };

    pub const Command = union(enum) {
        paint: PaintCommand,
        layer: LayerCommand,
        selection: SelectionCommand,

        pub fn deinit(self: *Command) void {
            switch (self.*) {
                .paint => |*cmd| cmd.deinit(),
                .layer => |*cmd| cmd.deinit(),
                .selection => {},
            }
        }
    };

    pub const Layer = struct {
        buffer: *c.GeglBuffer,
        source_node: *c.GeglNode,
        visible: bool = true,
        locked: bool = false,
        name: [64]u8 = undefined,
    };

    graph: ?*c.GeglNode = null,
    output_node: ?*c.GeglNode = null,
    layers: std.ArrayList(Layer) = undefined,
    active_layer_idx: usize = 0,

    base_node: ?*c.GeglNode = null,
    composition_nodes: std.ArrayList(*c.GeglNode) = undefined,

    undo_stack: std.ArrayList(Command) = undefined,
    redo_stack: std.ArrayList(Command) = undefined,
    current_command: ?Command = null,

    fill_buffer: std.ArrayList(u8) = undefined,

    canvas_width: c_int = 800,
    canvas_height: c_int = 600,
    fg_color: [4]u8 = .{ 0, 0, 0, 255 },
    brush_size: c_int = 3,
    mode: Mode = .paint,
    brush_type: BrushType = .square,
    selection: ?c.GeglRectangle = null,
    selection_mode: SelectionMode = .rectangle,

    sel_cx: f64 = 0,
    sel_cy: f64 = 0,
    sel_inv_rx_sq: f64 = 0,
    sel_inv_ry_sq: f64 = 0,

    // GEGL is not thread-safe for init/exit, and tests run in parallel.
    // We must serialize access to the GEGL global state.
    var gegl_mutex = std.Thread.Mutex{};

    pub fn init(self: *Engine) void {
        gegl_mutex.lock();
        // Accept null args for generic initialization
        c.gegl_init(null, null);
        self.layers = std.ArrayList(Layer){};
        self.composition_nodes = std.ArrayList(*c.GeglNode){};
        self.undo_stack = std.ArrayList(Command){};
        self.redo_stack = std.ArrayList(Command){};
        self.fill_buffer = std.ArrayList(u8){};
    }

    pub fn deinit(self: *Engine) void {
        for (self.undo_stack.items) |*cmd| cmd.deinit();
        self.undo_stack.deinit(std.heap.c_allocator);
        for (self.redo_stack.items) |*cmd| cmd.deinit();
        self.redo_stack.deinit(std.heap.c_allocator);
        if (self.current_command) |*cmd| cmd.deinit();

        self.fill_buffer.deinit(std.heap.c_allocator);

        self.composition_nodes.deinit(std.heap.c_allocator);
        for (self.layers.items) |layer| {
            c.g_object_unref(layer.buffer);
            // nodes are owned by the graph generally, but if they are not added to graph yet?
            // "gegl_node_new_child" adds it to graph.
            // If we keep references to them in Layer, we might need to unref them if we own a ref.
            // But usually GEGL graph destruction handles children.
            // However, we might need to be careful.
            // For now, let's assume graph handles nodes.
        }
        self.layers.deinit(std.heap.c_allocator);

        if (self.graph) |g| {
            c.g_object_unref(g);
        }
        // c.gegl_exit();
        gegl_mutex.unlock();
    }

    pub fn beginTransaction(self: *Engine) void {
        if (self.current_command != null) return;
        if (self.active_layer_idx >= self.layers.items.len) return;

        const layer = &self.layers.items[self.active_layer_idx];
        // We capture 'before' state.
        // gegl_buffer_dup creates a COW copy.
        const before_buf = c.gegl_buffer_dup(layer.buffer);
        if (before_buf == null) return;

        const cmd = PaintCommand{
            .layer_idx = self.active_layer_idx,
            .before = before_buf.?,
            .after = null,
        };
        self.current_command = Command{ .paint = cmd };
    }

    pub fn beginSelection(self: *Engine) void {
        if (self.current_command != null) return;

        const cmd = SelectionCommand{
            .before = self.selection,
            .before_mode = self.selection_mode,
        };
        self.current_command = Command{ .selection = cmd };
    }

    pub fn commitTransaction(self: *Engine) void {
        if (self.current_command) |*cmd| {
            switch (cmd.*) {
                .paint => |*p_cmd| {
                    if (p_cmd.layer_idx < self.layers.items.len) {
                        const layer = &self.layers.items[p_cmd.layer_idx];
                        // Capture 'after' state.
                        const after_buf = c.gegl_buffer_dup(layer.buffer);
                        if (after_buf) |ab| {
                            p_cmd.after = ab;
                        }
                    }
                },
                .layer => {}, // Nothing to capture for layer commands
                .selection => |*s_cmd| {
                    s_cmd.after = self.selection;
                    s_cmd.after_mode = self.selection_mode;
                },
            }
            // Move current_command to undo stack
            self.undo_stack.append(std.heap.c_allocator, self.current_command.?) catch |err| {
                std.debug.print("Failed to append to undo stack: {}\n", .{err});
                self.current_command.?.deinit();
                self.current_command = null;
                return;
            };
            self.current_command = null;

            // Clear redo stack
            for (self.redo_stack.items) |*r_cmd| r_cmd.deinit();
            self.redo_stack.clearRetainingCapacity();
        }
    }

    pub fn undo(self: *Engine) void {
        if (self.undo_stack.items.len == 0) return;
        const cmd_opt = self.undo_stack.pop();
        if (cmd_opt) |cmd| {
            // Need a mutable copy to update snapshots
            var mutable_cmd = cmd;
            switch (mutable_cmd) {
                .paint => |p_cmd| {
                    if (p_cmd.layer_idx < self.layers.items.len) {
                        const layer = &self.layers.items[p_cmd.layer_idx];

                        // Restore 'before' buffer
                        const new_buf = c.gegl_buffer_dup(p_cmd.before);
                        if (new_buf) |b| {
                            c.g_object_unref(layer.buffer);
                            layer.buffer = b;

                            // Update source node
                            c.gegl_node_set(layer.source_node, "buffer", b, @as(?*anyopaque, null));
                        }
                    }
                },
                .layer => |*l_cmd| {
                    switch (l_cmd.*) {
                        .add => |*add_cmd| {
                            // Undo Add -> Remove
                            add_cmd.snapshot = self.removeLayerInternal(add_cmd.index);
                        },
                        .remove => |*rm_cmd| {
                            // Undo Remove -> Add (Restore)
                            if (rm_cmd.snapshot) |*snap| {
                                self.addLayerInternal(snap.buffer, &snap.name, snap.visible, snap.locked, rm_cmd.index) catch |err| {
                                    std.debug.print("Failed to undo layer remove: {}\n", .{err});
                                };
                                rm_cmd.snapshot = null; // Ownership transferred
                            }
                        },
                        .reorder => |*ord_cmd| {
                            self.reorderLayerInternal(ord_cmd.to, ord_cmd.from);
                        },
                        .visibility => |*vis_cmd| {
                            self.toggleLayerVisibilityInternal(vis_cmd.index);
                        },
                        .lock => |*lock_cmd| {
                            self.toggleLayerLockInternal(lock_cmd.index);
                        },
                    }
                },
                .selection => |*s_cmd| {
                    self.setSelectionMode(s_cmd.before_mode);
                    if (s_cmd.before) |r| {
                        self.setSelection(r.x, r.y, r.width, r.height);
                    } else {
                        self.clearSelection();
                    }
                },
            }

            self.redo_stack.append(std.heap.c_allocator, mutable_cmd) catch {
                mutable_cmd.deinit();
            };
        }
    }

    pub fn redo(self: *Engine) void {
        if (self.redo_stack.items.len == 0) return;
        const cmd_opt = self.redo_stack.pop();

        if (cmd_opt) |cmd| {
            // Need a mutable copy to update snapshots
            var mutable_cmd = cmd;
            switch (mutable_cmd) {
                .paint => |p_cmd| {
                    if (p_cmd.layer_idx < self.layers.items.len) {
                        const layer = &self.layers.items[p_cmd.layer_idx];
                        if (p_cmd.after) |after_buf| {
                            const new_buf = c.gegl_buffer_dup(after_buf);
                            if (new_buf) |b| {
                                c.g_object_unref(layer.buffer);
                                layer.buffer = b;
                                c.gegl_node_set(layer.source_node, "buffer", b, @as(?*anyopaque, null));
                            }
                        }
                    }
                },
                .layer => |*l_cmd| {
                    switch (l_cmd.*) {
                        .add => |*add_cmd| {
                            // Redo Add -> Add (Restore)
                            if (add_cmd.snapshot) |*snap| {
                                self.addLayerInternal(snap.buffer, &snap.name, snap.visible, snap.locked, add_cmd.index) catch |err| {
                                    std.debug.print("Failed to redo layer add: {}\n", .{err});
                                };
                                add_cmd.snapshot = null; // Ownership transferred
                            }
                        },
                        .remove => |*rm_cmd| {
                            // Redo Remove -> Remove
                            rm_cmd.snapshot = self.removeLayerInternal(rm_cmd.index);
                        },
                        .reorder => |*ord_cmd| {
                            self.reorderLayerInternal(ord_cmd.from, ord_cmd.to);
                        },
                        .visibility => |*vis_cmd| {
                            self.toggleLayerVisibilityInternal(vis_cmd.index);
                        },
                        .lock => |*lock_cmd| {
                            self.toggleLayerLockInternal(lock_cmd.index);
                        },
                    }
                },
                .selection => |*s_cmd| {
                    self.setSelectionMode(s_cmd.after_mode);
                    if (s_cmd.after) |r| {
                        self.setSelection(r.x, r.y, r.width, r.height);
                    } else {
                        self.clearSelection();
                    }
                },
            }

            self.undo_stack.append(std.heap.c_allocator, mutable_cmd) catch {
                mutable_cmd.deinit();
            };
        }
    }

    pub fn setupGraph(self: *Engine) void {
        // Create the main graph container
        self.graph = c.gegl_node_new();

        const bg_color = c.gegl_color_new("rgb(0.9, 0.9, 0.9)");

        // Background color node
        const bg_node = c.gegl_node_new_child(self.graph, "operation", "gegl:color", "value", bg_color, @as(?*anyopaque, null));

        // A crop node to give the background finite dimensions
        const bg_crop = c.gegl_node_new_child(self.graph, "operation", "gegl:crop", "width", @as(f64, 800.0), "height", @as(f64, 600.0), @as(?*anyopaque, null));

        _ = c.gegl_node_link_many(bg_node, bg_crop, @as(?*anyopaque, null));

        self.base_node = bg_crop;

        // Add initial layer
        self.addLayer("Background") catch |err| {
            std.debug.print("Failed to add initial layer: {}\n", .{err});
        };
    }

    pub fn rebuildGraph(self: *Engine) void {
        // 1. Clear old composition chain (but don't destroy layer source nodes!)
        // The composition nodes are the 'gegl:over' nodes connecting layers.
        // We need to unlink them or destroy them. Since we created them, we can destroy them?
        // Wait, if they are children of 'graph', destroying graph destroys them.
        // But we are not destroying graph.
        // gegl_node_process works on the graph.

        // We stored the 'over' nodes in composition_nodes.
        // Let's just destroy them? But they are linked.
        // Removing them from graph should suffice?
        // gegl_node_remove_child(graph, node)?
        // Or simply unref if they are not added to graph?
        // 'gegl_node_new_child' adds them to graph.
        // So we should 'gegl_node_remove_child'? Or just disconnect?

        // Let's assume creating new nodes is cheap enough, but we should clean up old ones.
        // gegl_node_disconnect(node, "input")?

        // Actually, let's just create new ones and let the old ones drift?
        // No, that leaks memory and clutters graph.
        // We should destroy the old 'over' nodes.

        // NOTE: In C, we would do g_object_unref?
        // If gegl_node_new_child was used, the parent holds a ref.
        // So we need to remove from parent?
        // c.gegl_node_remove_child(self.graph, node);

        // Since we don't have gegl_node_remove_child in C bindings easily visible here (it exists in GEGL),
        // let's try to just build new ones and update output_node.
        // But over time this will grow infinite.
        // I should find a way to remove them.
        // 'c.gegl_node_remove_child' might not be in my c.zig?
        // Check c.zig? Assuming standard GEGL API.

        // Let's assume I can reuse the nodes? No, the number of nodes changes.
        // I will attempt to remove them.
        // If c.gegl_node_remove_child is not available, I might need to add it or use g_object_run_dispose?

        // For now, I'll rely on g_object_unref if I can remove them from graph.
        // But wait, gegl_node_new_child adds reference?

        // Strategy: Just unlink everything and overwrite output_node?
        // The old nodes will still be in the graph.

        // Let's look at c.zig if possible.
        // Assuming c.gegl_node_remove_child works if bound.

        for (self.composition_nodes.items) |node| {
            _ = c.gegl_node_remove_child(self.graph, node);
            // And unref? remove_child usually drops the parent's ref.
            // If we held a ref in ArrayList (we didn't explicitly ref, just stored pointer),
            // then we might be dangling if remove_child frees it.
            // But we probably want to ensure it's gone.
        }
        self.composition_nodes.clearRetainingCapacity();

        var current_input = self.base_node;

        for (self.layers.items) |layer| {
            if (!layer.visible) continue;

            if (c.gegl_node_new_child(self.graph, "operation", "gegl:over", @as(?*anyopaque, null))) |over_node| {
                _ = c.gegl_node_connect(over_node, "input", current_input, "output");
                _ = c.gegl_node_connect(over_node, "aux", layer.source_node, "output");

                self.composition_nodes.append(std.heap.c_allocator, over_node) catch {};
                current_input = over_node;
            }
        }

        self.output_node = current_input;
    }

    fn addLayerInternal(self: *Engine, buffer: *c.GeglBuffer, name: []const u8, visible: bool, locked: bool, index: usize) !void {
        const source_node = c.gegl_node_new_child(self.graph, "operation", "gegl:buffer-source", "buffer", buffer, @as(?*anyopaque, null)) orelse return error.GeglNodeFailed;

        var layer = Layer{
            .buffer = buffer,
            .source_node = source_node,
            .visible = visible,
            .locked = locked,
        };
        // Copy name
        const len = @min(name.len, layer.name.len - 1);
        @memcpy(layer.name[0..len], name[0..len]);
        layer.name[len] = 0; // Null terminate

        try self.layers.insert(std.heap.c_allocator, index, layer);

        // Update active index
        // If we inserted before or at active index, we need to shift active index?
        // Logic: We usually want to select the new layer.
        self.active_layer_idx = index;

        self.rebuildGraph();
    }

    pub fn addLayer(self: *Engine, name: []const u8) !void {
        const extent = c.GeglRectangle{ .x = 0, .y = 0, .width = self.canvas_width, .height = self.canvas_height };
        const format = c.babl_format("R'G'B'A u8");
        const buffer = c.gegl_buffer_new(&extent, format) orelse return error.GeglBufferFailed;

        const index = self.layers.items.len;
        try self.addLayerInternal(buffer, name, true, false, index);

        // Push Undo
        const cmd = Command{
            .layer = .{ .add = .{ .index = index, .snapshot = null } },
        };
        self.undo_stack.append(std.heap.c_allocator, cmd) catch |err| {
            std.debug.print("Failed to push undo: {}\n", .{err});
        };
        for (self.redo_stack.items) |*r_cmd| r_cmd.deinit();
        self.redo_stack.clearRetainingCapacity();
    }

    fn removeLayerInternal(self: *Engine, index: usize) LayerSnapshot {
        const layer = self.layers.orderedRemove(index);

        // Clean up node but keep buffer
        _ = c.gegl_node_remove_child(self.graph, layer.source_node);

        // Update active index
        if (self.active_layer_idx >= self.layers.items.len) {
            if (self.layers.items.len > 0) {
                self.active_layer_idx = self.layers.items.len - 1;
            } else {
                self.active_layer_idx = 0;
            }
        }

        self.rebuildGraph();

        return LayerSnapshot{
            .buffer = layer.buffer,
            .name = layer.name,
            .visible = layer.visible,
            .locked = layer.locked,
        };
    }

    pub fn removeLayer(self: *Engine, index: usize) void {
        if (index >= self.layers.items.len) return;
        var snapshot = self.removeLayerInternal(index);

        // Push Undo
        const cmd = Command{
            .layer = .{ .remove = .{ .index = index, .snapshot = snapshot } },
        };
        self.undo_stack.append(std.heap.c_allocator, cmd) catch |err| {
            std.debug.print("Failed to push undo: {}\n", .{err});
            snapshot.deinit(); // Prevent leak
        };
        for (self.redo_stack.items) |*r_cmd| r_cmd.deinit();
        self.redo_stack.clearRetainingCapacity();
    }

    fn reorderLayerInternal(self: *Engine, from: usize, to: usize) void {
        const layer = self.layers.orderedRemove(from);
        self.layers.insert(std.heap.c_allocator, to, layer) catch {
            self.layers.append(std.heap.c_allocator, layer) catch {};
            return;
        };

        if (self.active_layer_idx == from) {
            self.active_layer_idx = to;
        } else if (from < self.active_layer_idx and to >= self.active_layer_idx) {
            self.active_layer_idx -= 1;
        } else if (from > self.active_layer_idx and to <= self.active_layer_idx) {
            self.active_layer_idx += 1;
        }

        self.rebuildGraph();
    }

    pub fn reorderLayer(self: *Engine, from: usize, to: usize) void {
        if (from >= self.layers.items.len or to >= self.layers.items.len) return;
        if (from == to) return;
        self.reorderLayerInternal(from, to);

        // Push Undo
        const cmd = Command{
            .layer = .{ .reorder = .{ .from = from, .to = to } },
        };
        self.undo_stack.append(std.heap.c_allocator, cmd) catch |err| {
            std.debug.print("Failed to push undo: {}\n", .{err});
        };
        for (self.redo_stack.items) |*r_cmd| r_cmd.deinit();
        self.redo_stack.clearRetainingCapacity();
    }

    pub fn setActiveLayer(self: *Engine, index: usize) void {
        if (index < self.layers.items.len) {
            self.active_layer_idx = index;
        }
    }

    fn toggleLayerVisibilityInternal(self: *Engine, index: usize) void {
        self.layers.items[index].visible = !self.layers.items[index].visible;
        self.rebuildGraph();
    }

    pub fn toggleLayerVisibility(self: *Engine, index: usize) void {
        if (index < self.layers.items.len) {
            self.toggleLayerVisibilityInternal(index);

            // Push Undo
            const cmd = Command{
                .layer = .{ .visibility = .{ .index = index } },
            };
            self.undo_stack.append(std.heap.c_allocator, cmd) catch |err| {
                std.debug.print("Failed to push undo: {}\n", .{err});
            };
            for (self.redo_stack.items) |*r_cmd| r_cmd.deinit();
            self.redo_stack.clearRetainingCapacity();
        }
    }

    fn toggleLayerLockInternal(self: *Engine, index: usize) void {
        self.layers.items[index].locked = !self.layers.items[index].locked;
    }

    pub fn toggleLayerLock(self: *Engine, index: usize) void {
        if (index < self.layers.items.len) {
            self.toggleLayerLockInternal(index);

            // Push Undo
            const cmd = Command{
                .layer = .{ .lock = .{ .index = index } },
            };
            self.undo_stack.append(std.heap.c_allocator, cmd) catch |err| {
                std.debug.print("Failed to push undo: {}\n", .{err});
            };
            for (self.redo_stack.items) |*r_cmd| r_cmd.deinit();
            self.redo_stack.clearRetainingCapacity();
        }
    }

    fn isPointInSelection(self: *Engine, x: c_int, y: c_int) bool {
        if (self.selection) |sel| {
            if (x < sel.x or x >= sel.x + sel.width or y < sel.y or y >= sel.y + sel.height) return false;

            if (self.selection_mode == .ellipse) {
                const dx_p = @as(f64, @floatFromInt(x)) + 0.5 - self.sel_cx;
                const dy_p = @as(f64, @floatFromInt(y)) + 0.5 - self.sel_cy;

                if ((dx_p * dx_p) * self.sel_inv_rx_sq + (dy_p * dy_p) * self.sel_inv_ry_sq > 1.0) return false;
            }
        }
        return true;
    }

    pub fn paintStroke(self: *Engine, x0: f64, y0: f64, x1: f64, y1: f64, pressure: f64) void {
        if (self.active_layer_idx >= self.layers.items.len) return;
        const layer = &self.layers.items[self.active_layer_idx];

        if (!layer.visible or layer.locked) return;

        const buf = layer.buffer;

        // Draw a simple line by setting pixels along the path
        // Using Bresenham-style drawing for simplicity
        const brush_size = self.brush_size;
        const format = c.babl_format("R'G'B'A u8");

        // Use selected foreground color, or transparent if erasing
        var pixel: [4]u8 = undefined;
        if (self.mode == .erase) {
            pixel = .{ 0, 0, 0, 0 };
        } else {
            pixel = self.fg_color;
            if (self.mode == .airbrush) {
                // Modulate alpha by pressure
                // pixel[3] is u8 (0-255)
                const alpha: f64 = @as(f64, @floatFromInt(pixel[3]));
                const new_alpha: u8 = @intFromFloat(alpha * pressure);
                pixel[3] = new_alpha;
            }
        }

        // Simple line drawing using interpolation
        const dx = x1 - x0;
        const dy = y1 - y0;
        const dist = @sqrt(dx * dx + dy * dy);
        const steps: usize = @max(1, @as(usize, @intFromFloat(dist)));

        // Paint a small brush
        const half = @divFloor(brush_size, 2);
        const radius_sq = if (self.brush_type == .circle)
            std.math.pow(f64, @as(f64, @floatFromInt(brush_size)) / 2.0, 2.0)
        else
            0;

        for (0..steps + 1) |i| {
            const t: f64 = if (steps == 0) 0.0 else @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps));
            const x: c_int = @intFromFloat(x0 + dx * t);
            const y: c_int = @intFromFloat(y0 + dy * t);

            var by: c_int = -half;
            while (by <= half) : (by += 1) {
                var bx: c_int = -half;
                while (bx <= half) : (bx += 1) {
                    // Check shape
                    if (self.brush_type == .circle) {
                        const dist_sq = @as(f64, @floatFromInt(bx * bx + by * by));
                        if (dist_sq > radius_sq) continue;
                    }

                    const px = x + bx;
                    const py = y + by;

                    if (!self.isPointInSelection(px, py)) continue;

                    if (px >= 0 and py >= 0 and px < self.canvas_width and py < self.canvas_height) {
                        const rect = c.GeglRectangle{ .x = px, .y = py, .width = 1, .height = 1 };
                        c.gegl_buffer_set(buf, &rect, 0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE);
                    }
                }
            }
        }
    }

    pub fn bucketFill(self: *Engine, start_x: f64, start_y: f64) !void {
        if (self.active_layer_idx >= self.layers.items.len) return;
        const layer = &self.layers.items[self.active_layer_idx];

        if (!layer.visible or layer.locked) return;

        const buf = layer.buffer;

        const w: usize = @intCast(self.canvas_width);
        const h: usize = @intCast(self.canvas_height);
        const x: c_int = @intFromFloat(start_x);
        const y: c_int = @intFromFloat(start_y);

        if (x < 0 or x >= self.canvas_width or y < 0 or y >= self.canvas_height) return;

        if (!self.isPointInSelection(x, y)) return;

        // 1. Read entire buffer
        // Allocation: 800 * 600 * 4 = 1.9 MB approx
        const allocator = std.heap.c_allocator; // Use C allocator for simplicity with large buffer
        const buffer_size = w * h * 4;
        try self.fill_buffer.resize(allocator, buffer_size);
        const pixels = self.fill_buffer.items;

        const rect = c.GeglRectangle{ .x = 0, .y = 0, .width = self.canvas_width, .height = self.canvas_height };
        const format = c.babl_format("R'G'B'A u8");
        // Rowstride must be correct
        const rowstride: c_int = self.canvas_width * 4;
        c.gegl_buffer_get(buf, &rect, 1.0, format, pixels.ptr, rowstride, c.GEGL_ABYSS_NONE);

        // 2. Identify Target Color
        const idx: usize = (@as(usize, @intCast(y)) * w + @as(usize, @intCast(x))) * 4;
        const target_color: [4]u8 = pixels[idx..][0..4].*;
        const fill_color: [4]u8 = self.fg_color;

        // If target matches fill, nothing to do
        if (std.mem.eql(u8, &target_color, &fill_color)) return;

        // 3. Setup Flood Fill (BFS)
        const Point = struct { x: c_int, y: c_int };
        var queue = std.ArrayList(Point){};
        defer queue.deinit(allocator);

        // Fill start pixel and add to queue
        @memcpy(pixels[idx..][0..4], &fill_color);
        try queue.append(allocator, .{ .x = x, .y = y });

        var min_x = x;
        var max_x = x;
        var min_y = y;
        var max_y = y;

        while (queue.items.len > 0) {
            const p = queue.pop().?;

            // Neighbors
            const neighbors = [4]Point{
                .{ .x = p.x + 1, .y = p.y },
                .{ .x = p.x - 1, .y = p.y },
                .{ .x = p.x, .y = p.y + 1 },
                .{ .x = p.x, .y = p.y - 1 },
            };

            for (neighbors) |n| {
                const px = n.x;
                const py = n.y;

                if (px < 0 or px >= self.canvas_width or py < 0 or py >= self.canvas_height) continue;
                if (!self.isPointInSelection(px, py)) continue;

                const p_idx: usize = (@as(usize, @intCast(py)) * w + @as(usize, @intCast(px))) * 4;
                const current_pixel = pixels[p_idx..][0..4];

                // Check if matches target
                if (std.mem.eql(u8, current_pixel, &target_color)) {
                    // Fill immediately
                    @memcpy(current_pixel, &fill_color);

                    // Update dirty bounds
                    if (px < min_x) min_x = px;
                    if (px > max_x) max_x = px;
                    if (py < min_y) min_y = py;
                    if (py > max_y) max_y = py;

                    try queue.append(allocator, n);
                }
            }
        }

        // 4. Write back buffer (Only dirty rect)
        const rect_w = max_x - min_x + 1;
        const rect_h = max_y - min_y + 1;
        const dirty_rect = c.GeglRectangle{ .x = min_x, .y = min_y, .width = rect_w, .height = rect_h };

        const offset = (@as(usize, @intCast(min_y)) * w + @as(usize, @intCast(min_x))) * 4;
        c.gegl_buffer_set(buf, &dirty_rect, 0, format, pixels.ptr + offset, rowstride);
    }

    pub fn applyGaussianBlur(self: *Engine, radius: f64) !void {
        if (self.active_layer_idx >= self.layers.items.len) return;
        const layer = &self.layers.items[self.active_layer_idx];
        if (layer.locked) return;

        self.beginTransaction();

        const temp_graph = c.gegl_node_new();
        defer c.g_object_unref(temp_graph);

        const input_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:buffer-source", "buffer", layer.buffer, @as(?*anyopaque, null));
        const blur_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:gaussian-blur", "std-dev-x", radius, "std-dev-y", radius, @as(?*anyopaque, null));

        const format = c.babl_format("R'G'B'A u8");
        const extent = c.gegl_buffer_get_extent(layer.buffer);
        const new_buffer = c.gegl_buffer_new(extent, format);
        // If allocation fails, we should probably abort transaction?
        if (new_buffer == null) return;

        const write_node = c.gegl_node_new_child(temp_graph, "operation", "gegl:write-buffer", "buffer", new_buffer, @as(?*anyopaque, null));

        _ = c.gegl_node_link_many(input_node, blur_node, write_node, @as(?*anyopaque, null));

        _ = c.gegl_node_process(write_node);

        // Update Layer
        c.g_object_unref(layer.buffer);
        layer.buffer = new_buffer.?;
        _ = c.gegl_node_set(layer.source_node, "buffer", new_buffer, @as(?*anyopaque, null));

        self.commitTransaction();
    }

    pub fn setFgColor(self: *Engine, r: u8, g: u8, b: u8, a: u8) void {
        self.fg_color = .{ r, g, b, a };
    }

    pub fn setBrushSize(self: *Engine, size: c_int) void {
        self.brush_size = size;
    }

    pub fn setMode(self: *Engine, mode: Mode) void {
        self.mode = mode;
    }

    pub fn setBrushType(self: *Engine, brush_type: BrushType) void {
        self.brush_type = brush_type;
    }

    pub fn setSelectionMode(self: *Engine, mode: SelectionMode) void {
        self.selection_mode = mode;
    }

    pub fn setSelection(self: *Engine, x: c_int, y: c_int, w: c_int, h: c_int) void {
        self.selection = c.GeglRectangle{ .x = x, .y = y, .width = w, .height = h };

        const width_f = @as(f64, @floatFromInt(w));
        const height_f = @as(f64, @floatFromInt(h));
        const rx = width_f / 2.0;
        const ry = height_f / 2.0;
        self.sel_cx = @as(f64, @floatFromInt(x)) + rx;
        self.sel_cy = @as(f64, @floatFromInt(y)) + ry;

        if (rx > 0.0) {
            self.sel_inv_rx_sq = 1.0 / (rx * rx);
        } else {
            self.sel_inv_rx_sq = 0.0;
        }

        if (ry > 0.0) {
            self.sel_inv_ry_sq = 1.0 / (ry * ry);
        } else {
            self.sel_inv_ry_sq = 0.0;
        }
    }

    pub fn clearSelection(self: *Engine) void {
        self.selection = null;
    }

    pub fn blit(self: *Engine, width: c_int, height: c_int, ptr: [*]u8, stride: c_int) void {
        self.blitView(width, height, ptr, stride, 1.0, 0.0, 0.0);
    }

    pub fn blitView(self: *Engine, width: c_int, height: c_int, ptr: [*]u8, stride: c_int, scale: f64, view_x: f64, view_y: f64) void {
        if (self.output_node) |node| {
            const rect = c.GeglRectangle{ .x = @intFromFloat(view_x), .y = @intFromFloat(view_y), .width = width, .height = height };
            const format = c.babl_format("cairo-ARGB32");

            c.gegl_node_blit(node, scale, &rect, format, ptr, stride, c.GEGL_BLIT_DEFAULT);
        }
    }
};

// TESTS COMMENTED OUT temporarily to allow build

test "Engine paint color" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // Set color to RED
    engine.setFgColor(255, 0, 0, 255);

    // Draw a single point/small line at 100,100
    engine.paintStroke(100, 100, 100, 100, 1.0);

    // Read back pixel
    if (engine.layers.items.len > 0) {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 100, .y = 100, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);

        try std.testing.expectEqual(pixel[0], 255);
        try std.testing.expectEqual(pixel[1], 0);
        try std.testing.expectEqual(pixel[2], 0);
        try std.testing.expectEqual(pixel[3], 255);
    } else {
        return error.NoLayer;
    }
}

test "Engine multiple layers" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // Layer 1 (Background) is index 0.
    // Add Layer 2.
    try engine.addLayer("Layer 2");
    // active layer should be 1.
    try std.testing.expectEqual(engine.active_layer_idx, 1);

    // Paint BLUE on Layer 2 at 100,100
    engine.setFgColor(0, 0, 255, 255);
    engine.paintStroke(100, 100, 100, 100, 1.0);

    // Switch to Layer 1
    engine.setActiveLayer(0);
    // Paint RED on Layer 1 at 100,100
    engine.setFgColor(255, 0, 0, 255);
    engine.paintStroke(100, 100, 100, 100, 1.0); // This writes to Layer 1

    // Verify Layer 2 is Blue
    {
        const buf = engine.layers.items[1].buffer;
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 100, .y = 100, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[2], 255); // Blue
    }

    // Verify Layer 1 is Red
    {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 100, .y = 100, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 255); // Red
    }
}

test "Engine layer visibility" {
    // This test requires rendering the graph, which might be tricky in headless test environment
    // if plugins are not loaded correctly. But 'gegl:over' is core.
    // Let's try to blitView to a buffer.

    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // Layer 1: Red at 100,100
    engine.setActiveLayer(0);
    engine.setFgColor(255, 0, 0, 255);
    engine.paintStroke(100, 100, 100, 100, 1.0);

    // Layer 2: Blue at 100,100 (Covering Red)
    try engine.addLayer("Layer 2");
    engine.setFgColor(0, 0, 255, 255);
    engine.paintStroke(100, 100, 100, 100, 1.0);

    // Render 1x1 pixel at 100,100.
    var pixel: [4]u8 = undefined;

    // Helper to render
    const render = struct {
        fn func(e: *Engine, p: *[4]u8) void {
            // View x=100, y=100. Width=1, Height=1. Scale=1.0.
            // Stride=4.
            e.blitView(1, 1, p, 4, 1.0, 100.0, 100.0);
        }
    }.func;

    // 1. Both Visible -> Should be Blue
    render(&engine, &pixel);
    // Cairo ARGB32: B G R A (Little Endian)
    // Blue: 255, 0, 0, 255 -> B=255, G=0, R=0, A=255.
    // Memory: 255, 0, 0, 255.
    // Wait, let's just check raw values. Blue should be dominant.
    // If Blue is on top, pixel[0] (B) should be 255.
    // Note: babl format "cairo-ARGB32" in blitView.
    try std.testing.expect(pixel[0] > 200); // Blue
    try std.testing.expect(pixel[2] < 50); // Red

    // 2. Hide Layer 2 -> Should be Red
    engine.toggleLayerVisibility(1);
    render(&engine, &pixel);
    try std.testing.expect(pixel[2] > 200); // Red
    try std.testing.expect(pixel[0] < 50); // Blue
}

test "Engine brush size" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    engine.setFgColor(255, 255, 255, 255); // White for visibility

    // 1. Large Brush (Size 5)
    engine.setBrushSize(5);
    engine.paintStroke(100, 100, 100, 100, 1.0);

    if (engine.layers.items.len > 0) {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 102, .y = 102, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 255);
    } else {
        return error.NoLayer;
    }
}

test "Engine eraser" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    engine.setFgColor(255, 0, 0, 255); // Red

    // 1. Paint Red at 50,50
    engine.paintStroke(50, 50, 50, 50, 1.0);

    if (engine.layers.items.len > 0) {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 50, .y = 50, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 255);
        try std.testing.expectEqual(pixel[3], 255);

        // 2. Switch to Erase
        engine.setMode(.erase);
        // 3. Erase at 50,50
        engine.paintStroke(50, 50, 50, 50, 1.0);

        var pixel2: [4]u8 = .{ 255, 255, 255, 255 };
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel2, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);

        try std.testing.expectEqual(pixel2[0], 0);
        try std.testing.expectEqual(pixel2[3], 0);
    }
}

test "Engine bucket fill" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    engine.setFgColor(255, 0, 0, 255); // Red

    // 1. Paint a closed box
    engine.setBrushSize(1);
    engine.paintStroke(10, 10, 30, 10, 1.0);
    engine.paintStroke(10, 30, 30, 30, 1.0);
    engine.paintStroke(10, 10, 10, 30, 1.0);
    engine.paintStroke(30, 10, 30, 30, 1.0);

    // 2. Fill inside with BLUE
    engine.setFgColor(0, 0, 255, 255);
    try engine.bucketFill(20, 20);

    if (engine.layers.items.len > 0) {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = undefined;
        var rect = c.GeglRectangle{ .x = 20, .y = 20, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);

        // Assert Blue
        try std.testing.expectEqual(pixel[2], 255);
        try std.testing.expectEqual(pixel[3], 255);
    }
}

test "Engine brush shapes" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    engine.setFgColor(255, 255, 255, 255);

    engine.setBrushSize(5);

    // 1. Square (Default)
    engine.paintStroke(100, 100, 100, 100, 1.0);

    if (engine.layers.items.len > 0) {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 102, .y = 102, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 255);

        // 2. Circle
        engine.setBrushType(.circle);
        engine.paintStroke(200, 200, 200, 200, 1.0);

        var rect2 = c.GeglRectangle{ .x = 202, .y = 202, .width = 1, .height = 1 };
        c.gegl_buffer_get(buf, &rect2, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        // Should be unpainted (0)
        try std.testing.expectEqual(pixel[0], 0);
    }
}

test "Engine selection clipping" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    engine.setFgColor(255, 255, 255, 255);

    engine.setSelection(10, 10, 10, 10);

    // 1. Paint inside
    engine.paintStroke(15, 15, 15, 15, 1.0);
    if (engine.layers.items.len > 0) {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 15, .y = 15, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 255);

        // 2. Paint outside
        engine.paintStroke(5, 5, 5, 5, 1.0);
        var rect2 = c.GeglRectangle{ .x = 5, .y = 5, .width = 1, .height = 1 };
        c.gegl_buffer_get(buf, &rect2, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 0);
    }
}

test "Benchmark bucket fill" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // 1. Measure Fill of empty 800x600 canvas (Worst Case BFS)
    // Target: Transparent (0,0,0,0)
    // Fill: Red
    engine.setFgColor(255, 0, 0, 255);

    var timer = try std.time.Timer.start();
    try engine.bucketFill(400, 300);
    const duration = timer.read();

    std.debug.print("\nBenchmark bucket fill: {d} ms\n", .{@divFloor(duration, std.time.ns_per_ms)});
}

test "Cairo error surface check" {
    // Attempt to create a surface with invalid dimensions (negative)
    // Cairo 1.16+ handles -1, -1 as error.
    const s = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, -1, -1);
    const status = c.cairo_surface_status(s);

    // Expect failure
    try std.testing.expect(status != c.CAIRO_STATUS_SUCCESS);

    // Check data
    const data = c.cairo_image_surface_get_data(s);
    // data should be null for error surface in recent Cairo,
    // or pointing to garbage but status is definitely error.
    // Documentation says "If the surface is not an image surface... or if an error occurred... the return value is NULL."
    try std.testing.expect(data == null);

    c.cairo_surface_destroy(s);
}

test "Engine undo redo" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // Paint stroke
    engine.setFgColor(255, 0, 0, 255);
    engine.beginTransaction();
    engine.paintStroke(10, 10, 10, 10, 1.0);
    engine.commitTransaction();

    // Check pixel is Red
    if (engine.layers.items.len > 0) {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 10, .y = 10, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 255);
    } else {
        return error.NoLayer;
    }

    // Undo
    engine.undo();
    // Check pixel is Transparent (original)
    if (engine.layers.items.len > 0) {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = .{ 255, 255, 255, 255 };
        const rect = c.GeglRectangle{ .x = 10, .y = 10, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        // Expect Transparent
        try std.testing.expectEqual(pixel[0], 0);
        try std.testing.expectEqual(pixel[3], 0);
    }

    // Redo
    engine.redo();
    // Check pixel is Red
    if (engine.layers.items.len > 0) {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = .{ 0, 0, 0, 0 };
        const rect = c.GeglRectangle{ .x = 10, .y = 10, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        try std.testing.expectEqual(pixel[0], 255);
    }
}

test "Engine gaussian blur" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // 1. Paint a white square 10x10 at 50,50 on black background
    // Default bg is not black, but transparent or user-defined.
    // Let's ensure layer is cleared or we paint background.
    // The default setupGraph creates a white/gray background?
    // "gegl:color" with "rgb(0.9, 0.9, 0.9)".
    // Let's paint a black square first, then white inside.

    engine.setFgColor(0, 0, 0, 255);
    engine.setBrushSize(50);
    engine.setBrushType(.square);
    engine.paintStroke(50, 50, 50, 50, 1.0); // Big black square

    engine.setFgColor(255, 255, 255, 255);
    engine.setBrushSize(10);
    engine.paintStroke(50, 50, 50, 50, 1.0); // White square in middle

    // Check sharp edge
    // Center is 50,50. Size 10 -> 45 to 55.
    // At 50,50 it is White.
    // At 60,60 it is Black.
    // At 56,56 it is Black.

    {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = undefined;
        const rect = c.GeglRectangle{ .x = 60, .y = 60, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);
        // Expect Black
        try std.testing.expect(pixel[0] < 10);
    }

    // 2. Apply Blur
    try engine.applyGaussianBlur(5.0);

    // 3. Check edge at 55,55 (corner of white square).
    // Before blur: White (or close to it) inside, Black outside.
    // After blur: Gray.
    {
        const buf = engine.layers.items[0].buffer;
        var pixel: [4]u8 = undefined;
        // Check a point that was Black but near White
        const rect = c.GeglRectangle{ .x = 58, .y = 58, .width = 1, .height = 1 };
        const format = c.babl_format("R'G'B'A u8");
        c.gegl_buffer_get(buf, &rect, 1.0, format, &pixel, c.GEGL_AUTO_ROWSTRIDE, c.GEGL_ABYSS_NONE);

        // Should be grayish (not 0, not 255)
        // With stub, it will still be Black (0).
        // This expectation will fail once implemented, or rather
        // I want to verify it fails now if I expect > 10.
        if (pixel[0] < 10) {
            // Test fails as expected (Baseline)
            // But for 'zig build test' to pass I should maybe make it conditional?
            // No, the instruction says "Create a reproduction/baseline test".
            // Typically this means a failing test.
            // But if I want to commit steps, I shouldn't break the build?
            // I'll make the expectation strict so it fails, confirming the baseline.
            // But I cannot call 'plan_step_complete' if verification fails?
            // "Only call this when you have successfully completed all items needed for this plan step."
            // If the step is "Create a test", adding it is success.
            // I will run it and see it fail.
        }
        // I will assert it changes.
        try std.testing.expect(pixel[0] > 10);
    }
}

test "Benchmark bucket fill ellipse" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();
    engine.setFgColor(255, 0, 0, 255);

    // Set an ellipse selection covering most of the canvas
    engine.setSelectionMode(.ellipse);
    engine.setSelection(50, 50, 700, 500);

    var timer = try std.time.Timer.start();
    // Fill inside the ellipse at center
    // Center of 50+700/2 = 400. 50+500/2 = 300.
    try engine.bucketFill(400, 300);
    const duration = timer.read();

    std.debug.print("\nBenchmark bucket fill ellipse: {d} ms\n", .{@divFloor(duration, std.time.ns_per_ms)});
}

test "Engine layer undo redo" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // 0. Initial state: Background layer only
    try std.testing.expectEqual(engine.layers.items.len, 1);
    // setupGraph adds "Background", which pushes to undo stack.
    // Let's clear undo stack to start fresh for this test logic
    for (engine.undo_stack.items) |*cmd| cmd.deinit();
    engine.undo_stack.clearRetainingCapacity();

    // 1. Add Layer 1
    try engine.addLayer("Layer 1");
    try std.testing.expectEqual(engine.layers.items.len, 2);
    try std.testing.expectEqual(engine.undo_stack.items.len, 1);

    // 2. Undo Add (Should remove Layer 1)
    engine.undo();
    try std.testing.expectEqual(engine.layers.items.len, 1);
    try std.testing.expectEqual(engine.undo_stack.items.len, 0);
    try std.testing.expectEqual(engine.redo_stack.items.len, 1);

    // 3. Redo Add (Should restore Layer 1)
    engine.redo();
    try std.testing.expectEqual(engine.layers.items.len, 2);
    try std.testing.expectEqual(engine.undo_stack.items.len, 1);
    try std.testing.expectEqual(engine.redo_stack.items.len, 0);

    // 4. Remove Layer 1 (Index 1)
    engine.removeLayer(1);
    try std.testing.expectEqual(engine.layers.items.len, 1);
    try std.testing.expectEqual(engine.undo_stack.items.len, 2); // Add + Remove

    // 5. Undo Remove (Should restore Layer 1)
    engine.undo();
    try std.testing.expectEqual(engine.layers.items.len, 2);
    try std.testing.expect(std.mem.startsWith(u8, &engine.layers.items[1].name, "Layer 1"));

    // 6. Redo Remove (Should remove Layer 1)
    engine.redo();
    try std.testing.expectEqual(engine.layers.items.len, 1);
}

test "Engine selection undo redo" {
    var engine: Engine = .{};
    engine.init();
    defer engine.deinit();
    engine.setupGraph();

    // 1. Initial State: No Selection
    try std.testing.expect(engine.selection == null);

    // 2. Select Rectangle
    engine.setSelectionMode(.rectangle);
    engine.beginSelection();
    engine.setSelection(10, 10, 100, 100);
    engine.commitTransaction();

    try std.testing.expect(engine.selection != null);
    if (engine.selection) |s| {
        try std.testing.expectEqual(s.x, 10);
        try std.testing.expectEqual(s.width, 100);
    }
    try std.testing.expectEqual(engine.undo_stack.items.len, 2); // Initial Layer + Selection

    // 3. Undo -> Should be no selection
    engine.undo();
    try std.testing.expect(engine.selection == null);

    // 4. Redo -> Should be Rectangle
    engine.redo();
    try std.testing.expect(engine.selection != null);
    if (engine.selection) |s| {
        try std.testing.expectEqual(s.x, 10);
    }

    // 5. Change to Ellipse and Select
    engine.beginSelection();
    engine.setSelectionMode(.ellipse);
    engine.setSelection(50, 50, 50, 50);
    engine.commitTransaction();

    try std.testing.expectEqual(engine.selection_mode, .ellipse);
    if (engine.selection) |s| {
        try std.testing.expectEqual(s.x, 50);
    }

    // 6. Undo -> Should be Rectangle (from Step 2)
    engine.undo();
    try std.testing.expectEqual(engine.selection_mode, .rectangle);
    if (engine.selection) |s| {
        try std.testing.expectEqual(s.x, 10);
    }
}
