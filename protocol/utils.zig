const std = @import("std");

pub fn shortTypeName(comptime T: type) []const u8 {
    const full = @typeName(T);
    return if (std.mem.lastIndexOfScalar(u8, full, '.')) |i| full[i + 1 ..] else full;
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

pub fn getEndianFor(comptime T: type, comptime name: []const u8) ?std.builtin.Endian {
    const endian_table = if (@hasDecl(T, "endian")) @field(T, "endian") else return null;
    const endian = if (@hasField(@TypeOf(endian_table), name)) @field(endian_table, name) else return null;
    return endian;
}

// Struct with fields that are present in both F and T but have different types
fn FieldsTypeDiff(comptime F: type, comptime T: type) type {
    const fields = @typeInfo(T).@"struct".fields;

    comptime var len = 0;
    inline for (fields) |f| if (f.type != @FieldType(F, f.name)) {
        len += 1;
    };

    comptime var field_names: [len][]const u8 = undefined;
    comptime var field_types: [len]type = undefined;
    comptime var field_attrs: [len]std.builtin.Type.StructField.Attributes = undefined;

    comptime var i = 0;
    inline for (fields) |f| {
        if (f.type != @FieldType(F, f.name)) {
            field_names[i] = f.name;
            field_types[i] = @FieldType(T, f.name);
            field_attrs[i] = .{
                .@"comptime" = false,
                .@"align" = f.alignment,
                .default_value_ptr = null,
            };
            i = i + 1;
        }
    }

    return @Struct(.auto, null, &field_names, &field_types, &field_attrs);
}

pub fn copyMatchingFields(comptime F: type, comptime T: type, from: F, diff: FieldsTypeDiff(F, T)) T {
    const to_info = @typeInfo(T);
    var result: T = undefined;
    inline for (to_info.@"struct".fields) |f| {
        if (f.type == @FieldType(F, f.name)) {
            @field(result, f.name) = @field(from, f.name);
        } else {
            @field(result, f.name) = @field(diff, f.name);
        }
    }
    return result;
}
