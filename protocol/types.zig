// Structs in the wire format that are not packets themselves

const std = @import("std");

const utils = @import("utils.zig");
const codec = @import("codec.zig");
const Vec3 = @import("../world/utils.zig").Vec3;
const character = @import("../world/character.zig");

const EndianTable = utils.EndianTable;
const UTF16String = codec.UTF16String;
const copyMatchingFields = utils.copyMatchingFields;

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
    custom_data: []u8,
    equipment: []character.EquipmentItem,
    is_active: bool,
    delete_time: u32,
    create_time: u32,
    lastlogin_time: u32,
    position: Vec3,
    world_id: u32,
    custom_status: []u8,
    character_mode: []u8,
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

    pub fn from(char: character.Character) RoleInfo {
        return copyMatchingFields(character.Character, RoleInfo, char, .{
            .level = char.level,
            .cultivation = char.cultivation,
            .name = .init(char.name),
        });
    }
};
