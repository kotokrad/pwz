const std = @import("std");
const print = std.debug.print;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

const utils = @import("utils.zig");
const overrides = @import("overrides.zig");

const FixedArray = utils.FixedArray;
const String = utils.String;

const shortTypeName = utils.shortTypeName;
const getEndianFor = utils.getEndianFor;

const LengthPrefixSize = enum(u16) { cuint, _ };

/// Writes an item prefixed by its byte size
/// Parametrized by length prefix type (cuint|uint) and endianness
fn OctetsGeneric(
    comptime len_prefix_size: LengthPrefixSize,
    comptime len_prefix_endian: std.builtin.Endian,
    comptime T: type,
) type {
    return struct {
        value: T,

        const U = std.meta.Int(.unsigned, @intFromEnum(len_prefix_size));
        const Self = @This();
        pub fn init(value: T) Self {
            return .{ .value = value };
        }

        pub fn write(self: Self, writer: *Writer) !void {
            var buf: [@sizeOf(T)]u8 = undefined;
            var fw = Writer.fixed(&buf);
            try serialize(T, &fw, self.value);
            const payload = buf[0..fw.end];

            if (len_prefix_size == .cuint) {
                try writeCuint(writer, payload.len);
            } else {
                try writer.writeInt(U, @truncate(payload.len), len_prefix_endian);
            }

            try writer.writeAll(payload);
        }

        pub fn read(reader: *Reader, arena: std.mem.Allocator) !Self {
            const len = if (len_prefix_size == .cuint) try readCuint(reader) else try reader.takeInt(U, len_prefix_endian);
            const buf = try reader.take(len);
            var buf_reader = Reader.fixed(buf);
            const value = try deserialize(T, &buf_reader, arena);
            return .{ .value = value };
        }
    };
}

pub fn Octets(comptime T: type) type {
    return OctetsGeneric(.cuint, .little, T);
}

pub fn OctetsU32LE(comptime T: type) type {
    return OctetsGeneric(@enumFromInt(32), .little, T);
}

pub fn OctetsU16LE(comptime T: type) type {
    return OctetsGeneric(@enumFromInt(16), .little, T);
}

/// Writes amount of items, then encodes items one-by-one
/// Parametrized by length prefix type (cuint|uint) and endianness
fn VecGeneric(
    comptime len_prefix_size: LengthPrefixSize,
    comptime len_prefix_endian: std.builtin.Endian,
    comptime T: type,
    comptime cap: usize,
) type {
    return struct {
        list: FixedArray(T, cap),

        const U = std.meta.Int(.unsigned, @intFromEnum(len_prefix_size));
        const Self = @This();
        pub fn init(list: []const T) !Self {
            return .{ .list = try .fromSlice(list) };
        }

        pub fn write(self: Self, writer: *Writer) !void {
            if (len_prefix_size == .cuint) {
                try writeCuint(writer, self.list.len);
            } else {
                try writer.writeInt(U, @truncate(self.list.len), len_prefix_endian);
            }
            if (T == u8) {
                try writer.writeAll(self.list);
            } else {
                for (self.list.slice()) |item| try serialize(T, writer, item);
            }
        }

        pub fn read(reader: *Reader, arena: std.mem.Allocator) !Self {
            const len = if (len_prefix_size == .cuint) try readCuint(reader) else try reader.takeInt(U, len_prefix_endian);
            if (T == u8) {
                return try reader.take(len);
            } else {
                var result: std.ArrayList(T) = .empty;
                for (len) |item| result.append(arena, deserialize(T, reader, item, arena));
                return .{ .list = result };
            }
        }
    };
}

pub fn Vec(comptime T: type, comptime cap: usize) type {
    return VecGeneric(.cuint, .little, T, cap);
}

pub fn VecU32LE(comptime T: type, comptime cap: usize) type {
    return VecGeneric(@enumFromInt(32), .little, T, cap);
}

