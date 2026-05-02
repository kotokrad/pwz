const std = @import("std");
const print = std.debug.print;
const Io = std.Io;

const codec = @import("codec.zig");
const Octets = codec.Octets;
const UTF16String = codec.UTF16String;
const shortTypeName = codec.shortTypeName;

pub const InPacket = union(enum(u16)) {
    // zig fmt: off
    keep_alive: KeepAlive       = 0x5A,
    login_request: LoginRequest = 0x03,
    key_exchange: KeyExchange   = 0x02,
    // zig fmt: on

    pub fn read(reader: *Io.Reader, arena: std.mem.Allocator) !InPacket {
        const peek = try reader.peekGreedy(1);
        // print("PEEK: {X}\n", .{peek});
        var pr = Io.Reader.fixed(peek);
        const opcode = try codec.readCuint(&pr);
        const len = try codec.readCuint(&pr);
        const total_len = len + pr.seek;
        inline for (@typeInfo(std.meta.Tag(InPacket)).@"enum".fields) |field| {
            if (field.value == opcode) {
                const T = @FieldType(InPacket, field.name);
                if (pr.bufferedLen() < len) {
                    print("ERROR: not enough bytes to parse packet {s} ({}/{})\n", .{ field.name, peek.len, len });
                    return error.EndOfZdream;
                }
                const payload = try codec.deserialize(T, &pr, arena);
                reader.toss(total_len);

                print("0x{x:0>4}: <= {s}\n", .{ opcode, shortTypeName(T) });
                return @unionInit(InPacket, field.name, payload);
            }
        }
        reader.toss(total_len);

        print("0x{x:0>4}: <= UNKNOWN OPCODE\n", .{opcode});
        return error.UnknownOpcode;
    }
};

pub const OutPacket = union(enum(u16)) {
    // zig fmt: off
    keep_alive: KeepAlive           = 0x5A,
    server_error: ServerError       = 0x05,
    challenge: Challenge            = 0x01,
    key_exchange: KeyExchange       = 0x02,
    online_announce: OnlineAnnounce = 0x04,
    // zig fmt: on

    pub fn write(self: OutPacket, writer: *Io.Writer, arena: std.mem.Allocator) !void {
        var aw: std.Io.Writer.Allocating = .init(arena);
        defer aw.deinit();

        switch (self) {
            inline else => |variant, tag| {
                const T = @TypeOf(variant);
                const opcode = @intFromEnum(tag);

                try codec.serialize(T, &aw.writer, variant, arena);
                const payload = aw.written();

                try codec.writeCuint(writer, opcode);
                try codec.writeCuint(writer, payload.len);
                try writer.writeAll(payload);

                print("0x{x:0>4}: => {s}\n", .{ opcode, shortTypeName(T) });
            },
        }
    }
};

// Packet types
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
    unk1: u3 = 0,
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

pub const OnlineAnnounce = struct {
    account_id: u32,
    session_id: u32,
    time_remaining: u32,
    zone_id: u8,
    free_time_left: u32,
    free_time_end: u32,
    create_time: u32,
    referrer_flag: u8,
    // passwd_flag: u8, // NOTE: (1.4.5+) passwd_flag (using old password? Or need to update password?)
    // usbbind: u8, // NOTE: (1.4.5+)

};
