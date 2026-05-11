// Structs in the wire format that are not packets themselves

const std = @import("std");

const utils = @import("utils.zig");
const codec = @import("codec.zig");
const Vec3 = @import("../world/utils.zig").Vec3;
const character = @import("../world/character.zig");

const FixedArray = utils.FixedArray;
const String = utils.String;
const EndianTable = utils.EndianTable;
const UTF16String = codec.UTF16String;
const copyShallow = utils.copyShallow;
const copyDeep = utils.copyDeep;

pub const ErrorCode = enum(u8) {
    // zig fmt: off
    invalid_credentials   = 0x03,
    already_in_game       = 0x10,
    maintenance           = 0x25,
    server_offline        = 0x28,
    account_not_activated = 0x83,
    // zig fmt: on
};

pub const ServerFlags = packed struct(u16) {
    unk0: u1 = 0,
    is_money_bonus: bool = false,
    is_drop_bonus: bool = false,
    is_spirit_bonus: bool = false,
    unk1: u3 = 0,
    is_pvp: bool = false,
    unk2: u8 = 0,
};

pub const ChallengeData = struct {
    server_load: u8,
    unk1: u16 = 0,
    flags: ServerFlags,
    unk2: u32 = 0,
    random_bytes: [8]u8,
};

pub const RoleInfo = struct {
    char_id: u32,
    gender: u8,
    race: u8,
    class: u8,
    level: u32,
    cultivation: u32,
    name: UTF16String,
    custom_data: FixedArray(u8, 256),
    equipment: FixedArray(character.EquipmentItem, 22),
    is_active: bool,
    delete_time: u32,
    create_time: u32,
    lastlogin_time: u32,
    position: Vec3,
    world_id: u32,
    custom_status: FixedArray(u8, 32),
    character_mode: FixedArray(u8, 8),
    referrer_id: u32,
    cash_add: u32,

    pub const endian: EndianTable(@This(), .little) = .{
        .level = .big,
        .cultivation = .big,
        .delete_time = .big,
        .create_time = .big,
        .lastlogin_time = .big,
        .world_id = .big,
        .referrer_id = .big,
        .cash_add = .big,
    };

    pub fn from(char: character.Character) !RoleInfo {
        return try copyDeep(character.Character, RoleInfo, char, .{
            .char_id = char.char_id,
            .level = char.level,
            .cultivation = char.cultivation,
            .name = .fromFixedString(char.name),
            .world_id = 1,
            .custom_status = try .fromSlice(&.{}),
            .character_mode = try .fromSlice(&.{ 1, 0, 0, 0, 1, 0, 0, 0 }),
            .referrer_id = 0xFFFFFFFF,
            .cash_add = 362_000,
        });
    }
};

pub const BattleMapLand = struct {
    id: u8 = 1,
    level: u8 = 1,
    color: u8 = 0,
    owner: u32 = 0,
    attacker: u32 = 0,
    battletime: u32 = 0,
    deposit: u32 = 0,
    maxbonus: u32 = 0,
};
