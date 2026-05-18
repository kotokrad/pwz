const std = @import("std");
const print = std.debug.print;

const codec = @import("../../protocol/codec.zig");
const packets = @import("../../protocol/packets.zig");
const events = @import("../../events/events.zig");
const BoundedArray = @import("../../utils/utils.zig").BoundedArray;
const Session = @import("../session.zig").Session;

const Reply = events.Reply;
const Action = events.Action;
const ActionPayload = events.ActionPayload;
const Owned = packets.Owned;
const InPacket = packets.InPacket;
const EnterWorld = packets.EnterWorld;
const GetUIConfig = packets.GetUIConfig;
const GetUIConfigRe = packets.GetUIConfigRe;
const GetFriends = packets.GetFriends;
const GetFriendsRe = packets.GetFriendsRe;
const GetSavedMsg = packets.GetSavedMsg;
const GetSavedMsgRe = packets.GetSavedMsgRe;
const GetHelpStates = packets.GetHelpStates;
const GetHelpStatesRe = packets.GetHelpStatesRe;
const BattleGetMap = packets.BattleGetMap;
const BattleGetMapRe = packets.BattleGetMapRe;
const CheckNewMail = packets.CheckNewMail;
const PublicMessage = packets.PublicMessage;
const PrivateMessage = packets.PrivateMessage;
const PublicChat = packets.PublicChat;
const WorldChat = packets.WorldChat;

pub fn handleInWorld(session: *Session, packet: Owned(InPacket)) !void {
    errdefer packet.deinit();
    switch (packet.value) {
        // zig fmt: off
        .enter_world          => |payload| try handleEnterWorld(session, payload),
        .gamedata             => |payload| try handleGamedata(session, payload),
        .get_ui_config        => |payload| try handleGetUIConfig(session, payload),
        .get_friends          => |payload| try handleGetFriends(session, payload),
        .get_saved_msg        => |payload| try handleGetSavedMsg(session, payload),
        .get_help_states      => |payload| try handleGetHelpStates(session, payload),
        .battle_get_map       => |payload| try handleBattleGetMap(session, payload),
        .check_new_mail       => |payload| try handleCheckNewMail(session, payload),
        .public_message       => |payload| try handlePublicMessage(session, payload),
        .private_message      => |payload| try handlePrivateMessage(session, payload),
        // zig fmt: on

        else => print("WARNING: [InWorld] Unhandled packet:\n    {any}\n", .{packet.value}),
    }
}

fn handleEnterWorld(session: *Session, payload: EnterWorld) !void {
    try session.messages_tx.append(.{ .enter_world = .{
        .session_id = @truncate(session.id.?),
        .char_id = @truncate(payload.char_id),
    } });
}

fn handleGetUIConfig(session: *Session, payload: GetUIConfig) !void {
    var reply: Reply(BoundedArray(u8, 512)) = .{};
    try session.messages_tx.append(.{ .get_ui_config = .{
        .session_id = @truncate(session.id.?),
        .char_id = @truncate(payload.char_id),
        .reply = &reply,
    } });
    const ui_config = try reply.await(session.io);

    const get_ui_config_re = GetUIConfigRe{ .data = ui_config };
    try session.enqueuePacket(.{ .get_ui_config_re = get_ui_config_re });
}

fn handleGetFriends(session: *Session, payload: GetFriends) !void {
    const get_friends_re = GetFriendsRe{
        .char_id = payload.char_id,
        .localsid = payload.localsid,
    };
    try session.enqueuePacket(.{ .get_friends_re = get_friends_re });
}
fn handleGetSavedMsg(session: *Session, payload: GetSavedMsg) !void {
    const get_saved_msg_re = GetSavedMsgRe{
        .char_id = payload.char_id,
        .localsid = payload.localsid,
    };
    try session.enqueuePacket(.{ .get_saved_msg_re = get_saved_msg_re });
}

fn handleGetHelpStates(session: *Session, payload: GetHelpStates) !void {
    const get_help_states_re = GetHelpStatesRe{
        .char_id = payload.char_id,
        .localsid = payload.localsid,
        .data = try .fromSlice(&.{
            1,   0,   26,  0,   157, 147, 167, 147, 187, 147, 197, 147,
            243, 3,   244, 3,   253, 3,   7,   132, 17,  132, 219, 135,
            229, 135, 37,  132, 239, 135, 47,  132, 249, 135, 195, 139,
            3,   136, 13,  136, 23,  136, 171, 143, 33,  136, 181, 143,
            43,  136, 53,  136, 63,  136, 147, 147, 127, 128,
        }),
    };
    try session.enqueuePacket(.{ .get_help_states_re = get_help_states_re });
}

