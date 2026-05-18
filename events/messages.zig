const std = @import("std");
const Io = std.Io;

const BoundedArray = @import("../utils/utils.zig").BoundedArray;
const channel = @import("channel.zig");
const Update = @import("updates.zig").Update;
const Account = @import("../world/world.zig").Account;
const CharIds = @import("../world/world.zig").CharIds;
const RoleInfo = @import("../protocol/types.zig").RoleInfo;
const SessionId = @import("../world/world.zig").SessionId;
const CharacterId = @import("../db/types/character.zig").CharacterId;

const Channel = channel.Channel;

pub fn Reply(comptime T: type) type {
    return struct {
        done: Io.Event = .waiting,
        result: T = undefined,

        const Self = @This();

        pub fn set(self: *Self, io: Io, result: T) void {
            self.result = result;
            self.done.set(io);
        }

        pub fn await(self: *Self, io: Io) !T {
            try self.done.wait(io);
            return self.result;
        }
    };
}

/// `Message` to the game loop from a session thread.
/// Session may expect a reply and will block until it's received.
pub const Message = union(enum) {
    // zig fmt: off
    init_session:  struct { channel: *Channel(Update), reply: *Reply(SessionId) },
    enter_world:   struct { session_id: SessionId, char_id: CharacterId },
    get_ui_config: struct { session_id: SessionId, char_id: CharacterId, reply: *Reply(BoundedArray(u8, 512)) },
    set_char_flag: struct { session_id: SessionId, char_id: CharacterId, flag: u5 },
    // zig fmt: on
};
