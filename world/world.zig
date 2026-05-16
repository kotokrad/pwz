const std = @import("std");
const print = std.debug.print;

const FixedArray = @import("../protocol/utils.zig").FixedArray;
const character = @import("character.zig");
const types = @import("../protocol/types.zig");
const events = @import("../events/events.zig");
const upd = @import("../events/updates.zig");

const Channel = events.Channel;
const Message = events.Message;
const Action = events.Action;
const Update = events.Update;
const Character = character.Character;
const Vec3 = types.Vec3;

pub const CharIds = struct {
    chars: [8]u8,
    len: u4,
};

pub const Account = struct {
    id: u8,
    hash: [16]u8,
    chars: CharIds,
};

pub const Session = struct {
    updates_tx: *Channel(Update),
    char_id: ?u8 = null,
};

const World = struct {
    gpa: std.mem.Allocator,
    accounts: std.StringHashMap(Account),
    characters: [256]?Character,
    players_online: [256]bool,
    sessions: [256]?Session,
    next_session_id: u8,

    fn init(gpa: std.mem.Allocator) World {
        return .{
            .gpa = gpa,
            .accounts = .init(gpa),
            .characters = @splat(null),
            .players_online = @splat(false),
            .sessions = @splat(null),
            .next_session_id = 0,
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
            .hash = .{ 186, 117, 211, 48, 160, 7, 17, 59, 47, 33, 1, 52, 234, 181, 167, 97 }, // qwer:qwer

            .chars = .{ .chars = char_ids, .len = 1 },
        };
        try self.accounts.put("qwer", test_account);
        self.characters[123] = try character.getExampleChar();
    }

    fn registerSession(self: *World, updates_tx: *Channel(Update)) u8 {
        const id = self.next_session_id;
        self.sessions[id] = .{ .updates_tx = updates_tx };
        self.next_session_id += 1;
        return id;
    }

    fn getRoleInfoList(self: World, ids: CharIds) !FixedArray(types.RoleInfo, 8) {
        var list: FixedArray(types.RoleInfo, 8) = .{};
        for (ids.chars[0..ids.len]) |id| {
            try list.append(try types.RoleInfo.from(self.characters[id].?));
        }
        return list;
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
                    world.sessions[payload.session_id].?.char_id = payload.char_id;
                    const ctx = get_message_context(&world, payload) catch continue;
                    const updates_tx, const char = ctx;

                    // try updates_tx.?.appendMany(
                    try updates_tx.append(.{ .role_status_info = .from(char) });
                    try updates_tx.append(.{ .role_world_info = .from(char) });
                    try updates_tx.append(.{ .nearby_players = try .fromSlice(&.{.from(char)}) });
                    try updates_tx.append(.{ .server_config_info = .init() });
                    try updates_tx.append(.{ .unknown_010b = .{} });
                    try updates_tx.append(.{ .safety_lock_status = .init() });
                    try updates_tx.append(.{ .enter_pvp_zone = .{} });
                    // });
                    world.players_online[payload.char_id] = true;
                },
                .get_ui_config => |payload| {
                    const ctx = get_message_context(&world, payload) catch continue;
                    _, const char = ctx;

                    payload.reply.set(io, char.ui_config);
                },
            }
        }

        for (try actions_rx.drain()) |action_tuple| {
            const session_id, const action = action_tuple;
            const session = world.sessions[session_id];
            if (session == null) {
                print("ERROR: [World] session {} does not exist\n", .{session_id});
                continue;
            }
            if (session.?.char_id == null) {
                print("ERROR: [World] session {}: charater id is not set\n", .{session_id});
                continue;
            }
            const char = world.characters[session.?.char_id.?];
            if (char == null) {
                print("ERROR: [World] session {}: charater {} does not exist\n", .{ session_id, session.?.char_id.? });
                continue;
            }

            // Safe to unwrap: channel is set at the auth stage
            const updates_tx = world.sessions[session_id].?.updates_tx;

            switch (action) {
                .move => {},
                .stop => {},
                .get_base_info => {
                    try updates_tx.append(.{ .role_status_info = .from(char.?) });
                    try updates_tx.append(.{ .player_combat_stats = try .init() });
                    try updates_tx.append(.{ .inventory = try .from(.general, char.?) });
                    try updates_tx.append(.{ .inventory = try .from(.equipment, char.?) });
                    try updates_tx.append(.{ .inventory = try .from(.fashion, char.?) });
                    try updates_tx.append(.{ .quest_inventory = .{} });
                    try updates_tx.append(.{ .money = .{ .current = 0, .max = 12774155 } });
                    try updates_tx.append(.{ .skills = try .init(char.?.skills.slice()) });
                    try updates_tx.append(.{ .unknown_69 = try .init() });
                },
                .gm_teleport => |payload| {
                    var updated_info: upd.RoleWorldInfo = .from(char.?);
                    updated_info.position = payload.pos;
                    try updates_tx.append(.{ .role_world_info = updated_info });

                    // This doesn't work because of that 0x43 thing
                    // try updates_tx.append(.{ .stop = .{
                    //     .char_id = char.?.char_id,
                    //     .pos = payload.pos,
                    // } });
                },
                .stop_meditation => {},
                .respawn => {},
                .enter_dungeon => {},
            }
        }

        try io.sleep(.fromMilliseconds(50), .awake);
    }
}

const EventCtx = struct { *Channel(Update), Character };

fn get_message_context(
    world: *const World,
    payload: anytype,
) !EventCtx {
    const session = world.sessions[payload.session_id];
    const char = world.characters[payload.char_id];
    if (session == null) {
        print("ERROR: [World] session {} does not exist\n", .{payload.session_id});
        return error.SessionNotExists;
    }
    if (char == null) {
        print("ERROR: [World] charater {} does not exist\n", .{payload.char_id});
        return error.CharacterNotExists;
    }
    const updates_tx = session.?.updates_tx;
    return .{ updates_tx, char.? };
}
