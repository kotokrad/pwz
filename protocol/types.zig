// Structs in the wire format that are not packets themselves

const std = @import("std");

const utils = @import("../utils/utils.zig");
const codec = @import("codec.zig");
const character = @import("../db/types/character.zig");
const inventory = @import("../db/types/inventory.zig");

const UTF16String = codec.UTF16String;
const BoundedArray = utils.BoundedArray;
const String = utils.String;
const EndianTable = utils.EndianTable;
const copyShallow = utils.copyShallow;
const copyDeep = utils.copyDeep;

const Item = inventory.Item;

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn write(self: Vec3, writer: *std.Io.Writer) !void {
        try writer.writeInt(u32, @bitCast((self.x - 400) * 10), .little);
        try writer.writeInt(u32, @bitCast(self.z * 10), .little);
        try writer.writeInt(u32, @bitCast((self.y - 550) * 10), .little);
    }

    pub fn read(reader: *std.Io.Reader, arena: std.mem.Allocator) !Vec3 {
        _ = arena;
        const x = @as(f32, @bitCast(try reader.takeInt(u32, .little))) / 10 + 400;
        const z = @as(f32, @bitCast(try reader.takeInt(u32, .little))) / 10;
        const y = @as(f32, @bitCast(try reader.takeInt(u32, .little))) / 10 + 550;
        return .{ .x = x, .y = y, .z = z };
    }
};

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

pub const Equipment = struct {
    items: BoundedArray(EquipmentItem, Item.MAX_EQUIPMENT_ITEMS),

    pub fn fromItems(items: []const Item) !Equipment {
        var buf: [29]EquipmentItem = undefined;
        var result: std.ArrayList(EquipmentItem) = .initBuffer(&buf);
        for (items) |item| if (item.inventory_type == .equipment) {
            try result.appendBounded(.from(item));
        };
        return .{ .items = try .fromSlice(result.items) };
    }
};

pub const EquipmentItem = struct {
    item_id: u32,
    slot: inventory.EquipmentSlot,
    count: u32,
    max_count: u32,
    data: BoundedArray(u8, 256),
    proc_type: u32,
    expire_date: u32,
    guid1: u32,
    guid2: u32,
    mask: u32,

    pub const endian: EndianTable(@This(), .big) = .{};

    pub fn from(item: Item) EquipmentItem {
        return copyShallow(Item, EquipmentItem, item, .{
            .slot = @enumFromInt(item.slot),
        });
    }
};

pub const RoleInfo = struct {
    id: u32,
    gender: u8,
    race: u8,
    class: u8,
    level: u32,
    cultivation: u32,
    name: UTF16String(16),
    custom_data: BoundedArray(u8, 256),
    equipment: Equipment,
    is_active: bool,
    delete_time: u32,
    create_time: u32,
    lastlogin_time: u32,
    position: Vec3,
    world_id: u32,
    custom_status: BoundedArray(u8, 32),
    character_mode: BoundedArray(u8, 8),
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

    pub fn from(char: character.Character, items: []const Item) !RoleInfo {
        return try copyDeep(character.Character, RoleInfo, char, .{
            .level = char.level,
            .cultivation = char.cultivation,
            .name = .fromString(char.name),
            .equipment = try .fromItems(items),
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

pub const ChatChannel = enum(u8) {
    // zig fmt: off
    local   = 0,
    world   = 1,
    group   = 2,
    faction = 3,
    unk     = 4, // "Emotion"? wth
    trade   = 7,
    gm      = 9,
    horn    = 12,
    // zig fmt: on
};
