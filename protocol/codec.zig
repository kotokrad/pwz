const std = @import("std");
const print = std.debug.print;
const Io = std.Io;

pub fn shortTypeName(comptime T: type) []const u8 {
    const full = @typeName(T);
    return if (std.mem.lastIndexOfScalar(u8, full, '.')) |i| full[i + 1 ..] else full;
}

pub fn BEInt(comptime T: type) type {
    const info = @typeInfo(T);
    if (info != .int) @compileError("T must be an int");
    return packed struct {
        value: T,

        const Self = @This();
        fn write(self: Self, writer: *Io.Writer) !void {
            try writer.writeInt(T, self.value, .big);
            // print("Writing {s}be: {any}\n", .{ @typeName(T), self.value });
        }
    };
}

pub const u8be = BEInt(u8);
pub const u16be = BEInt(u16);
pub const u32be = BEInt(u32);

pub fn U8BE(value: u8) u8be {
    return .{ .value = value };
}

pub fn U16BE(value: u8) u16be {
    return .{ .value = value };
}

pub fn U32BE(value: u32) u32be {
    return .{ .value = value };
}

pub fn Octets(comptime T: type) type {
    return struct {
        value: T,
        const Self = @This();

        pub fn write(self: Self, writer: *Io.Writer, arena: std.mem.Allocator) !void {
            var aw: std.Io.Writer.Allocating = .init(arena);
            defer aw.deinit();
            try serialize(T, &aw.writer, self.value, arena);
            const payload = aw.written();

            try writeCuint(writer, payload.len);
            try writer.writeAll(payload);
        }

        pub fn read(reader: *Io.Reader, arena: std.mem.Allocator) !Octets(T) {
            const size = try readCuint(reader);
            const buf = try reader.take(size);
            var buf_reader = Io.Reader.fixed(buf);
            const value = try deserialize(T, &buf_reader, arena);
            return .{ .value = value };
        }

        pub fn init(value: T) Octets(T) {
            return .{ .value = value };
        }
    };
}

pub const UTF16String = struct {
    value: []u8,
    const Self = @This();

    pub fn write(self: Self, writer: *Io.Writer, arena: std.mem.Allocator) !void {
        _ = arena;
        var buf: [128]u16 = undefined;
        const len = try std.unicode.utf8ToUtf16Le(&buf, self.value);
        // const utf16 = try std.unicode.utf8ToUtf16LeAlloc(arena, self.value);
        try writeCuint(writer, len * 2);
        try writer.writeAll(buf[0..len]);
    }

    pub fn read(reader: *Io.Reader, arena: std.mem.Allocator) !UTF16String {
        const len = try readCuint(reader);
        const buf = try reader.readAlloc(arena, len);
        const utf8 = try std.unicode.utf16LeToUtf8Alloc(arena, buf);
        return .{ .value = utf8 };
    }

    pub fn init(value: []const u8, arena: std.mem.Allocator) !UTF16String {
        const buf = try arena.dupe(u8, value);
        return .{ .value = buf };
    }
};

// pub const Bytes = struct {
//     value: []u8,
//     const Self = @This();
//
//     pub fn write(self: Self, writer: *Io.Writer, arena: std.mem.Allocator) !void {
//         _ = arena;
//         try writeCuint(writer, self.value.len);
//         try writer.writeAll(self.value);
//     }
//
//     pub fn read(reader: *Io.Reader, arena: std.mem.Allocator) !Bytes {
//         // var list = try std.ArrayList(u8).initCapacity(arena, len);
//         // const buf = try list.addManyAsSlice(arena, len);
//         // try reader.readSliceShort(buf);
//         const len = try readCuint(reader);
//         const buf = try reader.readAlloc(arena, len);
//         return .{ .value = buf };
//     }
//
//     pub fn init(value: []const u8, arena: std.mem.Allocator) !Bytes {
//         // var list = try std.ArrayList(u8).initCapacity(arena, value.len);
//         // try list.appendSlice(arena, value);
//         // const writer = Io.Writer.Allocating.init(arena);
//         // writer.
//         const buf = try arena.dupe(u8, value);
//         return .{ .value = buf };
//     }
// };

pub fn writeCuint(writer: *Io.Writer, value: usize) !void {
    if (value < 0x80) {
        try writer.writeInt(u8, @intCast(value), .big);
    } else if (value < 0x4000) {
        const v = (value | 0x8000);
        try writer.writeInt(u16, @intCast(v), .big);
    } else if (value < 0x20000000) {
        const v = (value | 0xC0000000);
        try writer.writeInt(u32, @intCast(v), .big);
    } else std.debug.panic("ERROR: CUInt overflow: value {} >= 0x20000000\n", .{value});
}

