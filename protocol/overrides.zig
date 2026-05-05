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

pub const Vec3 = struct {
    pub fn write(self: domain.Vec3, writer: *Writer, arena: std.mem.Allocator) !void {
        _ = arena;
        try writer.writeInt(u32, @bitCast(self.x * 16777216.0), .little);
        try writer.writeInt(u32, @bitCast(self.z * 16777216.0), .little);
        try writer.writeInt(u32, @bitCast(self.y * 16777216.0), .little);
    }
    pub fn read(reader: *Reader, arena: std.mem.Allocator) !domain.Vec3 {
        if (reader.buffered().len < 12) return error.EndOfStream;
        const x: f32 = @as(f32, @bitCast(reader.takeInt(u32, .little))) / 16777216.0;
        const z: f32 = @as(f32, @bitCast(reader.takeInt(u32, .little))) / 16777216.0;
        const y: f32 = @as(f32, @bitCast(reader.takeInt(u32, .little))) / 16777216.0;
        const result = arena.create(domain.Vec3);
        result.* = domain.Vec3{ .x = x, .y = y, .z = z };
        return result;
    }
};

// pub const Character = struct {
//     pub const endian: EndianTable(domain.Character, .little) = .{
//         .level = .big,
//         .cultivation = .big,
//         .world_id = .big,
//         .referrer_id = .big,
//         .cash_add = .big,
//     };
// };

pub const EquipmentItem = struct {
    pub const endian: EndianTable(domain.EquipmentItem, .big) = .{};
};
