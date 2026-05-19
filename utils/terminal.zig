const std = @import("std");

pub fn c(comptime color: u8) []const u8 {
    return std.fmt.comptimePrint("\x1b[38;5;{d}m", .{color});
}

pub fn r() []const u8 {
    return "\x1b[0m";
}