pub fn readCuint(reader: *Io.Reader) !usize {
    var bytes = try reader.peek(1);
    if (bytes[0] < 0x80) {
        reader.toss(1);
        return bytes[0];
    }

    bytes = try reader.peek(2);
    if (bytes[1] < 0xC0) {
        const value = try reader.takeInt(u16, .big);
        return value & 0x3FFF;
    }

    const value = try reader.takeInt(u32, .big);
    return value & 0x1FFFFFFF;
}

pub fn serialize(comptime T: type, writer: *Io.Writer, value: T, arena: std.mem.Allocator) !void {
    const info = @typeInfo(T);
    switch (info) {
        .int => {
            // print("debug: Writing {s}le: {any}\n", .{ @typeName(T), value });
            try writer.writeInt(T, value, .little);
        },
        .@"struct" => |struct_info| {
            if (struct_info.backing_integer) |BackingInt| {
                try writer.writeInt(BackingInt, @bitCast(value), .big);
            } else if (@hasDecl(T, "write")) {
                try value.write(writer, arena);
            } else {
                inline for (struct_info.fields) |f| {
                    const field = @field(value, f.name);
                    try serialize(f.type, writer, field, arena);
                }
            }
        },
        .array => {
            try writer.writeAll(&value);
        },
        .@"enum" => |enum_type| {
            try writer.writeInt(enum_type.tag_type, @intFromEnum(value), .little);
        },
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => {
                const len = value.len * @sizeOf(pointer_info.child);
                try writeCuint(writer, len);
                try writer.writeAll(value);
            },
            else => @compileError("Pointer type is not writable: " ++ @typeName(T)),
        },
        else => @compileError("Type is not writable: " ++ @typeName(T)),
    }
}

pub fn deserialize(comptime T: type, reader: *Io.Reader, arena: std.mem.Allocator) !T {
    const info = @typeInfo(T);
    switch (info) {
        .int => {
            // print("debug: Reading {s}le\n", .{@typeName(T)});
            return try reader.takeInt(T, .little);
        },
        .@"struct" => |struct_info| {
            if (struct_info.backing_integer) |BackingInt| {
                const int = try reader.takeInt(BackingInt, .big);
                return @bitCast(int);
            } else if (@hasDecl(T, "read")) {
                return try T.read(reader, arena);
            } else {
                var result: T = undefined;
                inline for (struct_info.fields) |f| {
                    @field(result, f.name) = try deserialize(f.type, reader, arena);
                }
                return result;
            }
        },
        .array => |array_info| {
            var result: T = std.mem.zeroes(T);
            if (array_info.child == u8) {
                const ptr = try reader.takeArray(array_info.len);
                result = ptr.*;
            } else {
                for (0..array_info.len) |i| {
                    result[i] = try deserialize(array_info.child, reader, arena);
                }
            }
            return result;
        },
        .@"enum" => |enum_info| {
            const int = try reader.takeInt(enum_info.tag_type, .little);
            return @enumFromInt(int);
        },
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => {
                const len = try readCuint(reader);
                const buf = try reader.take(len);
                return buf;
            },
            else => @compileError("Pointer type is not readable: " ++ @typeName(T)),
        },
        else => @compileError("Type is not readable: " ++ @typeName(T)),
    }
}

pub fn debug(value: anytype) void {
    const T = @TypeOf(value);
    var scratch: std.heap.ArenaAllocator = .init(std.heap.smp_allocator);
    var aw: Io.Writer.Allocating = .init(scratch.allocator());
    const name = shortTypeName(T);
    serialize(T, &aw.writer, value, scratch.allocator()) catch |err| {
        print("DEBUG: serialization of {s} failed: {}", .{ name, err });
        return;
    };
    print("DEBUG: {s} serialized:\n", .{name});
    print("{X}\n", .{aw.written()});
}

test "read and write CUInt" {
    var buf: [10]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    var reader = std.Io.Reader.fixed(&buf);

    try writeCuint(&writer, 69);
    try writeCuint(&writer, 420);
    try writeCuint(&writer, 333333333);

    const first = try readCuint(&reader);
    const second = try readCuint(&reader);
    const third = try readCuint(&reader);

    try std.testing.expectEqual(first, 69);
    try std.testing.expectEqual(second, 420);
    try std.testing.expectEqual(third, 333333333);
}
