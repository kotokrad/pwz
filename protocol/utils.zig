const std = @import("std");

pub fn shortTypeName(comptime T: type) []const u8 {
    const full = @typeName(T);
    return if (std.mem.lastIndexOfScalar(u8, full, '.')) |i| full[i + 1 ..] else full;
}

pub fn getEndianFor(comptime T: type, comptime name: []const u8) ?std.builtin.Endian {
    const endian_table = if (@hasDecl(T, "endian")) @field(T, "endian") else return null;
    const endian = if (@hasField(@TypeOf(endian_table), name)) @field(endian_table, name) else return null;
    return endian;
}

pub fn EndianTable(comptime T: type, default: std.builtin.Endian) type {
    const info = @typeInfo(T);

    comptime var len = 0;
    inline for (info.@"struct".fields) |f| {
        switch (@typeInfo(f.type)) {
            .int => len = len + 1,
            else => {},
        }
    }

    comptime var field_names: [len][]const u8 = undefined;
    comptime var field_types: [len]type = undefined;
    comptime var field_attrs: [len]std.builtin.Type.StructField.Attributes = undefined;

    comptime var i = 0;
    inline for (info.@"struct".fields) |f| {
        switch (@typeInfo(f.type)) {
            .int => {
                field_names[i] = f.name;
                field_types[i] = std.builtin.Endian;
                field_attrs[i] = .{
                    .@"comptime" = false,
                    .@"align" = f.alignment,
                    .default_value_ptr = &default,
                };
                i = i + 1;
            },
            else => {},
        }
    }

    return @Struct(.auto, null, &field_names, &field_types, &field_attrs);
}
