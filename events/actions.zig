const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const Reader = std.Io.Reader;

const channel = @import("channel.zig");
const codec = @import("../protocol/codec.zig");
const shortTypeName = @import("../protocol/utils.zig").shortTypeName;
const Vec3 = @import("../world/utils.zig").Vec3;

const Channel = channel.Channel;

// `Actions` are mapped to `subpackets` that server receives in a `Gamedata` packet.
// They are `fire and forget`, and will be processed in the game loop
// without blocking the session thread.
// Server may respond with `Update` packets that will be aggregated
// and sent in one `Container` packet and the end of the tick.
// (but for now server responds immediately)

// We have to send it together with the session id
pub const Action = struct { u8, ActionPayload };

pub const ActionPayload = union(enum(u16)) {
    // zig fmt: off
    move: Move                 = 0x00,
    stop: Stop                 = 0x07,
    get_base_info: GetBaseInfo = 0x27,
    // zig fmt: on

    pub fn read(reader: *Reader, arena: std.mem.Allocator) !ActionPayload {
        const lenPlusOne = try codec.readCuint(reader);
        const len = try codec.readCuint(reader);
        assert(lenPlusOne - len == codec.cuintSize(len));

        const opcode = try reader.takeInt(u16, .little);
        const payload_len = len - 2;
        // Block until we have enough data
        if (reader.bufferedLen() < payload_len) {
            print("INFO: [Actions] waiting for more data ({}/{})...\n", .{ reader.bufferedLen(), payload_len });
            try reader.fill(payload_len);
        }
        inline for (@typeInfo(std.meta.Tag(ActionPayload)).@"enum".fields) |field| {
            if (field.value == opcode) {
                const T = @FieldType(ActionPayload, field.name);
                const hex = reader.buffered();
                const payload = try codec.deserialize(T, reader, arena);
                print("0x{x:0>2}: <- {s}\n", .{ opcode, shortTypeName(T) });
                print("    hex: {X}\n", .{hex});
                print("    {any}\n", .{payload});
                if (reader.bufferedLen() > 0) {
                    print("WARNING: [Actions] {any} has some leftover data: {X}\n", .{ T, reader.buffered() });
                }
                return @unionInit(ActionPayload, field.name, payload);
            }
        }

        print("  0x{X:0>2}: <- UNKNOWN ACTION ({X})\n", .{ opcode, reader.buffered() });

        reader.toss(payload_len);
        return error.UnknownOpcode;
    }

    fn deinit(self: *Action) void {
        switch (self) {
            inline else => |payload| {
                if (@hasDecl(@TypeOf(payload), "deinit")) payload.deinit();
            },
        }
    }
};

const Move = struct {
    pos: Vec3,
    dest: Vec3,
    unk1: u16,
    unk2: u16,
    unk3: u8,
    counter: u16,
};

const Stop = struct {
    pos: Vec3,
    unk1: u16,
    unk2: u16,
    counter: u16,
    unk4: u16,
};

const GetBaseInfo = struct {
    unk1: u8,
    unk2: u8,
    null: u8,
};
