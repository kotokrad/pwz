const std = @import("std");
const print = std.debug.print;

const codec = @import("../../protocol/codec.zig");
const packets = @import("../../protocol/packets.zig");
const BoundedArray = @import("../../utils/utils.zig").BoundedArray;
const Session = @import("../session.zig").Session;
const Action = @import("../../protocol/actions.zig").Action;

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
const SendPublicMessage = packets.SendPublicMessage;
const SendPrivateMessage = packets.SendPrivateMessage;
const PublicChat = packets.PublicChat;
const WorldChat = packets.WorldChat;
const PlayerBaseInfo = packets.PlayerBaseInfo;

pub fn handleInWorld(session: *Session, packet: Owned(InPacket)) !void {
    errdefer packet.deinit();
    switch (packet.value) {
        // zig fmt: off
        .enter_world           => |payload| try handleEnterWorld(session, payload),
        .gamedata              => |payload| try handleGamedata(session, payload),
        .get_ui_config         => |payload| try handleGetUIConfig(session, payload),
        .get_friends           => |payload| try handleGetFriends(session, payload),
        .get_saved_msg         => |payload| try handleGetSavedMsg(session, payload),
        .get_help_states       => |payload| try handleGetHelpStates(session, payload),
        .battle_get_map        => |payload| try handleBattleGetMap(session, payload),
        .check_new_mail        => |payload| try handleCheckNewMail(session, payload),
        .send_public_message   => |payload| try handlePublicMessage(session, payload),
        .send_private_message  => |payload| try handlePrivateMessage(session, payload),
        .player_base_info      => |payload| try handlePlayerBaseInfo(session, payload),
        // zig fmt: on

        else => print("WARNING: [InWorld] Unhandled packet:\n    {any}\n", .{packet.value}),
    }
}

fn handleEnterWorld(session: *Session, payload: EnterWorld) !void {
    try session.tx.send(.{ .enter_world = .{
        .session_id = session.id.?,
        .char_id = payload.char_id,
    } });
}

fn handleGetUIConfig(session: *Session, payload: GetUIConfig) !void {
    const ui_config = try session.tx.request(BoundedArray(u8, 512), .get_ui_config, .{
        .session_id = session.id.?,
        .char_id = payload.char_id,
    });

    const get_ui_config_re = GetUIConfigRe{
        .char_id = session.char_id.?,
        .session_id = session.id.?,
        .data = ui_config,
    };
    try session.enqueuePacket(.{ .get_ui_config_re = get_ui_config_re });
}

fn handleGetFriends(session: *Session, payload: GetFriends) !void {
    const get_friends_re = GetFriendsRe{
        .char_id = payload.char_id,
        .session_id = payload.session_id,
    };
    try session.enqueuePacket(.{ .get_friends_re = get_friends_re });
}
fn handleGetSavedMsg(session: *Session, payload: GetSavedMsg) !void {
    const get_saved_msg_re = GetSavedMsgRe{
        .char_id = payload.char_id,
        .session_id = payload.session_id,
    };
    try session.enqueuePacket(.{ .get_saved_msg_re = get_saved_msg_re });
}

fn handleGetHelpStates(session: *Session, payload: GetHelpStates) !void {
    const get_help_states_re = GetHelpStatesRe{
        .char_id = payload.char_id,
        .session_id = payload.session_id,
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
        .session_id = payload.session_id,
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

fn handlePublicMessage(session: *Session, payload: SendPublicMessage) !void {
    // TODO: forward to World and listen for incoming messages to send these packets.
    // Right now World can only send Updates, so need to set up another Message channel
    try session.tx.send(.{ .public_message = .{
        .session_id = session.id.?,
        .channel = payload.channel,
        .from_id = payload.from_id,
        .text = payload.message,
    } });
}

fn handlePrivateMessage(session: *Session, payload: SendPrivateMessage) !void {
    try session.tx.send(.{ .private_message = .{
        .from_id = payload.from_id,
        .from_name = payload.from_name,
        .to_id = payload.to_id,
        .to_name = payload.to_name,
        .text = payload.message,
    } });
}

fn handlePlayerBaseInfo(session: *Session, payload: PlayerBaseInfo) !void {
}

fn handleGamedata(session: *Session, payload: Action) !void {
    try session.tx.send(.{ .action = .{
        .session_id = session.id.?,
        .char_id = session.char_id.?,
        .action = payload,
    } });
}
