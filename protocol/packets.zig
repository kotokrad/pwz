const std = @import("std");
const print = std.debug.print;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

const utils = @import("utils.zig");
const codec = @import("codec.zig");
const types = @import("types.zig");
const events = @import("../events/events.zig");

const Octets = codec.Octets;
const Seq = codec.Seq;
const UTF16String = codec.UTF16String;
const EndianTable = utils.EndianTable;
const Update = events.Update;
const Action = events.Action;

pub fn Owned(comptime T: type) type {
    return struct {
        arena: ?std.heap.ArenaAllocator = null,
        value: T,

        pub fn deinit(self: @This()) void {
            if (self.arena) |arena| arena.deinit();
        }
    };
}

pub const InPacket = union(enum(u16)) {
    // zig fmt: off
    gamedata: Action            = 0x22,
    keep_alive: KeepAlive       = 0x5A,
    login_request: LoginRequest = 0x03,
    key_exchange: KeyExchange   = 0x02,
    role_list: RoleList         = 0x52,
    select_role: SelectRole     = 0x46,
    // zig fmt: on

    pub fn read(reader: *Reader, arena: std.mem.Allocator) !InPacket {
        const peek = try reader.peekGreedy(1);
        // print("PEEK: {X}\n", .{peek});
        var pr = Reader.fixed(peek);
        const opcode = try codec.readCuint(&pr);

        // Gamedata packets have format:
        // 0x22|len+cuint_size(len)|len|opcode|data
        if (opcode == 0x22) {
            const payload = try Action.read(reader, arena);
            return @unionInit(InPacket, "gamedata", payload);
        } else {
            const len = try codec.readCuint(&pr);
            const total_len = len + pr.seek;
            inline for (@typeInfo(std.meta.Tag(InPacket)).@"enum".fields) |field| {
                if (field.value == opcode) {
                    const T = @FieldType(InPacket, field.name);
                    if (pr.bufferedLen() < len) {
                        print("ERROR: [Codec] not enough bytes to parse packet {s} ({}/{})\n", .{ field.name, peek.len, len });
                        return error.EndOfZdream;
                    }
                    const payload = try codec.deserialize(T, &pr, arena);
                    reader.toss(total_len);

                    print("0x{X:0>4}: <- {s}\n", .{ opcode, utils.shortTypeName(T) });
                    print("    {any}\n", .{payload});
                    return @unionInit(InPacket, field.name, payload);
                }
            }
            reader.toss(total_len);

            print("0x{X:0>4}: <- UNKNOWN OPCODE ({X})\n", .{ opcode, peek });

            return error.UnknownOpcode;
        }
    }
};

pub const OutPacket = union(enum(u16)) {
    // zig fmt: off
    container: Container            = 0x00,
    keep_alive: KeepAlive           = 0x5A,
    server_error: ServerError       = 0x05,
    challenge: Challenge            = 0x01,
    key_exchange: KeyExchange       = 0x02,
    online_announce: OnlineAnnounce = 0x04,
    role_list_re: RoleListRe        = 0x53,
    select_role_re: SelectRoleRe    = 0x47,
    // zig fmt: on

    pub fn write(self: OutPacket, writer: *Writer, arena: std.mem.Allocator) !void {
        var aw: Writer.Allocating = .init(arena);
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

                print("0x{X:0>4}: -> {s}\n", .{ opcode, utils.shortTypeName(T) });
                // print("{any}\n", .{variant});
            },
        }
    }
};

// Packet types
// ----------------------------------------

pub const Container = Seq(Update);

pub const KeepAlive = struct {
    data: u8,
};

pub const ServerError = struct {
    code: types.ErrorCode,
    message: []const u8,
};

pub const Challenge = struct {
    data: Octets(types.ChallengeData),
    version: [4]u8,
    auth_method: u8,
    crc_signature: Octets([26]u8),
    exp_multiplier: u8,
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

pub const RoleList = struct {
    account_id: u32,
    localsid: u32,
    slot: u32,
};

pub const RoleListRe = struct {
    result: u32,
    next_slot: u32,
    account_id: u32,
    session_id: u32,
    characters: []const types.RoleInfo,
};

pub const SelectRole = struct {
    char_id: u32,
};

pub const SelectRoleRe = struct {
    zeroes: u32 = 0,
    gm_code: [33]u8,
};
