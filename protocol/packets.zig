const std = @import("std");
const print = std.debug.print;
const Io = std.Io;

const codec = @import("codec.zig");
const Octets = codec.Octets;
const UTF16String = codec.UTF16String;
const shortTypeName = codec.shortTypeName;

pub const InPacket = union(enum(usize)) {
    // zig fmt: off
    LoginRequest: LoginRequest = 0x03,
    KeepAlive: KeepAlive       = 0x5A,
    KeyExchange: KeyExchange   = 0x02,
    // zig fmt: on

    pub fn read(reader: *Io.Reader, arena: std.mem.Allocator) !InPacket {
        const peek = try reader.peekGreedy(1);
        print("PEEK: {X}\n", .{peek});
        var pr = Io.Reader.fixed(peek);
        const opcode = try codec.readCuint(&pr);
        const len = try codec.readCuint(&pr);
        const total_len = len + pr.seek;
        inline for (@typeInfo(std.meta.Tag(InPacket)).@"enum".fields) |field| {
            if (field.value == opcode) {
                const T = @FieldType(InPacket, field.name);
                if (pr.bufferedLen() < len) {
                    print("ERROR: not enough bytes to parse packet {s} ({}/{})\n", .{ shortTypeName(T), peek.len, len });
                    return error.EndOfZdream;
                }
                const payload = try codec.deserialize(T, &pr, arena);
                reader.toss(total_len);
                print("0x{x:0>4}: <= {s}\n", .{ opcode, shortTypeName(T) });
                return @unionInit(InPacket, shortTypeName(T), payload);
            }
        }
        print("0x{x:0>4}: <= UNKNOWN OPCODE\n", .{opcode});

        // C8BE05662BAAE987ABD3F35721CB778129C66BA7
        // C8BE05A6A2347D988B50A04CB35E045F8A59D3A7

        // print("LEFT: {X}", .{reader.buffer});
        reader.toss(total_len);
        return error.UnknownOpcode;
    }
};

pub const OutPacket = union(enum(usize)) {
    // zig fmt: off
    Challenge: Challenge     = 0x01,
    ServerError: ServerError = 0x05,
    KeepAlive: KeepAlive     = 0x5A,
    KeyExchange: KeyExchange = 0x02,
    // zig fmt: on

    pub fn write(self: OutPacket, writer: *Io.Writer, arena: std.mem.Allocator) !void {
        var aw: std.Io.Writer.Allocating = .init(arena);
        defer aw.deinit();

        switch (self) {
            inline else => |variant, tag| {
                const T = @TypeOf(variant);
                const opcode = @intFromEnum(tag);

                // print("debug: Serializing packet {s}\n", .{@typeName(T)});
                try codec.serialize(T, &aw.writer, variant, arena);
                const payload = aw.written();
                // print("debug: payload {x}\n", .{payload});

                // print("debug: Writing packet {s} with opcode {d}\n", .{@typeName(T), opcode});
                try codec.writeCuint(writer, opcode);
                try codec.writeCuint(writer, payload.len);
                try writer.writeAll(payload);
            },
        }
    }
};

// pub fn Packet(comptime T: type) type {
//     return struct {
//         value: T,
//
//         const Self = @This();
//         fn get_opcode() usize {
//             inline for (@typeInfo(OutPacket).@"union".fields) |field| {
//                 if (field.type == T) {
//                     const tag = @field(std.meta.Tag(OutPacket), field.name);
//                     return @intFromEnum(tag);
//                 }
//             }
//             @compileError(std.fmt.comptimePrint("Packet {} is not in the list", .{@typeName(T)}));
//         }
//
//         pub fn write(self: Self, writer: *Io.Writer, arena: std.mem.Allocator) !void {
//             var aw: std.Io.Writer.Allocating = .init(arena);
//             defer aw.deinit();
//
//             try codec.serialize(T, &aw.writer, self.value, arena);
//             const payload = aw.written();
//
//             try codec.writeCuint(writer, get_opcode());
//             try codec.writeCuint(writer, payload.len);
//             try writer.writeAll(payload);
//             print("debug: Writing packet: {s}\n", .{@typeName(T)});
//         }
//
//         pub fn init(value: T) Packet(T) {
//             return .{ .value = value };
//         }
//     };
// }

// ----------------------------------------
pub const KeepAlive = struct {
    data: u8,
};

pub const ErrorCode = enum(u8) {
    invalid_credentials = 0x03,
    already_in_game = 0x10,
    maintenance = 0x25,
    server_offline = 0x28,
    account_not_activated = 0x83,
};

pub const ServerError = struct {
    code: ErrorCode,
    message: []const u8,
};

pub const ServerFlags = packed struct(u16) {
    unk0: u1 = 0,
    is_money_bonus: bool = false,
    is_drop_bonus: bool = false,
    is_spirit_bonus: bool = false,
    unk4: u3 = 0,
    is_pvp: bool = false,
    unk2: u8 = 0,
};

pub const Challenge = struct {
    data: Octets(ChallengeData),
    version: [4]u8,
    auth_method: u8,
    crc_signature: Octets([26]u8),
    exp_multiplier: u8,
};

pub const ChallengeData = struct {
    server_load: u8,
    unk1: u16 = 0,
    flags: ServerFlags,
    unk2: u32 = 0,
    random_bytes: [8]u8,
};

pub const LoginRequest = struct {
    username: []u8,
    hash: Octets([16]u8),
};

pub const KeyExchange = struct {
    key: Octets([16]u8),
    null: u8 = 0,
};
