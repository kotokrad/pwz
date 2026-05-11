const std = @import("std");
const print = std.debug.print;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

const utils = @import("utils.zig");
const codec = @import("codec.zig");
const types = @import("types.zig");
const events = @import("../events/events.zig");

const Octets = codec.Octets;
const Seq = codec.Seq;
const UTF16String = codec.UTF16String;
const FixedArray = utils.FixedArray;
const String = utils.String;
const EndianTable = utils.EndianTable;
const Update = events.Update;
const Action = events.Action;
const ActionPayload = events.ActionPayload;

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
    gamedata: ActionPayload        = 0x22,
    keep_alive: KeepAlive          = 0x5A,
    login_request: LoginRequest    = 0x03,
    key_exchange: KeyExchange      = 0x02,
    role_list: RoleList            = 0x52,
    select_role: SelectRole        = 0x46,
    enter_world: EnterWorld        = 0x48,
    get_ui_config: GetUIConfig     = 0x68,
    get_friends: GetFriends        = 0xCE,
    get_saved_msg: GetSavedMsg     = 0xD9,
    get_help_states: GetHelpStates = 0x82,
    battle_get_map: BattleGetMap   = 0x352,
    check_new_mail: CheckNewMail   = 0x1068,
    // zig fmt: on

    pub fn read(reader: *Reader, arena: std.mem.Allocator) !InPacket {
        const opcode = try codec.readCuint(reader);

        // Gamedata packets have format:
        // 0x22|len+cuint_size(len)|len|opcode|data
        if (opcode == 0x22) {
            const payload = try ActionPayload.read(reader, arena);
            return @unionInit(InPacket, "gamedata", payload);
        } else {
            const payload_len = try codec.readCuint(reader);
            // Block until we have enough data
            if (reader.bufferedLen() < payload_len) {
                print("INFO: [Packets] waiting for more data ({}/{})...\n", .{ reader.bufferedLen(), payload_len });
                try reader.fill(payload_len);
            }
            inline for (@typeInfo(std.meta.Tag(InPacket)).@"enum".fields) |field| {
                if (field.value == opcode) {
                    const T = @FieldType(InPacket, field.name);
                    const payload = try codec.deserialize(T, reader, arena);

                    print("0x{X:0>4}: <- {s}\n", .{ opcode, utils.shortTypeName(T) });
                    // print("    {any}\n", .{payload});
                    return @unionInit(InPacket, field.name, payload);
                }
            }

            print("0x{X:0>4}: <- UNKNOWN OPCODE ({X})\n", .{ opcode, reader.buffered() });

            reader.toss(payload_len);
            return error.UnknownOpcode;
        }
    }
};

pub const OutPacket = union(enum(u16)) {
    // zig fmt: off
    container: Container                = 0x00,
    keep_alive: KeepAlive               = 0x5A,
    server_error: ServerError           = 0x05,
    challenge: Challenge                = 0x01,
    key_exchange: KeyExchange           = 0x02,
    online_announce: OnlineAnnounce     = 0x04,
    role_list_re: RoleListRe            = 0x53,
    select_role_re: SelectRoleRe        = 0x47,
    get_ui_config_re: GetUIConfigRe     = 0x69,
    get_friends_re: GetFriendsRe        = 0xCF,
    get_saved_msg_re: GetSavedMsgRe     = 0xDA,
    get_help_states_re: GetHelpStatesRe = 0x83,
    battle_get_map_re: BattleGetMapRe   = 0x353,
    // zig fmt: on

    pub fn write(self: OutPacket, writer: *Writer, scratch: std.mem.Allocator) !void {
        var aw: Writer.Allocating = .init(scratch);
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

                print("0x{X:0>4}: -> {s}\n", .{ opcode, utils.shortTypeName(T) });
                // print("{any}\n", .{variant});
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
    message: String,
};

pub const Challenge = struct {
    data: Octets(types.ChallengeData),
    version: [4]u8,
    auth_method: u8,
    crc_signature: Octets([26]u8),
    exp_multiplier: u8,
};

pub const LoginRequest = struct {
    username: String,
    hash: Octets([16]u8),
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
    // passwd_flag: u8, // NOTE: (1.4.5+) passwd_flag (using old password? Or need to update password?)
    // usbbind: u8, // NOTE: (1.4.5+)
};

pub const RoleList = struct {
    account_id: u32,
    localsid: u32,
    slot: u32,

    pub const endian: EndianTable(@This(), .little) = .{ .localsid = .big };
};

pub const RoleListRe = struct {
    result: u32,
    next_slot: u32,
    account_id: u32,
    session_id: u32,
    characters: FixedArray(types.RoleInfo, 8),
};

pub const SelectRole = struct {
    char_id: u32,
};

pub const SelectRoleRe = struct {
    zeroes: u32 = 0,
    gm_code: [33]u8,
};

pub const EnterWorld = struct {
    role_id: u32,
    provider_link_id: u32,
    locktime: u32,
    timeout: u32,
    settime: u32,
    localsid: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .localsid = .big };
};

pub const GetUIConfig = struct {
    role_id: u32,
    localsid: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .localsid = .big };
};

pub const GetUIConfigRe = struct {
    result: u32 = 0,
    unk1: u32 = 0xf01,
    unk2: u16 = 0x200,
    unk3: u16 = 0xe01,
    // role_id: u32,
    // localsid: u32,
    data: FixedArray(u8, 512),
    pub const endian: EndianTable(@This(), .little) = .{
        .unk1 = .big,
        .unk2 = .big,
        .unk3 = .big,
    };
};

pub const GetFriends = struct {
    role_id: u32,
    localsid: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .localsid = .big };
};

pub const GetFriendsRe = struct {
    role_id: u32,
    empty_array_len1: u8 = 0,
    empty_array_len2: u8 = 0,
    empty_array_len3: u8 = 0,
    localsid: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .role_id = .big };
};

pub const GetSavedMsg = struct {
    role_id: u32,
    localsid: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .localsid = .big };
};

pub const GetSavedMsgRe = struct {
    result: u8 = 0,
    empty_array_len1: u8 = 0,
    role_id: u32,
    localsid: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .role_id = .big };
};

pub const GetHelpStates = struct {
    role_id: u32,
    localsid: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .localsid = .big };
};

pub const GetHelpStatesRe = struct {
    result: u8 = 0,
    role_id: u32,
    localsid: u32,
    data: FixedArray(u8, 128),
    pub const endian: EndianTable(@This(), .little) = .{ .role_id = .big, .localsid = .big };
};

// Client send it every time you walk into another zone
pub const BattleGetMap = struct {
    role_id: u32,
    localsid: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .localsid = .big };
};

pub const BattleGetMapRe = struct {
    result: u8 = 0,
    maxbid: u16 = 2000,
    status: u16 = 1,
    lands: FixedArray(types.BattleMapLand, 1),
    bonus_item_id: u32 = 11208,
    bonus_count1: u32 = 150,
    bonus_count2: u32 = 200,
    bonus_count3: u32 = 300,
    localsid: u32,
};

pub const CheckNewMail = struct {
    role_id: u32,
    localsid: u32,
    pub const endian: EndianTable(@This(), .little) = .{ .localsid = .big };
};

pub const SendChatMessage = struct {};
