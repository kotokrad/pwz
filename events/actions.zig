const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const Reader = std.Io.Reader;

const channel = @import("channel.zig");
const codec = @import("../protocol/codec.zig");
const shortTypeName = @import("../protocol/utils.zig").shortTypeName;
const Vec3 = @import("../world/utils.zig").Vec3;

const Channel = channel.Channel;
const Owned = channel.Owned;

// `Actions` are mapped to `subpackets` that server receives in a `Gamedata` packet.
// They are `fire and forget`, and will be processed in the game loop
// without blocking the session thread.
// Server may respond with `Update` packets that will be aggregated
// and sent in one `Container` packet and the end of the tick.
// (but for now server responds immediately)
pub const Action = union(enum(u16)) {
    // zig fmt: off
    move: Move                 = 0x00,
    stop: Stop                 = 0x07,
    get_base_info: GetBaseInfo = 0x27,
    // zig fmt: on

    pub fn read(reader: *Reader, arena: std.mem.Allocator) !Action {
        const Ox22 = try reader.takeByte();
        assert(Ox22 == 0x22);
        const lenPlusOne = try codec.readCuint(reader);
        const len = try codec.readCuint(reader);
        assert(lenPlusOne - len == codec.cuintSize(len));

        const opcode = try reader.takeInt(u16, .little);
        const payload_len = len - 2;
        inline for (@typeInfo(std.meta.Tag(Action)).@"enum".fields) |field| {
            if (field.value == opcode) {
                const T = @FieldType(Action, field.name);
                if (reader.bufferedLen() < payload_len) {
                    print("ERROR: [Actions] not enough bytes to parse action {s} ({}/{})\n", .{ field.name, reader.bufferedLen(), payload_len });
                    return error.EndOfStream;
                }
                const payload = try codec.deserialize(T, reader, arena);
                print("  0x{x:0>2}: <- {s}\n", .{ opcode, shortTypeName(T) });
                print("      {any}\n", .{payload});
                return @unionInit(Action, field.name, payload);
            }
        }

        const peek = try reader.peek(len - 1);
        print("  0x{X:0>2}: <- UNKNOWN ACTION ({X})\n", .{ opcode, peek });

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
};

const Stop = struct {
    pos: Vec3,
    unk1: u16,
    unk2: u16,
};

const GetBaseInfo = struct {
    unk1: u8,
    unk2: u8,
    null: u8,
};
