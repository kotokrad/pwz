const std = @import("std");
const print = std.debug.print;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

const utils = @import("../utils/utils.zig");
const codec = @import("codec.zig");
const types = @import("types.zig");
const Action = @import("actions.zig").Action;
const Update = @import("updates.zig").Update;

const c = utils.term.c;
const r = utils.term.r;
const Octets = codec.Octets;
const Seq = codec.Seq;
const UTF16String = codec.UTF16String;
const Vec = codec.Vec;
const BE = utils.BE;
const BoundedArray = utils.BoundedArray;
const String = utils.String;
const EndianTable = utils.EndianTable;

pub fn Owned(comptime T: type) type {
    return struct {
        arena: ?std.heap.ArenaAllocator = null,
        value: T,

        pub fn deinit(self: @This()) void {
            if (self.arena) |arena| arena.deinit();
        }
    };
}

pub const InPacket = union(enum(u16)) {
    // zig fmt: off
    gamedata: Action                         = 0x22,
    keep_alive: KeepAlive                    = 0x5A,
    login_request: LoginRequest              = 0x03,
    key_exchange: KeyExchange                = 0x02,
    role_list: RoleList                      = 0x52,
    select_role: SelectRole                  = 0x46,
    enter_world: EnterWorld                  = 0x48,
    get_ui_config: GetUIConfig               = 0x68,
    get_friends: GetFriends                  = 0xCE,
    get_saved_msg: GetSavedMsg               = 0xD9,
    get_help_states: GetHelpStates           = 0x82,
    battle_get_map: BattleGetMap             = 0x352,
    player_base_info: PlayerBaseInfo         = 0x5B,
    check_new_mail: CheckNewMail             = 0x1068,
    send_public_message: SendPublicMessage   = 0x4F,
    send_private_message: SendPrivateMessage = 0x60,
    send_faction_message: SendFactionMessage = 0x12C3,
    // zig fmt: on

    pub fn read(reader: *Reader, arena: std.mem.Allocator) !InPacket {
        const raw = try reader.peekGreedy(1);
        print("<- raw: {X}\n", .{raw});
        const opcode = try codec.readCuint(reader);

        // Gamedata packets have format:
        // 0x22|len+cuint_size(len)|len|opcode|data
        if (opcode == 0x22) {
            const payload = try Action.read(reader, arena);
            return @unionInit(InPacket, "gamedata", payload);
        } else {
            const payload_len = try codec.readCuint(reader);
            // Block until we have enough data
            if (reader.bufferedLen() < payload_len) {
                print("INFO: [Packets] waiting for more data ({}/{})...\n", .{ reader.bufferedLen(), payload_len });
                print("opcode = 0x{X:0>4}, len = {}, data: {X}\n", .{ opcode, payload_len, reader.buffered() });
                try reader.fill(payload_len);
            }
            inline for (@typeInfo(std.meta.Tag(InPacket)).@"enum".fields) |field| {
                if (field.value == opcode) {
                    const T = @FieldType(InPacket, field.name);
                    const hex = reader.buffered();
                    const payload = try codec.deserialize(T, reader, arena);

                    print("{s}<- 0x{X:0>4}: {s}{s}\n", .{ c(3), opcode, utils.shortTypeName(T), r() });
                    print("    hex: {X}\n", .{hex});
                    print("    {any}\n", .{payload});
                    if (reader.bufferedLen() > 0) {
                        print("WARNING: [Packets] {any} has some leftover data: {X}\n", .{ T, reader.buffered() });
                    }
                    return @unionInit(InPacket, field.name, payload);
                }
            }

            print("{s}<- 0x{X:0>4}:{s} UNKNOWN OPCODE ({X})\n", .{ c(3), opcode, r(), reader.buffered() });

            reader.toss(payload_len);
            return error.UnknownOpcode;
        }
    }
};

