const std = @import("std");

const c = @cImport({
    @cInclude("gtk/gtk.h");
});

pub fn main() !void {
    // Initialize GTK
    // We pass 0 and null because we aren't parsing command line args for GTK yet
    c.gtk_init();

    std.debug.print("GTK initialized successfully. Vimp shell starting...\n", .{});

    // Create a dummy application to prove we can access GTK symbols
    // In a real app we'd use GtkApplication
    const app = c.gtk_application_new("org.vimp.app", c.G_APPLICATION_DEFAULT_FLAGS);
    _ = app; // suppress unused variable error

    std.debug.print("Created GtkApplication instance.\n", .{});
}
