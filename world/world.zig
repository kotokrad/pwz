const std = @import("std");
const print = std.debug.print;

const character = @import("character.zig");
const utils = @import("utils.zig");
const events = @import("events.zig");
const types = @import("../protocol/types.zig");

const Channel = events.Channel;
const Action = events.Action;
const Update = events.Update;
const Owned = events.Owned;

const Character = character.Character;
const Vec3 = utils.Vec3;

pub const CharIds = struct {
    chars: [8]u8,
    len: u4,
};

pub const CharList = struct {
    chars: [8]Character,
    len: u4,
};

pub const Account = struct {
    id: u8,
    hash: [16]u8,
    chars: CharIds,
};

const Accounts = std.StringHashMap(Account);
const Characters = [256]Character;
const World = struct {
    chars: [256]Character,
    sessions: [256]*Channel(Update),
    next_session_id: u8,

    fn registerSession(self: *World, updates_tx: *Channel(Update)) u8 {
        const id = self.next_session_id;
        self.sessions[id] = updates_tx;
        self.next_session_id += 1;
        return id;
    }

    fn getCharacterList(self: *World, ids: CharIds) CharList {
        var char_list: CharList = .{
            .chars = undefined,
            .len = ids.len,
        };
        for (ids.chars[0..ids.len], 0..) |id, i| {
            char_list.chars[i] = self.chars[id];
        }
        return char_list;
    }
};

pub fn seed_with_test_data(gpa: std.mem.Allocator, accounts: *Accounts, world: *World) !void {
    var char_ids: [8]u8 = undefined;
    char_ids[0] = 123;
    const test_account: Account = .{
        .id = 35,
        .hash = .{ 41, 24, 244, 86, 253, 162, 124, 112, 60, 169, 226, 90, 244, 110, 139, 36 }, // qwer:qwer
        .chars = .{ .chars = char_ids, .len = 1 },
    };
    try accounts.put("qwer", test_account);

    world.chars[123] = try character.getExampleChar(gpa);
}

pub fn start(io: std.Io, gpa: std.mem.Allocator, actions_rx: *Channel(Action)) void {
    loop(io, gpa, actions_rx) catch |err| print("ERROR: World process crashed with error: {}", .{err});
}

pub fn loop(io: std.Io, gpa: std.mem.Allocator, actions_rx: *Channel(Action)) !void {
    var world: World = .{
        .chars = undefined,
        .sessions = undefined,
        .next_session_id = 0,
    };

    // Here for now
    var accounts: Accounts = .init(gpa);
    defer accounts.deinit();

    try seed_with_test_data(gpa, &accounts, &world);

    while (true) {
        for (try actions_rx.drain()) |action| {
            switch (action) {
                .auth => |payload| payload.reply.set(io, accounts.get(payload.username)),
                .init_session => |payload| {
                    const session_id = world.registerSession(payload.channel);
                    payload.reply.set(io, session_id);
                },
                .char_list => |payload| {
                    var arena: std.heap.ArenaAllocator = .init(gpa);
                    errdefer arena.deinit();
                    const allocator = arena.allocator();
                    const char_list = world.getCharacterList(payload.ids);
                    const result = try allocator.alloc(types.RoleInfo, payload.ids.len);
                    for (char_list.chars[0..char_list.len], 0..) |char, i| {
                        result[i] = try types.RoleInfo.from(allocator, char);
                    }
                    payload.reply.set(io, .{ .arena = arena, .value = result });
                },
                .enter_world => |payload| {
                    _ = payload;
                },
                .move => |payload| {
                    _ = payload;
                },
            }
        }

        try io.sleep(.fromMilliseconds(50), .real);
    }
}
