const std = @import("std");
const net = std.Io.net;
const Io = std.Io;
const print = std.debug.print;

const DB = @import("db/db.zig").DB;
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

    var db: DB = .{
        .io = io,
        .accounts = .init(gpa),
        .items = .init(gpa),
        .skills = .init(gpa),
        .characters = .init(gpa),
    };

    // _ = try db.accounts.create(.{
    //     .username = try .fromSlice("qwer"),
    //     .hash = .{ 186, 117, 211, 48, 160, 7, 17, 59, 47, 33, 1, 52, 234, 181, 167, 97 }, // qwer:qwer
    // });
    // _ = try db.accounts.create(.{
    //     .username = try .fromSlice("qwe"),
    //     .hash = .{ 186, 117, 211, 48, 160, 7, 17, 59, 47, 33, 1, 52, 234, 181, 167, 97 }, // qwer:qwer
    // });
    //
    // const char = try @import("db/types/character.zig").getExampleChar();
    // const char_id = try db.characters.create(char);
    //
    // var buf: [512]u8 = undefined;
    // const items = try @import("db/types/inventory.zig").getExampleEquipmentItems(&buf, char_id);
    //     // _ = try db.items.create(items[17]);
    // for (items) |item| {
    //     _ = try db.items.create(item);
    // }
    //
    // _ = try db.skills.create(.{ .skill_id = 167, .char_id = char_id, .level = 1 });
    // _ = try db.skills.create(.{ .skill_id = 234, .char_id = char_id, .level = 1 });
    // _ = try db.skills.create(.{ .skill_id = 235, .char_id = char_id, .level = 1 });
    // _ = try db.skills.create(.{ .skill_id = 1000, .char_id = char_id, .level = 1 });
    // _ = try db.skills.create(.{ .skill_id = 1001, .char_id = char_id, .level = 1 });
    // _ = try db.skills.create(.{ .skill_id = 1002, .char_id = char_id, .level = 1 });
    //
    // try db.save();
    try db.load(gpa);

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
