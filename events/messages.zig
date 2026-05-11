const std = @import("std");
const Io = std.Io;

const FixedArray = @import("../protocol/utils.zig").FixedArray;
const channel = @import("channel.zig");
const Update = @import("updates.zig").Update;
const Account = @import("../world/world.zig").Account;
const CharIds = @import("../world/world.zig").CharIds;
const RoleInfo = @import("../protocol/types.zig").RoleInfo;

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

// `Message` to the game loop from a session thread.
// Session may expect a reply and will block until it's received.
pub const Message = union(enum) {
    // zig fmt: off
    auth:          struct { username: []const u8, reply: *Reply(?Account) },
    init_session:  struct { channel: *Channel(Update), reply: *Reply(u8) },
    char_list:     struct { ids: CharIds, reply: *Reply(FixedArray(RoleInfo, 8)) },
    enter_world:   struct { session_id: u8, char_id: u8 },
    get_ui_config: struct { session_id: u8, char_id: u8, reply: *Reply(FixedArray(u8, 512)) },
    // zig fmt: on

    fn deinit(self: *Message) void {
        switch (self) {
            inline else => |payload| {
                if (@hasDecl(@TypeOf(payload), "deinit")) payload.deinit();
            },
        }
    }
};
