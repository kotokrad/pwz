const std = @import("std");
const codec = @import("codec.zig");

const readCuint = codec.readCuint;
const writeCuint = codec.writeCuint;
const serialize = codec.serialize;
const deserialize = codec.deserialize;

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
    inline for (fields) |f| if (!@hasField(F, f.name) or f.type != @FieldType(F, f.name)) {
        len += 1;
    };

    comptime var field_names: [len][]const u8 = undefined;
    comptime var field_types: [len]type = undefined;
    comptime var field_attrs: [len]std.builtin.Type.StructField.Attributes = undefined;

    comptime var i = 0;
    inline for (fields) |f| {
        if (!@hasField(F, f.name) or f.type != @FieldType(F, f.name)) {
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

pub fn copyShallow(comptime F: type, comptime T: type, from: F, diff: FieldsTypeDiff(F, T)) T {
    const to_info = @typeInfo(T);
    var result: T = undefined;
    inline for (to_info.@"struct".fields) |f| {
        if (@hasField(F, f.name) and f.type == @FieldType(F, f.name)) {
            @field(result, f.name) = @field(from, f.name);
        } else {
            @field(result, f.name) = @field(diff, f.name);
        }
    }
    return result;
}

// Doesn't handle every case, just enough for complex packets
pub fn copyDeep(comptime F: type, comptime T: type, from: F, diff: FieldsTypeDiff(F, T)) !T {
    const to_info = @typeInfo(T);
    var result: T = undefined;
    inline for (to_info.@"struct".fields) |f| {
        if (@hasField(F, f.name) and f.type == @FieldType(F, f.name)) {
            switch (@typeInfo(f.type)) {
                .@"struct" => {
                    @field(result, f.name) = try copyDeep(f.type, f.type, @field(from, f.name), .{});
                },
                else => @field(result, f.name) = @field(from, f.name),
            }
        } else {
            @field(result, f.name) = @field(diff, f.name);
        }
    }
    return result;
}

pub fn FixedArray(comptime T: type, comptime cap: usize) type {
    return struct {
        items: [cap]T = undefined,
        len: usize = 0,

        const Self = @This();

        pub fn fromSlice(s: []const T) !Self {
            if (s.len > cap) return error.Overflow;
            var fa: Self = .{ .len = @intCast(s.len) };
            @memcpy(fa.items[0..s.len], s);
            return fa;
        }

        pub fn fromHex(hex: []const u8) !Self {
            var buf: [cap]u8 = undefined;
            return try fromSlice(try std.fmt.hexToBytes(&buf, hex));
        }

        pub fn slice(self: *const Self) []const T {
            return self.items[0..self.len];
        }

        pub fn append(self: *Self, item: T) !void {
            if (self.len >= cap) return error.Overflow;
            self.items[self.len] = item;
            self.len += 1;
        }

        pub fn write(self: Self, writer: *std.Io.Writer) !void {
            try writeCuint(writer, self.len);
            if (T == u8) {
                try writer.writeAll(self.items[0..self.len]);
            } else {
                for (self.slice()) |item| try serialize(T, writer, item);
            }
        }

        pub fn read(reader: *std.Io.Reader, arena: std.mem.Allocator) !Self {
            const len = try readCuint(reader);
            if (T == u8) {
                return try fromSlice(try reader.take(len));
            } else {
                var result: Self = .{};
                for (len) |_| try result.append(deserialize(T, reader, arena));
                return result;
            }
        }
    };
}

pub const String = FixedArray(u8, 256);