pub const OutPacket = union(enum(u16)) {
    // zig fmt: off
    container: Container                  = 0x00,
    keep_alive: KeepAlive                 = 0x5A,
    server_error: ServerError             = 0x05,
    challenge: Challenge                  = 0x01,
    key_exchange: KeyExchange             = 0x02,
    online_announce: OnlineAnnounce       = 0x04,
    role_list_re: RoleListRe              = 0x53,
    select_role_re: SelectRoleRe          = 0x47,
    get_ui_config_re: GetUIConfigRe       = 0x69,
    get_friends_re: GetFriendsRe          = 0xCF,
    get_saved_msg_re: GetSavedMsgRe       = 0xDA,
    get_help_states_re: GetHelpStatesRe   = 0x83,
    battle_get_map_re: BattleGetMapRe     = 0x353,
    player_base_info_re: PlayerBaseInfoRe = 0x5C,
    public_chat: PublicChat               = 0x50,
    world_chat: WorldChat                 = 0x85,
    // zig fmt: on

    pub fn write(self: OutPacket, writer: *Writer, gpa: std.mem.Allocator) !void {
        var aw: Writer.Allocating = .init(gpa);
        defer aw.deinit();

        switch (self) {
            inline else => |variant, tag| {
                const T = @TypeOf(variant);
                const opcode = @intFromEnum(tag);

                try codec.serialize(T, &aw.writer, variant);
                const payload = aw.written();

                try codec.writeCuint(writer, opcode);
                try codec.writeCuint(writer, payload.len);
                try writer.writeAll(payload);

                if (T != Container) {
                    print("{s}-> 0x{X:0>4}: {s}{s}\n", .{ c(2), opcode, utils.shortTypeName(T), r() });
                    print("{any}\n", .{variant});
                }
            },
        }
    }
};

// Packet types
// ----------------------------------------

pub const Container = Seq(Update, 24);

pub const KeepAlive = struct {
    data: u8,
};

pub const ServerError = struct {
    code: types.ErrorCode,
    message: String(32),
};

pub const Challenge = struct {
    data: Octets(types.ChallengeData),
    version: [4]u8,
    auth_method: u8,
    crc_signature: Octets([26]u8),
    exp_multiplier: u8,
};

pub const LoginRequest = struct {
    username: String(16),
    hash: Octets([16]u8),
    null: u8,
};

pub const KeyExchange = struct {
    key: Octets([16]u8),
    null: u8 = 0,
};

pub const OnlineAnnounce = struct {
    account_id: u32,
    session_id: u32,
    time_remaining: u32,
    zone_id: u8,
    free_time_left: u32,
    free_time_end: u32,
    create_time: u32,
    referrer_flag: u8,
    passwd_flag: u8 = 0, // NOTE: (1.4.4 v60+) (using old password? Or need to update password?)
    usbbind: u8 = 0, // NOTE: (1.4.4 v60+)
    pub const endian: EndianTable(@This(), .little) = .{ .account_id = .big, .session_id = .big };
};

pub const RoleList = struct {
    account_id: u32,
    session_id: u32,
    slot: u32,

    pub const endian: EndianTable(@This(), .little) = .{ .account_id = .big, .session_id = .big };
};

pub const RoleListRe = struct {
    result: u32,
    next_slot: u32,
    account_id: u32,
    session_id: u32,
    characters: BoundedArray(types.RoleInfo, 8),

    pub const endian: EndianTable(@This(), .little) = .{ .account_id = .big, .session_id = .big };
};

pub const SelectRole = struct {
    char_id: u32,
};

pub const SelectRoleRe = struct {
    zeroes: u32 = 0,
    gm_code: [33]u8,
};

pub const EnterWorld = struct {
    char_id: u32,
    provider_link_id: u32,
    locktime: u32,
    timeout: u32,
    settime: u32,
    session_id: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .session_id = .big };
};

pub const GetUIConfig = struct {
    char_id: u32,
    session_id: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .session_id = .big };
};

pub const GetUIConfigRe = struct {
    result: u32 = 0,
    char_id: u32,
    session_id: u32,
    data: BoundedArray(u8, 512),
    pub const endian: EndianTable(@This(), .little) = .{ .session_id = .big };
};

