const std = @import("std");
const net = std.Io.net;
const Io = std.Io;
const print = std.debug.print;

const session = @import("server/session.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    const address = try net.IpAddress.parse("127.0.0.1", 29000);
    var server = try address.listen(io, .{ .reuse_address = true });
    print("INFO: Listening on {f}\n", .{address});
    defer server.deinit(io);

    while (true) {
        print("INFO: Waiting for new connection...\n", .{});
        const stream = try server.accept(io);
        _ = io.async(session.start, .{ io, gpa.allocator(), stream });

        // var task = io.async(session.start, .{ io, stream });
        // defer _ = task.cancel(io);

        // const thread = try std.Thread.spawn(.{}, session.run, .{ io, stream });
        // thread.detach();
    }
}
