const std = @import("std");
const net = std.Io.net;
const Io = std.Io;
const print = std.debug.print;

const world = @import("world/world.zig");
const Action = @import("world/events.zig").Action;
const Channel = @import("world/events.zig").Channel;
const session = @import("server/session.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var threaded: Io.Threaded = .init(gpa, .{});
    const io = threaded.io();

    const address = try net.IpAddress.parse("127.0.0.1", 29000);
    var server = try address.listen(io, .{ .reuse_address = true });
    print("INFO: Listening on {f}\n", .{address});
    defer server.deinit(io);

    var group: Io.Group = .init;
    defer group.cancel(io);

    var chan_back: [128]Action = undefined;
    var chan_front: [128]Action = undefined;
    var actions_channel: Channel(Action) = .{
        .back = .initBuffer(&chan_back),
        .front = .initBuffer(&chan_front),
        .mutex = .init,
        .io = io,
    };

    try group.concurrent(io, world.start, .{ io, gpa, &actions_channel });

    while (true) {
        print("INFO: Waiting for new connection...\n", .{});
        const stream = try server.accept(io);
        try group.concurrent(io, session.start, .{ io, gpa, stream, &actions_channel });
    }
}