pub const GetFriends = struct {
    char_id: u32,
    session_id: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .session_id = .big };
};

pub const GetFriendsRe = struct {
    char_id: u32,
    empty_array_len1: u8 = 0,
    empty_array_len2: u8 = 0,
    empty_array_len3: u8 = 0,
    session_id: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .char_id = .big };
};

pub const GetSavedMsg = struct {
    char_id: u32,
    session_id: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .session_id = .big };
};

pub const GetSavedMsgRe = struct {
    result: u8 = 0,
    empty_array_len1: u8 = 0,
    char_id: u32,
    session_id: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .char_id = .big };
};

pub const GetHelpStates = struct {
    char_id: u32,
    session_id: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .session_id = .big };
};

pub const GetHelpStatesRe = struct {
    result: u8 = 0,
    char_id: u32,
    session_id: u32,
    data: BoundedArray(u8, 128),
    pub const endian: EndianTable(@This(), .little) = .{ .char_id = .big, .session_id = .big };
};

/// Client sends it every time you walk into another zone
pub const BattleGetMap = struct {
    char_id: u32,
    session_id: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .session_id = .big };
};

pub const BattleGetMapRe = struct {
    result: u8 = 0,
    maxbid: u16 = 2000,
    status: u16 = 1,
    lands: BoundedArray(types.BattleMapLand, 1),
    bonus_item_id: u32 = 11208,
    bonus_count1: u32 = 150,
    bonus_count2: u32 = 200,
    bonus_count3: u32 = 300,
    session_id: u32,
};

pub const PlayerBaseInfo = struct {
    char_id: u32,
    unk_random: u32, // 2242601C, 23CCC09C
    id_list: Vec(BE(u32), 10),
};

pub const PlayerBaseInfoRe = struct {
    result: u32 = 0,
    char_id: u32,
    session_id: u32,
    player: types.RoleBase,
};

pub const CheckNewMail = struct {
    char_id: u32,
    session_id: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .session_id = .big };
};

/// Send public message
///
/// TODO: implement emoji packs:
/// 00E0 3C00 3000 3E00 3C00 5700 3E00 3C00 3000 3A00 3000 3E00 - default pack 🙂
/// 00E0 3C00 3000 3E00 3C00 5700 3E00 3C00 3000 3A00 3100 3E00 - default pack 😁
pub const SendPublicMessage = struct {
    channel: types.ChatChannel,
    unk1: u8,
    from_id: u32,
    unk2: u32,
    message: UTF16String(128),
};

/// Send private message
/// Somewhere it might have a flag saying that
/// the recepient is in the friend list.
/// Message to a friend is pink instead of blue
/// so the client checks it locally
///
/// `unk2` might be a `to_id` if you message by clicking on someone
/// instead of entering the name manually? but why?
pub const SendPrivateMessage = struct {
    unk1: u16, // 00E2
    from_name: UTF16String(16),
    from_id: u32,
    to_name: UTF16String(16),
    to_id: u32 = 0, // maybe
    message: UTF16String(128),
};

/// Send message to the faction chat
pub const SendFactionMessage = struct {
    unk1: u16 = 0,
    from_id: u32,
    message: UTF16String(128),
    unk2: u32 = 0,
};

/// Receive public chat message
///
/// Not sure how it is different from `WorldChat`.
/// If `char_id = 0`, the name is not shown
/// With other `char_id`s, message is just not visible
/// TODO: test it more
pub const PublicChat = struct {
    channel: types.ChatChannel,
    null: u8 = 0,
    from_id: u32 = 0, // TODO: test if it's really `from` id
    message: UTF16String(128),
    unk1: u32 = 0,
    unk2: u8 = 0,
};

/// Receive World chat message
///
/// Can be used for a normal chat
/// with the character name specified in `from`
/// If `char_id = 0`, the name is not shown
pub const WorldChat = struct {
    channel: types.ChatChannel,
    null: u8 = 0,
    from_id: u32 = 0,
    from_name: UTF16String(16),
    message: UTF16String(128),
    unk1: u32 = 0,
    unk2: u8 = 0,
};
