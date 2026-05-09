const std = @import("std");
const print = std.debug.print;

const utils = @import("utils.zig");
const character = @import("character.zig");
const types = @import("../protocol/types.zig");
const events = @import("../events/events.zig");
const upd = @import("../events/updates.zig");

const Channel = events.Channel;
const Owned = events.Owned;
const Message = events.Message;
const Action = events.Action;
const Update = events.Update;
const Character = character.Character;
const Vec3 = utils.Vec3;

pub const CharIds = struct {
    chars: [8]u8,
    len: u4,
};

pub const Account = struct {
    id: u8,
    hash: [16]u8,
    chars: CharIds,
};

const World = struct {
    gpa: std.mem.Allocator,
    accounts: std.StringHashMap(Account),
    characters: [256]?Character,
    players_online: [256]bool,
    sessions: [256]?*Channel(Update),
    next_session_id: u8,

    fn init(gpa: std.mem.Allocator) World {
        return .{
            .gpa = gpa,
            .accounts = .init(gpa),
            .characters = @splat(null),
            .players_online = @splat(false),
            .sessions = @splat(null),
            .next_session_id = 68,
        };
    }

    pub fn deinit(self: *World) void {
        self.accounts.deinit();
    }

    pub fn seed_with_test_data(self: *World) !void {
        var char_ids: [8]u8 = undefined;
        char_ids[0] = 123;
        const test_account: Account = .{
            .id = 35,
            .hash = .{ 41, 24, 244, 86, 253, 162, 124, 112, 60, 169, 226, 90, 244, 110, 139, 36 }, // qwer:qwer
            .chars = .{ .chars = char_ids, .len = 1 },
        };
        try self.accounts.put("qwer", test_account);
        self.characters[123] = try character.getExampleChar(self.gpa);
    }

    fn registerSession(self: *World, updates_tx: *Channel(Update)) u8 {
        const id = self.next_session_id;
        self.sessions[id] = updates_tx;
        self.next_session_id += 1;
        return id;
    }

    fn getRoleInfoList(self: World, ids: CharIds) !Owned([]types.RoleInfo) {
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        errdefer arena.deinit();
        const allocator = arena.allocator();
        const result = try allocator.alloc(types.RoleInfo, ids.len);
        for (ids.chars[0..ids.len], 0..) |id, i| {
            result[i] = try types.RoleInfo.from(allocator, self.characters[id].?);
        }
        return .{ .arena = arena, .value = result };
    }
};

pub fn start(
    io: std.Io,
    gpa: std.mem.Allocator,
    messages_rx: *Channel(Message),
    actions_rx: *Channel(Action),
) void {
    loop(io, gpa, messages_rx, actions_rx) catch |err| print("ERROR: [World] process crashed with error: {}", .{err});
}

pub fn loop(
    io: std.Io,
    gpa: std.mem.Allocator,
    messages_rx: *Channel(Message),
    actions_rx: *Channel(Action),
) !void {
    var world: World = .init(gpa);
    defer world.deinit();
    try world.seed_with_test_data();

    while (true) {
        for (try messages_rx.drain()) |message| {
            switch (message) {
                .auth => |payload| payload.reply.set(io, world.accounts.get(payload.username)),
                .init_session => |payload| {
                    const session_id = world.registerSession(payload.channel);
                    payload.reply.set(io, session_id);
                },
                .char_list => |payload| {
                    const list = try world.getRoleInfoList(payload.ids);
                    payload.reply.set(io, list);
                },
                .enter_world => |payload| {
                    print("INFO: [World] player is online: {}\n", .{payload.char_id});
                    const char = world.characters[payload.char_id];
                    const update_tx = world.sessions[payload.session_id];
                    if (char == null) {
                        print("ERROR: [World] charater {} does not exist\n", .{payload.char_id});
                        continue;
                    }
                    if (update_tx == null) {
                        print("ERROR: [World] session {} does not exist\n", .{payload.session_id});
                        continue;
                    }

                    // try update_tx.?.appendMany(
                    try update_tx.?.append(.{ .role_status_info = .from(char.?) });
                    try update_tx.?.append(.{ .role_world_info = .from(char.?) });
                    try update_tx.?.append(.{ .nearby_players = &.{} });
                    try update_tx.?.append(.{ .server_config_info = .init() });
                    try update_tx.?.append(.{ .unknown_010b = .{} });
                    try update_tx.?.append(.{ .safety_lock_status = .init() });
                    try update_tx.?.append(.{ .enter_pvp_zone = .{} });
                    // });
                    world.players_online[payload.char_id] = true;
                },
            }
        }

        for (try actions_rx.drain()) |action| {
            switch (action) {
                .move => |payload| {
                    print("[World] Player move: {any}\n", .{payload});
                },
                .stop => |payload| {
                    print("[World] Player stop: {any}\n", .{payload});
                },
                .get_base_info => |payload| {
                    print("[World] GetBaseInfo: {any}\n", .{payload});
                },
            }
        }

        try io.sleep(.fromMilliseconds(50), .awake);
    }
}
