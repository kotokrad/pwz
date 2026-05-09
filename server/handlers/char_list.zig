const std = @import("std");
const print = std.debug.print;

const Session = @import("../session.zig").Session;
const codec = @import("../../protocol/codec.zig");
const packets = @import("../../protocol/packets.zig");
const types = @import("../../protocol/types.zig");
const character = @import("../../world/character.zig");
const events = @import("../../events/events.zig");

const Reply = events.Reply;
const Owned = events.Owned;
const InPacket = packets.InPacket;
const RoleList = packets.RoleList;
const RoleListRe = packets.RoleListRe;
const SelectRole = packets.SelectRole;
const SelectRoleRe = packets.SelectRoleRe;
const RoleInfo = types.RoleInfo;

pub fn handleCharList(session: *Session, packet: InPacket) !void {
    switch (packet) {
        .role_list => |payload| try handleRoleList(session, payload),
        .select_role => |payload| try handleSelectRole(session, payload),
        else => {
            print("ERROR: [CharList] Unexpected packet {any}\n", .{packet});
            return error.UnexpectedPacket;
        },
    }
}

fn handleRoleList(session: *Session, payload: RoleList) !void {
    _ = payload;

    var reply: Reply(Owned([]RoleInfo)) = .{};
    try session.messages_tx.append(.{
        .char_list = .{
            .ids = session.account.?.chars,
            .reply = &reply,
        },
    });

    const char_list = try reply.await(session.io);

    const role_list_re = RoleListRe{
        .result = 0,
        .next_slot = 0xFFFFFFFF,
        .account_id = session.account.?.id,
        .session_id = session.id.?,
        .characters = char_list.value[0..1],
    };

    try session.enqueuePacketAlloc(char_list.arena, .{ .role_list_re = role_list_re });
}

fn handleSelectRole(session: *Session, payload: SelectRole) !void {
    _ = payload;
    const select_role_re = SelectRoleRe{
        .gm_code = .{
            // zig fmt: off
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A,
            0x0B, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0xC8, 0xC9, 0xCA, 0xCB,
            0xCC, 0xCD, 0xCE, 0xCF, 0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6
            // zig fmt: on
        },
    };

    try session.enqueuePacket(.{ .select_role_re = select_role_re });
    session.stage = .in_world;
}
