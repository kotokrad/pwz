// Serialize and parse DB to and from custom file format
// Completely useless since we have zon/json in std
// But what is not useless in this project

const std = @import("std");
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;

pub fn writeFile(comptime T: type, writer: *Writer, data: T) !void {
    if (!comptime isHashMap(T)) @compileError("Only HashMaps are supported");
    const Value = std.meta.fieldInfo(T.KV, .value).type;

    const name = typeSuffix(Value);

    var it = data.keyIterator();
    while (it.next()) |key| {
        const item = data.get(key.*).?;
        try writer.print("[{s}]\n", .{name});
        inline for (@typeInfo(Value).@"struct".fields) |f| {
            const field = @field(item, f.name);
            try writer.print("{s} = ", .{f.name});
            try writeValue(f.type, writer, field);
        }
        try writer.writeByte('\n');
    }
}

fn writeValue(comptime T: type, writer: *Writer, value: T) !void {
    switch (@typeInfo(T)) {
        // Here handle special cases
        // BoundedArray(u8, N) -> C0FFEE
        // BoundedArray(u32, N) -> 123,456,789
        .@"struct" => |info| {
            if (info.backing_integer) |I| {
                try writer.print("{}\n", .{@as(I, @bitCast(value))});
            } else if (comptime isBoundedArray(T)) {
                const array = @typeInfo(@FieldType(T, "items")).array;
                switch (array.child) {
                    u8 => {
                        if (isString(T)) {
                            try writer.print("{s}\n", .{value.slice()});
                        } else {
                            try writer.print("({X})\n", .{value.items[0..value.len]});
                        }
                    },
                    else => @compileError("Type is not writable: " ++ @typeName(@FieldType(T, "items"))),
                }
            } else try writeInlineStruct(T, writer, value);
        },
        .@"enum" => try writer.print("{}\n", .{@intFromEnum(value)}),
        .array => try writer.print("({X})\n", .{&value}),
        .optional => |info| {
            if (value == null) try writer.print("null\n", .{});
            try writeValue(info.child, writer, value.?);
        },
        else => try writer.print("{any}\n", .{value}),
    }
}

fn writeInlineStruct(comptime T: type, writer: *Writer, value: T) !void {
    var buf: [128]u8 = undefined;
    var temp: Writer = .fixed(&buf);
    inline for (@typeInfo(T).@"struct".fields) |f| {
        try writeValue(f.type, &temp, @field(value, f.name));
        try temp.writeByte(' ');
    }
    try writer.print("{{ ", .{});
    for (temp.buffered()) |c| if (c != '\n') try writer.writeByte(c);
    try writer.print("}}\n", .{});
}

const ParseError = error{
    EmptyFile,
    EmptyBlock,
    InvalidField,
    UnexpectedToken,
    WriteFailed,
};

pub fn readFile(comptime T: type, result: *T, data: []u8) ParseError!u32 {
    if (!comptime isHashMap(T)) @compileError("Only HashMaps are supported");
    const Value = std.meta.fieldInfo(T.KV, .value).type;

    const name = comptime typeSuffix(Value);

    var last_id: u32 = 10000;

    var blocks = std.mem.tokenizeSequence(u8, data, "[" ++ name ++ "]");
    if (blocks.peek() == null) return ParseError.EmptyFile;

    while (blocks.next()) |block| {
        errdefer std.debug.print("ERROR BLOCK:\n{s}\n", .{block});
        var lines = std.mem.tokenizeScalar(u8, block, '\n');
        if (lines.peek() == null) return ParseError.EmptyBlock;

        var item: Value = undefined;
        inline for (@typeInfo(Value).@"struct".fields) |f| {
            const line = lines.next() orelse {
                std.debug.print("ERROR: expected field {s}, got null\n", .{f.name});
                return ParseError.InvalidField;
            };

            const field = parseField(f.type, line) catch {
                std.debug.print("ERROR: parsing field {s}\n", .{f.name});
                return ParseError.InvalidField;
            };

            if (!std.mem.eql(u8, field.name, f.name)) {
                std.debug.print("ERROR: expected field {s}, got {s}\n", .{ f.name, field.name });
                return ParseError.InvalidField;
            }

            @field(item, f.name) = field.value;
        }
        last_id = @max(last_id, item.id);
        result.put(item.id, item) catch return ParseError.WriteFailed;
    }
    return last_id + 1;
}