/// Encodes items one-by-one without any size prefix
pub fn Seq(comptime T: type, comptime cap: usize) type {
    return struct {
        list: FixedArray(T, cap),

        const Self = @This();
        pub fn write(self: Self, writer: *Writer) !void {
            for (self.list.slice()) |item| {
                try serialize(T, writer, item);
            }
        }

        // TODO: test this
        // pub fn read(reader: *Reader, arena: std.mem.Allocator) !Octets(T) {
        //     var result: std.ArrayList(T) = .empty;
        //     while (reader.seek < reader.end) {
        //         print("seek = {}, end = {}\n", .{ reader.seek, reader.end });
        //         result.append(arena, deserialize(T, reader, arena));
        //     }
        //     return .{ .value = result };
        // }

        pub fn init(value: T) Octets(T) {
            return .{ .value = value };
        }
    };
}

pub const UTF16String = struct {
    string: String,
    const Self = @This();

    pub fn write(self: Self, writer: *Writer) !void {
        var buf: [128]u16 = undefined;
        const len = try std.unicode.utf8ToUtf16Le(&buf, self.string.slice());
        try writeCuint(writer, len * 2);
        try writer.writeAll(std.mem.sliceAsBytes(buf[0..len]));
    }

    pub fn read(reader: *Reader, arena: std.mem.Allocator) !UTF16String {
        _ = arena;
        const len = try readCuint(reader);
        var utf16_buf: [128]u16 = undefined;
        const data = try reader.take(len);
        @memcpy(std.mem.sliceAsBytes(utf16_buf[0 .. len / 2]), data);
        var utf8_buf: [384]u8 = undefined;
        _ = try std.unicode.utf16LeToUtf8(&utf8_buf, utf16_buf[0 .. len / 2]);
        return .{ .string = try .fromSlice(utf8_buf[0 .. len / 2]) };
    }

    pub fn init(string: []const u8) !UTF16String {
        return .{ .string = try .fromSlice(string) };
    }

    pub fn fromFixedString(string: String) UTF16String {
        return .{ .string = string };
    }
};

pub fn writeCuint(writer: *Writer, value: usize) !void {
    if (value < 0x80) {
        try writer.writeInt(u8, @intCast(value), .big);
    } else if (value < 0x4000) {
        const v = (value | 0x8000);
        try writer.writeInt(u16, @intCast(v), .big);
    } else if (value < 0x20000000) {
        const v = (value | 0xC0000000);
        try writer.writeInt(u32, @intCast(v), .big);
    } else std.debug.panic("ERROR: [Codec] CUInt overflow: value {} >= 0x20000000\n", .{value});
}

pub fn readCuint(reader: *Reader) !usize {
    var bytes = try reader.peek(1);
    if (bytes[0] < 0x80) {
        reader.toss(1);
        return bytes[0];
    }

    bytes = try reader.peek(2);
    if (bytes[0] < 0xC0) {
        const value = try reader.takeInt(u16, .big);
        return value & 0x3FFF;
    }

    const value = try reader.takeInt(u32, .big);
    return value & 0x1FFFFFFF;
}

pub fn cuintSize(value: usize) usize {
    if (value < 0x80) {
        return 1;
    } else if (value < 0x4000) {
        return 2;
    } else if (value < 0x20000000) {
        return 4;
    } else std.debug.panic("ERROR: [Codec] CUInt overflow: value {} >= 0x20000000\n", .{value});
}

