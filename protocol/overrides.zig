// Serializing/deserializing overrides for domain types
// To keep them free from protocol details
// - custom read/write methods
// - endianness for specific fields

const std = @import("std");
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

const utils = @import("utils.zig");
const types = @import("types.zig");

const shortTypeName = utils.shortTypeName;
const EndianTable = utils.EndianTable;

const domain = struct {
    pub const Vec3 = @import("../world/utils.zig").Vec3;
    pub const EquipmentItem = @import("../world/character.zig").EquipmentItem;
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
