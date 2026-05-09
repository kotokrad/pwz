const std = @import("std");
const print = std.debug.print;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

const utils = @import("utils.zig");
const overrides = @import("overrides.zig");

const shortTypeName = utils.shortTypeName;
const getEndianFor = utils.getEndianFor;

pub fn Seq(comptime T: type) type {
    return struct {
        list: []T,

        const Self = @This();
        pub fn write(self: Self, writer: *Writer, arena: std.mem.Allocator) !void {
            for (self.list) |item| {
                try serialize(T, writer, item, arena);
            }
        }

        pub fn read(reader: *Reader, arena: std.mem.Allocator) !Octets(T) {
            var result: std.ArrayList(T) = .empty;
            while (reader.seek < reader.end) {
                print("seek = {}, end = {}\n", .{ reader.seek, reader.end });
                result.append(arena, deserialize(T, reader, arena));
            }
            return .{ .value = result };
        }

        pub fn init(value: T) Octets(T) {
            return .{ .value = value };
        }
    };
}

pub fn Octets(comptime T: type) type {
    return struct {
        value: T,

        const Self = @This();
        pub fn init(value: T) Octets(T) {
            return .{ .value = value };
        }

        pub fn write(self: Self, writer: *Writer, arena: std.mem.Allocator) !void {
            var aw: Writer.Allocating = .init(arena);
            defer aw.deinit();
            try serialize(T, &aw.writer, self.value, arena);
            const payload = aw.written();

            try writeCuint(writer, payload.len);
            try writer.writeAll(payload);
        }

        pub fn read(reader: *Reader, arena: std.mem.Allocator) !Octets(T) {
            const size = try readCuint(reader);
            const buf = try reader.take(size);
            var buf_reader = Reader.fixed(buf);
            const value = try deserialize(T, &buf_reader, arena);
            return .{ .value = value };
        }
    };
}

pub const UTF16String = struct {
    value: []const u8,
    const Self = @This();

    pub fn write(self: Self, writer: *Writer, arena: std.mem.Allocator) !void {
        _ = arena;
        var buf: [128]u16 = undefined;
        const len = try std.unicode.utf8ToUtf16Le(&buf, self.value);
        try writeCuint(writer, len * 2);
        try writer.writeAll(std.mem.sliceAsBytes(buf[0..len]));
    }

    pub fn read(reader: *Reader, arena: std.mem.Allocator) !UTF16String {
        const len = try readCuint(reader);
        const buf = try reader.readAlloc(arena, len);
        const utf8 = try std.unicode.utf16LeToUtf8Alloc(arena, buf);
        return .{ .value = utf8 };
    }

    pub fn init(value: []const u8) UTF16String {
        return .{ .value = value };
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

pub fn serialize(comptime T: type, writer: *Writer, value: T, arena: std.mem.Allocator) !void {
    switch (@typeInfo(T)) {
        .int => {
            try writer.writeInt(T, value, .little);
        },
        .float => {
            if (T != f32) {
                @compileError("Float type " ++ @typeName(T) ++ " is not writable, only f32 are supported");
            }
            try writer.writeInt(u32, @bitCast(value * 16777216.0), .little);
        },
        .bool => {
            try writer.writeByte(if (value) 1 else 0);
        },
        .@"struct" => |info| {
            if (info.backing_integer) |BackingInt| {
                try writer.writeInt(BackingInt, @bitCast(value), .big);
            } else if (@hasDecl(overrides, shortTypeName(T)) and @hasDecl(@field(overrides, shortTypeName(T)), "write")) {
                const override = @field(overrides, shortTypeName(T));
                try override.write(value, writer, arena);
            } else if (@hasDecl(T, "write")) {
                try value.write(writer, arena);
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
                            try serialize(f.type, writer, field, arena);
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
                try value.write(writer, arena);
            } else @compileError("Union type is not writable: " ++ @typeName(T));
        },
        .pointer => |info| switch (info.size) {
            .slice => {
                try writeCuint(writer, value.len);
                if (info.child == u8) {
                    try writer.writeAll(value);
                } else {
                    for (value) |item| try serialize(info.child, writer, item, arena);
                }
            },
            else => @compileError("Pointer type is not writable: " ++ @typeName(T)),
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
            return @as(f32, @bitCast(try reader.takeInt(u32, .little))) / 16777216.0;
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
        .pointer => |info| switch (info.size) {
            .slice => {
                const len = try readCuint(reader);

                if (info.child == u8) {
                    return try reader.take(len);
                } else {
                    var result: std.ArrayList(info.child) = .empty;
                    for (len) |item| result.append(arena, deserialize(info.child, reader, item, arena));
                    return result;
                }
            },
            else => @compileError("Pointer type is not readable: " ++ @typeName(T)),
        },
        else => @compileError("Type is not readable: " ++ @typeName(T)),
    }
}

pub fn debug(value: anytype) void {
    const T = @TypeOf(value);
    var scratch: std.heap.ArenaAllocator = .init(std.heap.smp_allocator);
    var aw: Writer.Allocating = .init(scratch.allocator());
    const name = shortTypeName(T);
    serialize(T, &aw.writer, value, scratch.allocator()) catch |err| {
        print("DEBUG: serialization of {s} failed: {}", .{ name, err });
        return;
    };
    print("DEBUG: {s} serialized:\n", .{name});
    print("{X}\n", .{aw.written()});
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
