const std = @import("std");
const print = std.debug.print;

const codec = @import("../../protocol/codec.zig");
const packets = @import("../../protocol/packets.zig");
const types = @import("../../protocol/types.zig");
const events = @import("../../events/events.zig");
const BoundedArray = @import("../../utils/utils.zig").BoundedArray;
const Session = @import("../session.zig").Session;

const Reply = events.Reply;
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
    const characters = try session.db.getCharactersByAccountId(payload.account_id);
    var role_info_list: BoundedArray(RoleInfo, 8) = .{};
    for (characters.slice()) |char| {
        const items = try session.db.getItemsByCharId(char.id);
        print("ITEMS: {any}\n", .{items.slice()});
        const role_info = try RoleInfo.from(char, items.slice());
        try role_info_list.append(role_info);
    }

    const role_list_re = RoleListRe{ .result = 0, .next_slot = 0xFFFFFFFF, .account_id = session.account_id.?, .session_id = session.id.?, .characters = role_info_list };

    try session.enqueuePacket(.{ .role_list_re = role_list_re });
}

fn handleSelectRole(session: *Session, payload: SelectRole) !void {
    session.char_id = payload.char_id;
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
