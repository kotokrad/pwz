// Serializing/deserializing overrides for domain types
// To keep them free from protocol details
// - custom read/write methods
// - endianness for specific fields

const std = @import("std");
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

const utils = @import("utils.zig");
const codec = @import("codec.zig");
const types = @import("types.zig");

const FixedArray = utils.FixedArray;
const shortTypeName = utils.shortTypeName;
const copyShallow = utils.copyShallow;
const copyDeepAlloc = utils.copyDeepAlloc;
const EndianTable = utils.EndianTable;
const serialize = codec.serialize;
const writeCuint = codec.writeCuint;

const domain = struct {
    const Vec3 = @import("../world/utils.zig").Vec3;
    const EquipmentItem = @import("../world/character.zig").EquipmentItem;
    const InventoryItem = @import("../world/character.zig").InventoryItem;
};

// Looks up declaration of T in this module and extracts an override from the endian table
pub fn getEndianFor(comptime T: type, comptime name: []const u8) ?std.builtin.Endian {
    const type_overrides = if (@hasDecl(@This(), shortTypeName(T)))
        @field(@This(), shortTypeName(T))
    else
        return null;
    return utils.getEndianFor(type_overrides, name);
}

pub const EquipmentItem = struct {
    pub const endian: EndianTable(domain.EquipmentItem, .big) = .{};
};

pub const InventoryItem = struct {
    slot: u32,
    id: u32,
    expire_date: u32,
    proc_type: u32,
    count: u32,
    guid_or_unk: u16,
    data: codec.OctetsU16LE(FixedArray(u8, 256)),

    pub const endian: EndianTable(domain.InventoryItem, .little) = .{
        .guid_or_unk = .big,
    };

    pub fn from(item: domain.InventoryItem) InventoryItem {
        return copyShallow(domain.InventoryItem, InventoryItem, item, .{
            .data = .init(item.data),
        });
    }
};
