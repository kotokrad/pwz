const std = @import("std");
const net = std.Io.net;
const Io = std.Io;
const print = std.debug.print;

const DB = @import("db/db.zig").DB;
const world = @import("world/world.zig");
const session = @import("server/session.zig");
const seed = @import("db/seed.zig").seed;
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

    var db: DB = .init(gpa, io);
    defer db.deinit();

    try seed(&db);
    try db.save();
    try db.load();

    var group: Io.Group = .init;
    defer group.cancel(io);

    var actions_channel: Channel(Action) = try .init(io, gpa, 128);
    var messages_channel: Channel(Message) = try .init(io, gpa, 128);

    try group.concurrent(io, world.start, .{ io, gpa, &messages_channel, &actions_channel, &db });

    while (true) {
        print("INFO: [Server] Waiting for new connection...\n", .{});
        var stream = try server.accept(io);
        try group.concurrent(io, session.start, .{ io, gpa, &stream, &messages_channel, &actions_channel, &db });
    }
}
