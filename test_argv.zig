const std = @import("std");

pub fn main() void {
    std.debug.print("Argv len: {d}\n", .{std.os.argv.len});
}
