const std = @import("std");
const print = std.debug.print;

const EntityMap = @import("../db/entity.zig").EntityMap;
const DB = @import("../db/db.zig").DB;
const Channel = @import("../messages/channel.zig").Channel;
const ClientMessage = @import("../messages/messages.zig").ClientMessage;
const ServerMessage = @import("../messages/messages.zig").ServerMessage;
const Action = @import("../protocol/actions.zig").Action;
const utils = @import("../utils/utils.zig");
const character = @import("../db/types/character.zig");
const types = @import("../protocol/types.zig");
const chat = @import("chat.zig");

const c = utils.term.c;
const r = utils.term.r;
const BoundedArray = utils.BoundedArray;
const Vec3 = types.Vec3;
const Character = character.Character;
const CharacterId = character.CharacterId;
const Skill = character.Skill;

pub const SessionId = u32;

pub const Session = struct {
    id: SessionId = undefined,
    tx: *Channel(ServerMessage),
    char_id: ?CharacterId = null,
};

pub const World = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    // There is some kind of weird collision
    // between character id and session id
    sessions: EntityMap(Session, 69),
    next_session_id: u8,

    fn init(io: std.Io, gpa: std.mem.Allocator) World {
        return .{
            .io = io,
            .gpa = gpa,
            .sessions = .init(gpa),
            .next_session_id = 0,
        };
    }

    pub fn deinit(self: *World) void {
        self.sessions.deinit();
    }

    fn registerSession(self: *World, tx: *Channel(ServerMessage)) SessionId {
        const ptr = self.sessions.create(.{ .tx = tx });
        return ptr.id;
    }
};

pub fn start(
    io: std.Io,
    gpa: std.mem.Allocator,
    rx: *Channel(ClientMessage),
    db: *DB,
) void {
    loop(io, gpa, rx, db) catch |err| print("{s}ERROR: [World] process crashed with error: {}{s}\n", .{ c(1), err, r() });
}

pub fn loop(
    io: std.Io,
    gpa: std.mem.Allocator,
    rx: *Channel(ClientMessage),
    db: *DB,
) !void {
    var world: World = .init(io, gpa);
    defer world.deinit();

    while (true) {
        for (try rx.drain()) |message| {
            errdefer print("{s}[ERROR] -- Processing messages{s}\n", .{ c(1), r() });
            switch (message) {
                .get_account => |payload| payload.reply.set(io, db.getAccountByUsername(payload.username)),
                .get_characters => |payload| payload.reply.set(io, db.getCharactersByAccountId(payload.account_id)),
                .get_items => |payload| payload.reply.set(io, db.getItemsByCharId(payload.char_id)),
                .init_session => |payload| {
                    const session_id = world.registerSession(payload.channel);
                    print("INFO: [World] Created a session {}\n", .{session_id});
                    payload.reply.set(io, session_id);
                },
                .enter_world => |payload| {
                    print("INFO: [World] player is online: {}\n", .{payload.char_id});
                    const session = world.sessions.get(payload.session_id) orelse {
                        print("{s}ERROR: [World] enter_world session {} does not exist{s}\n", .{ c(1), payload.session_id, r() });
                        continue;
                    };
                    const char = db.characters.get(payload.char_id) orelse {
                        print("{s}ERROR: [World] enter_world session {}: character {} does not exist{s}\n", .{ c(1), payload.session_id, payload.char_id, r() });
                        continue;
                    };

                    try session.tx.send(.{ .update = .{ .role_status_info = .from(char.*) } });
                    try session.tx.send(.{ .update = .{ .role_world_info = .from(char.*) } });
                    try session.tx.send(.{ .update = .{ .server_config_info = .init() } });
                    try session.tx.send(.{ .update = .{ .unknown_010b = .{} } });
                    try session.tx.send(.{ .update = .{ .unknown_0120 = .{} } });
                    try session.tx.send(.{ .update = .{ .unknown_0105 = .{} } });
                    try session.tx.send(.{ .update = .{ .safety_lock_status = .init() } });
                    try session.tx.send(.{ .update = .{ .enter_pvp_zone = .{} } });
                },
                .get_ui_config => |payload| {
                    const char = db.characters.get(payload.char_id) orelse {
                        print("{s}ERROR: [World] get_ui_config session {}: character {} does not exist{s}\n", .{ c(1), payload.session_id, payload.char_id, r() });
                        continue;
                    };

                    payload.reply.set(io, char.ui_config);
                },
                .set_char_flag => |payload| {
                    _ = payload;
                    // TODO: figure out how to send it as an Update
                    // var updated_info: upd.RoleWorldInfo = .from(char.*);
                    // updated_info.setFlag(payload.flag);
                    // print("----------------------------------\n", .{});
                    // print("{any}\n", .{updated_info.flags});
                    // print("{b}\n", .{@as(u32, @bitCast(updated_info.flags)) & 0xFFFF});
                    // print("----------------------------------\n", .{});
                    // try updates_tx.send(.{ .role_world_info = updated_info });
                },
                },
                .action => |payload| {
                    const session = world.sessions.get(payload.session_id) orelse {
                        print("{s}ERROR: [World] action session {} does not exist{s}\n", .{ c(1), payload.session_id, r() });
                        continue;
                    };
                    const char = db.characters.get(payload.char_id) orelse {
                        print("{s}ERROR: [World] action session {}: character {} does not exist{s}\n", .{ c(1), payload.session_id, payload.char_id, r() });
                        continue;
                    };

                    try handleAction(db, &world, session, char, payload.action);
                },
            }
        }

        try io.sleep(.fromMilliseconds(50), .awake);
    }
}

fn handleAction(db: *DB, world: *World, session: *Session, char: *Character, action: Action) !void {
    errdefer print("{s}ERROR [World] -- handleAction{s}\n", .{ c(1), r() });
    _ = world;
    switch (action) {
        .move => {},
        .stop => {
            // const another_char = db.getCharacter(2).?;
            // try session.tx.send(.{ .send_player_info = another_char.* });
        },
        .get_base_info => {
            const skills = db.getSkillByCharId(char.id).slice();
            const items = db.getItemsByCharId(char.id).slice();

            try session.tx.send(.{ .update = .{ .role_status_info = .from(char.*) } });
            try session.tx.send(.{ .update = .{ .player_combat_stats = try .init() } });
            try session.tx.send(.{ .update = .{ .inventory = try .from(.general, items) } });
            try session.tx.send(.{ .update = .{ .inventory = try .from(.equipment, items) } });
            try session.tx.send(.{ .update = .{ .inventory = try .from(.fashion, items) } });
            try session.tx.send(.{ .update = .{ .quest_inventory = .{} } });
            try session.tx.send(.{ .update = .{ .money = .{ .current = 0, .max = 12774155 } } });
            try session.tx.send(.{ .update = .{ .skills = try .from(skills) } });
            try session.tx.send(.{ .update = .{ .unknown_69 = try .init() } });
        },
        .gm_teleport => |payload| {
            _ = payload;
            // var updated_info: upd.RoleWorldInfo = .from(char.*);
            // updated_info.position = payload.pos;
            // try session.tx.send(.{ .role_world_info = updated_info });

            // This doesn't work because of that 0x43 thing
            // try session.tx.send(.{ .stop = .{
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