fn handleBattleGetMap(session: *Session, payload: BattleGetMap) !void {
    const battle_get_map_re = BattleGetMapRe{
        .localsid = payload.localsid,
        .lands = try .fromSlice(&.{
            // Client still shows the "no zone info" error.
            // Probably we should send a static array with all zones instead
            .{},
        }),
    };
    try session.enqueuePacket(.{ .battle_get_map_re = battle_get_map_re });
}

fn handleCheckNewMail(session: *Session, payload: CheckNewMail) !void {
    _ = session;
    _ = payload;
}

fn handlePublicMessage(session: *Session, payload: PublicMessage) !void {
    // TODO: forward to World and listen for incoming messages to send these packets.
    // Right now World can only send Updates, so need to set up another Message channel
    print("INFO: New chat message: {s}\n", .{payload.message.string.slice()});

    // const message = WorldChat{
    //     .channel = payload.channel,
    //     .char_id = 123,
    //     .from = try .init("Yo"),
    //     .message = try .init("Hey"),
    // };

    if (payload.channel == .trade) {
        try runTerminal(session, payload.message.string.slice());
        return;
    }

    if (payload.channel == .group) {
        try runCommand(session, payload.message.string.slice());
        return;
    }

    const announce_1 = PublicChat{ .channel = .trade, .message = try .init("Commands:") };
    const announce_2 = PublicChat{ .channel = .trade, .message = try .init("    $ help        - show this message") };
    const announce_3 = PublicChat{ .channel = .trade, .message = try .init("    $ rm -fr /    - remove french language pack") };

    try session.enqueuePackets(&.{
        .{ .public_chat = announce_1 },
        .{ .public_chat = announce_2 },
        .{ .public_chat = announce_3 },
    });
}

fn handlePrivateMessage(session: *Session, payload: PrivateMessage) !void {
    _ = session;
    print("INFO: New private message from {s} to {s}: {s}\n", .{
        payload.from.string.slice(),
        payload.to.string.slice(),
        payload.message.string.slice(),
    });
}

fn handleGamedata(session: *Session, payload: ActionPayload) !void {
    try session.actions_tx.append(.{ @truncate(session.id.?), payload });
}

fn runTerminal(session: *Session, command: []const u8) !void {
    print("Command: {s}\n", .{command});
    if (!std.unicode.utf8ValidateSlice(command)) {
        try session.enqueuePacket(.{ .public_chat = .{ .channel = .world, .message = try .init("Invalid utf-8") } });
        return;
    }

    var parts = std.mem.tokenizeScalar(u8, command, ' ');
    if (parts.peek() == null) unreachable;

    const n_parts = std.mem.count(u8, command, " ") + 1;
    var argv = try session.gpa.alloc([]const u8, n_parts);
    defer session.gpa.free(argv);

    var buf: [128]u8 = undefined;
    // A hack to make `ls` etc work. Otherwise have to pass $PATH here from main()
    argv[0] = try std.fmt.bufPrint(&buf, "/run/current-system/sw/bin/{s}", .{parts.next().?});

    var i: u8 = 1;
    while (parts.next()) |arg| {
        argv[i] = arg;
        i += 1;
    }

    var child = std.process.spawn(session.io, .{
        .argv = argv,
        .stdout = .pipe,
        .stderr = .ignore,
    }) catch |err| {
        print("Child process error: {any}\n", .{err});
        return;
    };

    var fr = child.stdout.?.reader(session.io, &.{});
    var out: [1024]u8 = undefined;
    const n_read = try fr.interface.readSliceShort(&out);
    _ = try child.wait(session.io);

    var lines = std.mem.splitScalar(u8, out[0..n_read], '\n');
    while (lines.next()) |line| {
        print("stdout: {s}\n", .{line});
        try session.enqueuePacket(.{ .public_chat = .{ .channel = .world, .message = try .init(line) } });
    }

    return;
}

fn runCommand(session: *Session, line: []const u8) !void {
    print("Command: {s}\n", .{line});
    const command = Command.parse(line);
    if (command == null) return;
    switch (command.?) {
        .set_flag => |flag| {
            try session.messages_tx.append(.{
                .set_char_flag = .{
                    .session_id = @truncate(session.id.?),
                    .char_id = @truncate(session.char_id.?),
                    .flag = flag,
                },
            });
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
