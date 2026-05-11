const std = @import("std");
const net = std.Io.net;
const Io = std.Io;
const print = std.debug.print;

const world = @import("world/world.zig");
const session = @import("server/session.zig");
const events = @import("events/events.zig");

const Channel = events.Channel;
const Message = events.Message;
const Action = events.Action;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var threaded: Io.Threaded = .init(gpa, .{});
    const io = threaded.io();

    const address = try net.IpAddress.parse("127.0.0.1", 29000);
    var server = try address.listen(io, .{ .reuse_address = true });
    print("INFO: [Server] Listening on {f}\n", .{address});
    defer server.deinit(io);

    var group: Io.Group = .init;
    defer group.cancel(io);

    var actions_back: [128]Action = undefined;
    var actions_front: [128]Action = undefined;
    var actions_channel: Channel(Action) = .init(io, &actions_back, &actions_front);
    var messages_back: [128]Message = undefined;
    var messages_front: [128]Message = undefined;
    var messages_channel: Channel(Message) = .init(io, &messages_back, &messages_front);

    try group.concurrent(io, world.start, .{ io, gpa, &messages_channel, &actions_channel });

    while (true) {
        print("INFO: [Server] Waiting for new connection...\n", .{});
        var stream = try server.accept(io);
        try group.concurrent(io, session.start, .{ io, gpa, &stream, &messages_channel, &actions_channel });
    }
}
