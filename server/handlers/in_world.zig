const std = @import("std");
const print = std.debug.print;

const Session = @import("../session.zig").Session;
const codec = @import("../../protocol/codec.zig");
const packets = @import("../../protocol/packets.zig");
const Action = @import("../../events/events.zig").Action;

const Owned = packets.Owned;
const InPacket = packets.InPacket;
const EnterWorld = packets.EnterWorld;

pub fn handleInWorld(session: *Session, packet: Owned(InPacket)) !void {
    errdefer packet.deinit();
    switch (packet.value) {
        .enter_world => |payload| try handleEnterWorld(session, payload),
        .gamedata => |payload| try handleGamedata(session, payload),
        else => {
            print("ERROR: [InWorld] Unexpected packet {any}\n", .{packet});
            return error.UnexpectedPacket;
        },
    }
}

fn handleEnterWorld(session: *Session, payload: EnterWorld) !void {
    try session.messages_tx.append(.{ .enter_world = .{
        .session_id = @truncate(session.id.?),
        .char_id = @truncate(payload.role_id),
    } });
}

fn handleGamedata(session: *Session, payload: Action) !void {
    try session.actions_tx.append(payload);
}
