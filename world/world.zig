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

const DB = struct {
    accounts: std.StringHashMap(Account),
    characters: [256]Character,

    fn init(gpa: std.mem.Allocator) DB {
        return .{
            .accounts = .init(gpa),
            .characters = undefined,
        };
    }

    pub fn seed_with_test_data(self: *DB, gpa: std.mem.Allocator) !void {
        var char_ids: [8]u8 = undefined;
        char_ids[0] = 123;
        const test_account: Account = .{
            .id = 35,
            .hash = .{ 41, 24, 244, 86, 253, 162, 124, 112, 60, 169, 226, 90, 244, 110, 139, 36 }, // qwer:qwer
            .chars = .{ .chars = char_ids, .len = 1 },
        };
        try self.accounts.put("qwer", test_account);

        self.characters[123] = try character.getExampleChar(gpa);
    }

    fn getCharacterList(self: *DB, ids: CharIds) CharList {
        var char_list: CharList = .{
            .chars = undefined,
            .len = ids.len,
        };
        for (ids.chars[0..ids.len], 0..) |id, i| {
            char_list.chars[i] = self.characters[id];
        }
        return char_list;
    }

    pub fn deinit(self: *DB) void {
        self.accounts.deinit();
    }
};

const World = struct {
    players_online: [256]bool,
    sessions: [256]*Channel(Update),
    next_session_id: u8,

    fn registerSession(self: *World, updates_tx: *Channel(Update)) u8 {
        const id = self.next_session_id;
        self.sessions[id] = updates_tx;
        self.next_session_id += 1;
        return id;
    }
};

pub fn start(io: std.Io, gpa: std.mem.Allocator, actions_rx: *Channel(Action)) void {
    loop(io, gpa, actions_rx) catch |err| print("ERROR: World process crashed with error: {}", .{err});
}

pub fn loop(io: std.Io, gpa: std.mem.Allocator, actions_rx: *Channel(Action)) !void {
    var world: World = .{
        .players_online = undefined,
        .sessions = undefined,
        .next_session_id = 0,
    };

    // Here for now
    var db: DB = .init(gpa);
    defer db.deinit();
    try db.seed_with_test_data(gpa);

    while (true) {
        for (try actions_rx.drain()) |action| {
            switch (action) {
                .auth => |payload| payload.reply.set(io, db.accounts.get(payload.username)),
                .init_session => |payload| {
                    const session_id = world.registerSession(payload.channel);
                    payload.reply.set(io, session_id);
                },
                .char_list => |payload| {
                    var arena: std.heap.ArenaAllocator = .init(gpa);
                    errdefer arena.deinit();
                    const allocator = arena.allocator();
                    const char_list = db.getCharacterList(payload.ids);
                    const result = try allocator.alloc(types.RoleInfo, payload.ids.len);
                    for (char_list.chars[0..char_list.len], 0..) |char, i| {
                        result[i] = try types.RoleInfo.from(allocator, char);
                    }
                    payload.reply.set(io, .{ .arena = arena, .value = result });
                },
                .enter_world => |payload| {
                    world.players_online[payload.char_id] = true;
                },
                .move => |payload| {
                    _ = payload;
                },
            }
        }

        try io.sleep(.fromMilliseconds(50), .real);
    }
}
