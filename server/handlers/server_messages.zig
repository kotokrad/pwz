const std = @import("std");

const packets = @import("../../protocol/packets.zig");
const character = @import("../../db/types/character.zig");
const types = @import("../../protocol/types.zig");
const Update = @import("../../protocol/updates.zig").Update;
const BoundedArray = @import("../../utils/utils.zig").BoundedArray;
const String = @import("../../utils/utils.zig").String;
const Session = @import("../session.zig").Session;

const Character = character.Character;
const CharacterId = character.CharacterId;

const PlayerBaseInfoRe = packets.PlayerBaseInfoRe;
const ChatChannel = types.ChatChannel;
const RoleBase = types.RoleBase;

pub fn processServerMessages(session: *Session) !void {
    const messages = try session.rx.drain();
    var updates: std.ArrayList(Update) = .empty;
    defer updates.deinit(session.gpa);

    for (messages) |message| {
        switch (message) {
            .update => |packet| try updates.append(session.gpa, packet),
            .public_chat => |payload| try session.enqueuePacket(.{ .public_chat = .{
                .channel = payload.channel,
                .from_id = payload.from_id,
                .message = payload.message,
            } }),
            .world_chat => |payload| try session.enqueuePacket(.{ .world_chat = .{
                .channel = payload.channel,
                .from_id = payload.from_id,
                .from_name = payload.from_name,
                .message = payload.message,
            } }),
            .send_player_info => |payload| try sendPlayerBaseInfo(session, payload),
        }
    }

    // `Update` sub-packets are sent as-is in a `Container`
    if (updates.items.len > 0) {
        try session.enqueuePacket(.{ .container = .{ .list = try .fromSlice(updates.items) } });
    }
}

fn sendPlayerBaseInfo(session: *Session, char: Character) !void {
    const player_base_info: PlayerBaseInfoRe = .{
        .char_id = session.char_id.?,
        .session_id = session.id.?,
        .player = try .from(char),
    };

    try std.Io.sleep(session.io, .fromMilliseconds(500), .awake);
    try session.enqueuePacket(.{ .player_base_info_re = player_base_info });
}
