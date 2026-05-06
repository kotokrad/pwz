const std = @import("std");
const Io = std.Io;
const ArrayList = std.ArrayList;

const Vec3 = @import("utils.zig").Vec3;
const Character = @import("character.zig").Character;
const Account = @import("world.zig").Account;
const CharIds = @import("world.zig").CharIds;

// Just use this for now
const RoleInfo = @import("../protocol/types.zig").RoleInfo;

pub fn Owned(comptime T: type) type {
    return struct {
        arena: std.heap.ArenaAllocator,
        value: T,

        pub fn deinit(self: *@This()) void {
            self.arena.deinit();
        }
    };
}

pub fn Channel(comptime T: type) type {
    return struct {
        mutex: Io.Mutex,
        front: ArrayList(T),
        back: ArrayList(T),
        io: Io,

        const Self = @This();
        pub fn append(self: *Self, item: T) !void {
            try self.mutex.lock(self.io);
            defer self.mutex.unlock(self.io);
            try self.back.appendBounded(item);
        }

        pub fn drain(self: *Self) ![]T {
            try self.mutex.lock(self.io);
            defer self.mutex.unlock(self.io);
            std.mem.swap(ArrayList(T), &self.back, &self.front);
            self.back.clearRetainingCapacity();
            return self.front.items;
        }
    };
}

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

pub const Action = union(enum) {
    // zig fmt: off
    auth:         struct { username: []const u8, reply: *Reply(?Account) },
    init_session: struct { channel: *Channel(Update), reply: *Reply(u8) },
    char_list:    struct { ids: CharIds, reply: *Reply(Owned([]RoleInfo)) },
    enter_world:  struct { char_id: u8 },
    move:         struct { char_id: u8, pos: Vec3 },
    // zig fmt: on

    fn deinit(self: *Action) void {
        switch (self) {
            inline else => |payload| {
                if (@hasDecl(@TypeOf(payload), "deinit")) payload.deinit();
            },
        }
    }
};

pub const Update = union(enum) {
    // zig fmt: off
    move: struct { pos: Vec3 },
    // zig fmt: on
};
