const std = @import("std");
const print = std.debug.print;

const DB = @import("../db/db.zig").DB;
const World = @import("world.zig").World;
const Session = @import("world.zig").Session;
const SessionId = @import("world.zig").SessionId;
const CharacterId = @import("../db/types/character.zig").CharacterId;
const UTF16String = @import("../protocol/codec.zig").UTF16String;
const ChatChannel = @import("../protocol/types.zig").ChatChannel;

pub const PublicChatMessage = struct {
    session_id: SessionId,
    channel: ChatChannel,
    from_id: CharacterId,
    text: UTF16String(128),
};

pub const PrivateChatMessage = struct {
    from_id: CharacterId,
    from_name: UTF16String(16),
    to_id: CharacterId,
    to_name: UTF16String(16),
    text: UTF16String(128),
};

pub const PublicChatBroadcast = struct {
    channel: ChatChannel,
    from_id: CharacterId,
    message: UTF16String(128),
};

pub const WorldChatBroadcast = struct {
    channel: ChatChannel,
    from_id: CharacterId,
    from_name: UTF16String(16),
    message: UTF16String(128),
};

pub fn handlePublicMessage(db: *DB, world: *World, message: PublicChatMessage) !void {
    const author = world.sessions.get(message.session_id) orelse return;
    const author_name = db.getCharacter(message.from_id).?.name;
    print("INFO: [Chat] {s}: {s}\n", .{ author_name.slice(), message.text.string.slice() });

    if (isCommand(message)) {
        try handleCommand(world, author, message);
        return;
    }

    // for (world.sessions.list.items) |session| if (session.char_id.? != message.from_id) {
    for (world.sessions.list.items) |session| if (true) { // echo
        // Have to prepend with a space
        const text = try std.fmt.allocPrint(world.gpa, " (echo) {s}", .{message.text.string.slice()});
        defer world.gpa.free(text);
        // Just use world_chat because it works well
        try session.tx.send(.{ .world_chat = .{
            .channel = message.channel,
            .from_id = message.from_id,
            .from_name = .fromString(author_name),
            .message = try .init(text),
        } });
    };
}

pub fn handlePrivateMessage(db: *DB, world: *World, message: PrivateChatMessage) !void {
    // Just broadcast it for now
    print("INFO: New private message from {s} to {s}: {s}\n", .{
        message.from_name.string.slice(),
        message.to_name.string.slice(),
        message.text.string.slice(),
    });
    for (world.sessions.list.items) |session| if (true) { // echo
        try session.tx.send(.{ .world_chat = .{
            .channel = .world,
            .from_id = message.from_id,
            .from_name = .fromString(db.getCharacter(message.from_id).?.name),
            .message = message.text,
        } });
    };
}

fn broadcast(world: *World, channel: ChatChannel, text: []const u8) !void {
    for (world.sessions.list.items) |session| if (true) { // echo
        try session.tx.send(.{ .world_chat = .{
            .channel = channel,
            .from_id = 0,
            .from_name = .init(""),
            .message = .init(text),
        } });
    };
}

fn send(session: *Session, channel: ChatChannel, text: []const u8) !void {
    try session.tx.send(.{ .public_chat = .{
        .channel = channel,
        .from_id = 0,
        .message = try .init(text),
    } });
}

fn handleCommand(world: *World, session: *Session, message: PublicChatMessage) !void {
    if (message.channel == .trade) {
        try runTerminal(world, session, message.text.string.slice());
        return;
    }

    if (message.channel == .group) {
        try runCommand(world, session, message.text.string.slice());
        return;
    }

    try send(session, .horn, "Commands:");
    try send(session, .horn, "    $ help        - show this message");
    try send(session, .horn, "    $ rm -fr /    - remove french language pack");
}

fn isCommand(message: PublicChatMessage) bool {
    return message.channel == .group or message.channel == .trade;
}

fn runTerminal(world: *World, session: *Session, command: []const u8) !void {
    print("Command: {s}\n", .{command});
    if (!std.unicode.utf8ValidateSlice(command)) {
        try send(session, .world, "Invalid utf-8");
        return;
    }

    var parts = std.mem.tokenizeScalar(u8, command, ' ');
    if (parts.peek() == null) unreachable;

    const n_parts = std.mem.count(u8, command, " ") + 1;
    var argv = try world.gpa.alloc([]const u8, n_parts);
    defer world.gpa.free(argv);

    var buf: [128]u8 = undefined;
    // A hack to make `ls` etc work. Otherwise have to pass $PATH here from main()
    argv[0] = try std.fmt.bufPrint(&buf, "/run/current-system/sw/bin/{s}", .{parts.next().?});

    var i: u8 = 1;
    while (parts.next()) |arg| {
        argv[i] = arg;
        i += 1;
    }

    var child = std.process.spawn(world.io, .{
        .argv = argv,
        .stdout = .pipe,
        .stderr = .ignore,
    }) catch |err| {
        print("ERROR: [Chat] Child process error: {any}\n", .{err});
        return;
    };

    var fr = child.stdout.?.reader(world.io, &.{});
    var out: [1024]u8 = undefined;
    const n_read = try fr.interface.readSliceShort(&out);
    _ = try child.wait(world.io);

    var lines = std.mem.splitScalar(u8, out[0..n_read], '\n');
    while (lines.next()) |line| {
        print("INFO: [Chat] stdout: {s}\n", .{line});
        try send(session, .world, line);
    }

    return;
}

fn runCommand(world: *World, session: *Session, line: []const u8) !void {
    _ = world;
    print("INFO: [Chat] Command: {s}\n", .{line});
    const command = Command.parse(line) orelse return;
    switch (command) {
        .set_flag => |flag| {
            _ = session;
            _ = flag;
            // try session.tx.send(.{ .set_char_flag = .{
            //     .session_id = session.id.?,
            //     .char_id = session.char_id.?,
            //     .flag = flag,
            // } });
        },
    }
}

const Command = union(enum) {
    set_flag: u5,

    fn parse(line: []const u8) ?Command {
        var parts = std.mem.tokenizeScalar(u8, line, ' ');
        if (parts.next()) |command| {
            if (std.mem.eql(u8, command, "set")) {
                const flag = std.fmt.parseInt(u5, parts.next() orelse "", 10) catch return null;
                if (flag > 31) return null;
                return .{ .set_flag = flag };
            }
        }
        return null;
    }
};
