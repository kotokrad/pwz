const std = @import("std");
const print = std.debug.print;

const BoundedArray = @import("../utils/utils.zig").BoundedArray;
const EntityMap = @import("../db/entity.zig").EntityMap;
const DB = @import("../db/db.zig").DB;
const character = @import("../db/types/character.zig");
const types = @import("../protocol/types.zig");
const events = @import("../events/events.zig");
const upd = @import("../events/updates.zig");

const Channel = events.Channel;
const Message = events.Message;
const Action = events.Action;
const Update = events.Update;
const Character = character.Character;
const CharacterId = character.CharacterId;
const Skill = character.Skill;
const Vec3 = types.Vec3;

pub const SessionId = u32;

pub const Session = struct {
    id: SessionId = undefined,
    updates_tx: *Channel(Update),
    char_id: ?CharacterId = null,
};

const World = struct {
    gpa: std.mem.Allocator,
    // There is some kind of weird collision
    // between character id and session id
    sessions: EntityMap(Session, 69),
    next_session_id: u8,

    fn init(gpa: std.mem.Allocator) World {
        return .{
            .gpa = gpa,
            .sessions = .init(gpa),
            .next_session_id = 0,
        };
    }

    pub fn deinit(self: *World) void {
        self.sessions.deinit();
    }

    fn registerSession(self: *World, updates_tx: *Channel(Update)) !SessionId {
        return try self.sessions.create(.{ .updates_tx = updates_tx });
    }
};

pub fn start(
    io: std.Io,
    gpa: std.mem.Allocator,
    messages_rx: *Channel(Message),
    actions_rx: *Channel(Action),
    db: *DB,
) void {
    loop(io, gpa, messages_rx, actions_rx, db) catch |err| print("ERROR: [World] process crashed with error: {}", .{err});
}

pub fn loop(
    io: std.Io,
    gpa: std.mem.Allocator,
    messages_rx: *Channel(Message),
    actions_rx: *Channel(Action),
    db: *DB,
) !void {
    var world: World = .init(gpa);
    defer world.deinit();

    while (true) {
        for (try messages_rx.drain()) |message| {
            switch (message) {
                .init_session => |payload| {
                    const session_id = try world.registerSession(payload.channel);
                    print("Creatied a session {}\n", .{session_id});
                    payload.reply.set(io, session_id);
                },
                .enter_world => |payload| {
                    print("INFO: [World] player is online: {}\n", .{payload.char_id});
                    const session = world.sessions.get(payload.session_id).?;
                    session.char_id = payload.char_id;
                    const ctx = get_message_context(&world, db, payload) catch continue;
                    const updates_tx, const char = ctx;

                    // try updates_tx.?.appendMany(
                    try updates_tx.append(.{ .role_status_info = .from(char.*) });
                    try updates_tx.append(.{ .role_world_info = .from(char.*) });
                    try updates_tx.append(.{ .nearby_players = try .fromSlice(&.{.from(char.*)}) });
                    try updates_tx.append(.{ .server_config_info = .init() });
                    try updates_tx.append(.{ .unknown_010b = .{} });
                    try updates_tx.append(.{ .safety_lock_status = .init() });
                    try updates_tx.append(.{ .enter_pvp_zone = .{} });
                    // });
                },
                .get_ui_config => |payload| {
                    const ctx = get_message_context(&world, db, payload) catch continue;
                    _, const char = ctx;

                    payload.reply.set(io, char.ui_config);
                },
                .set_char_flag => |payload| {
                    const ctx = get_message_context(&world, db, payload) catch continue;
                    const updates_tx, const char = ctx;

                    var updated_info: upd.RoleWorldInfo = .from(char.*);
                    updated_info.setFlag(payload.flag);
                    print("----------------------------------\n", .{});
                    print("{any}\n", .{updated_info.flags});
                    print("{b}\n", .{@as(u32, @bitCast(updated_info.flags)) & 0xFFFF});
                    print("----------------------------------\n", .{});
                    try updates_tx.append(.{ .role_world_info = updated_info });
                },
            }
        }

        for (try actions_rx.drain()) |action_tuple| {
            const session_id, const action = action_tuple;
            const session = world.sessions.get(session_id) orelse {
                print("ERROR: [World] session {} does not exist\n", .{session_id});
                continue;
            };
            const char = db.characters.get(session.char_id.?) orelse {
                print("ERROR: [World] session {}: character {} does not exist\n", .{ session_id, session.char_id.? });
                continue;
            };

            // Safe to unwrap: channel is set at the auth stage
            const updates_tx = session.updates_tx;

            switch (action) {
                .move => {},
                .stop => {},
                .get_base_info => {
                    const skills = try db.getSkillByCharId(char.id);

                    try updates_tx.append(.{ .role_status_info = .from(char.*) });
                    try updates_tx.append(.{ .player_combat_stats = try .init() });
                    try updates_tx.append(.{ .inventory = try .from(.general, &.{}) });
                    try updates_tx.append(.{ .inventory = try .from(.equipment, &.{}) });
                    try updates_tx.append(.{ .inventory = try .from(.fashion, &.{}) });
                    try updates_tx.append(.{ .quest_inventory = .{} });
                    try updates_tx.append(.{ .money = .{ .current = 0, .max = 12774155 } });
                    try updates_tx.append(.{ .skills = try .from(skills.slice()) });
                    try updates_tx.append(.{ .unknown_69 = try .init() });
                },
                .gm_teleport => |payload| {
                    var updated_info: upd.RoleWorldInfo = .from(char.*);
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
                .move_item => {},
                .move_equipment => {},
                .take_off_equipment => {},
            }
        }

        try io.sleep(.fromMilliseconds(50), .awake);
    }
}

const EventCtx = struct { *Channel(Update), *Character };

fn get_message_context(
    world: *World,
    db: *DB,
    payload: anytype,
) !EventCtx {
    const session = world.sessions.get(payload.session_id) orelse return error.SessionNotExists;
    const char = db.characters.get(payload.char_id) orelse return error.CharacterNotExists;
    const updates_tx = session.updates_tx;
    return .{ updates_tx, char };
}