pub fn serialize(comptime T: type, writer: *Writer, value: T) !void {
    switch (@typeInfo(T)) {
        .int => {
            try writer.writeInt(T, value, .little);
        },
        .float => {
            if (T != f32) {
                @compileError("Float type " ++ @typeName(T) ++ " is not writable, only f32 are supported");
            }
            try writer.writeInt(u32, @intFromFloat(value * 16777216.0), .little);
        },
        .bool => {
            try writer.writeByte(if (value) 1 else 0);
        },
        .@"struct" => |info| {
            if (info.backing_integer) |BackingInt| {
                try writer.writeInt(BackingInt, @bitCast(value), .big);
            } else if (@hasDecl(overrides, shortTypeName(T)) and @hasDecl(@field(overrides, shortTypeName(T)), "write")) {
                const override = @field(overrides, shortTypeName(T));
                try override.write(value, writer);
            } else if (@hasDecl(T, "write")) {
                try value.write(writer);
            } else {
                inline for (info.fields) |f| {
                    const field = @field(value, f.name);
                    switch (@typeInfo(f.type)) {
                        // For `int` field, trying to apply endianness override
                        // First look for `endian: EndianTable` in the type itself,
                        // otherwise check type override in the `overrides.zig`
                        .int => {
                            const endian = getEndianFor(T, f.name) orelse overrides.getEndianFor(T, f.name) orelse .little;
                            try writer.writeInt(f.type, field, endian);
                        },
                        else => {
                            try serialize(f.type, writer, field);
                        },
                    }
                }
            }
        },
        .array => {
            try writer.writeAll(&value);
        },
        .@"enum" => |info| {
            try writer.writeInt(info.tag_type, @intFromEnum(value), .little);
        },
        .@"union" => {
            if (@hasDecl(T, "write")) {
                try value.write(writer);
            } else @compileError("Union type is not writable: " ++ @typeName(T));
        },
        else => @compileError("Type is not writable: " ++ @typeName(T)),
    }
}

pub fn deserialize(comptime T: type, reader: *Reader, arena: std.mem.Allocator) !T {
    switch (@typeInfo(T)) {
        .int => {
            return try reader.takeInt(T, .little);
        },
        .float => {
            if (T != f32) {
                @compileError("Float type " ++ @typeName(T) ++ " is not readable, only f32 are supported");
            }
            return @as(f32, @floatFromInt(try reader.takeInt(u32, .little))) / 16777216.0;
        },
        .bool => {
            return try reader.takeByte() == 1;
        },
        .@"struct" => |info| {
            if (info.backing_integer) |BackingInt| {
                const int = try reader.takeInt(BackingInt, .big);
                return @bitCast(int);
            } else if (@hasDecl(overrides, shortTypeName(T)) and @hasDecl(@field(overrides, shortTypeName(T)), "read")) {
                const override = @field(overrides, shortTypeName(T));
                return try override.read(reader, arena);
            } else if (@hasDecl(T, "read")) {
                return try T.read(reader, arena);
            } else {
                var result: T = undefined;
                inline for (info.fields) |f| {
                    switch (@typeInfo(f.type)) {
                        .int => {
                            // For `int` field, trying to apply endianness override
                            // First look for `endian: EndianTable` in the type itself,
                            // otherwise check type override in the `overrides.zig`
                            const endian = getEndianFor(T, f.name) orelse overrides.getEndianFor(T, f.name) orelse .little;
                            @field(result, f.name) = try reader.takeInt(f.type, endian);
                        },
                        else => @field(result, f.name) = try deserialize(f.type, reader, arena),
                    }
                }
                return result;
            }
        },
        .array => |info| {
            var result: T = std.mem.zeroes(T);
            if (info.child == u8) {
                const ptr = try reader.takeArray(info.len);
                result = ptr.*;
            } else {
                for (0..info.len) |i| {
                    result[i] = try deserialize(info.child, reader, arena);
                }
            }
            return result;
        },
        .@"enum" => |info| {
            const int = try reader.takeInt(info.tag_type, .little);
            return @enumFromInt(int);
        },
        .@"union" => {
            if (@hasDecl(T, "read")) {
                return try T.read(reader, arena);
            } else @compileError("Union type is not readable: " ++ @typeName(T));
        },
        else => @compileError("Type is not readable: " ++ @typeName(T)),
    }
}

test "read and write CUInt" {
    var buf: [7]u8 = undefined;
    var writer = Writer.fixed(&buf);
    var reader = Reader.fixed(&buf);

    try writeCuint(&writer, 69);
    try writeCuint(&writer, 420);
    try writeCuint(&writer, 333333333);

    try std.testing.expectFmt("4581A4D3DE4355", "{X}", .{writer.buffered()});

    const first = try readCuint(&reader);
    const second = try readCuint(&reader);
    const third = try readCuint(&reader);

    try std.testing.expectEqual(first, 69);
    try std.testing.expectEqual(second, 420);
    try std.testing.expectEqual(third, 333333333);
}