fn Field(comptime T: type) type {
    return struct {
        name: []const u8,
        value: T,
    };
}

fn parseField(comptime T: type, line: []const u8) ParseError!Field(T) {
    var parts = std.mem.tokenizeAny(u8, line, " =");
    const field_name = parts.next() orelse return ParseError.InvalidField;
    const field_value = parts.rest();
    if (field_value.len == 0) return ParseError.InvalidField;
    const value = parseValue(T, field_value) catch return ParseError.InvalidField;
    return .{ .name = field_name, .value = value };
}

fn parseValue(comptime T: type, value: []const u8) !T {
    switch (@typeInfo(T)) {
        .int => |info| return try std.fmt.parseInt(@Int(info.signedness, info.bits), value, 10),
        .float => return try std.fmt.parseFloat(f32, value),
        .bool => return std.mem.eql(u8, value, "true"),
        .array => return try parseArray(T, value),
        .@"enum" => |info| return @enumFromInt(try std.fmt.parseInt(info.tag_type, value, 10)),
        // Here handle special cases
        // BoundedArray(u8, N) -> C0FFEE
        // BoundedArray(u32, N) -> 123,456,789
        .@"struct" => |info| {
            if (info.backing_integer) |I| {
                return @bitCast(try std.fmt.parseInt(@Int(.unsigned, @sizeOf(I) * 8), value, 10));
            } else if (comptime isBoundedArray(T)) {
                const array = @typeInfo(@FieldType(T, "items")).array;
                var buf: [array.len * @sizeOf(array.child)]u8 = undefined;
                switch (array.child) {
                    u8 => {
                        if (isString(T)) return try T.fromSlice(value);
                        var it = std.mem.tokenizeAny(u8, value, "()");
                        if (it.next()) |inner| {
                            const slice = try std.fmt.hexToBytes(&buf, inner);
                            return try T.fromSlice(slice);
                        } else {
                            return try T.fromSlice(&.{});
                        }
                    },
                    else => @compileError("Type is not readable: " ++ @typeName(T)),
                }
            } else return try parseInlineStruct(T, value);
        },
        .optional => |info| {
            if (std.mem.eql(u8, value, "null")) return null;
            return try parseValue(info.child, value);
        },
        else => @compileError("Type is not readable: " ++ @typeName(T)),
    }
    return ParseError.InvalidField;
}

fn parseArray(comptime T: type, literal: []const u8) !T {
    if (@typeInfo(T) != .array) std.debug.print("Type is not readable: {s}\n", .{@typeName(T)});

    const info = @typeInfo(T).array;
    var result: [info.len]info.child = undefined;
    switch (info.child) {
        u8 => {
            var it = std.mem.tokenizeAny(u8, literal, "()");
            if (it.next()) |inner| {
                _ = try std.fmt.hexToBytes(result[0..info.len], inner);
            }
        },
        u32 => {
            var items = std.mem.tokenizeScalar(u8, literal, ',');
            var i: usize = 0;
            while (items.next()) |item| {
                result[i] = try std.fmt.parseInt(u32, item, 10);
                i += 1;
            }
        },
        else => std.debug.print("Type is not readable: {s}\n", .{@typeName(T)}),
    }
    return result;
}

fn parseInlineStruct(comptime T: type, value: []const u8) !T {
    var result: T = undefined;
    var parts = std.mem.tokenizeAny(u8, value, "{ }");
    inline for (@typeInfo(T).@"struct".fields) |f| {
        const field = parts.next() orelse return ParseError.InvalidField;
        @field(result, f.name) = try parseValue(f.type, field);
    }
    if (parts.next() != null) return ParseError.UnexpectedToken;
    return result;
}

// Utils

fn isHashMap(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "KV") and @hasField(T.KV, "key") and @hasField(T.KV, "value");
}

fn isString(comptime T: type) bool {
    return @hasDecl(T, "is_unicode") and T.is_unicode;
}

fn isBoundedArray(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasField(T, "items") and @hasField(T, "len") and @hasDecl(T, "capacity");
}

fn typeSuffix(comptime T: type) []const u8 {
    return comptime blk: {
        const full = @typeName(T);
        const dot = std.mem.lastIndexOfScalar(u8, full, '.');
        const suffix = if (dot) |d| full[d + 1 ..] else full;
        var result: [suffix.len]u8 = undefined;
        for (&result, suffix) |*r, c| r.* = std.ascii.toLower(c);
        const final = result;
        break :blk &final;
    };
}
