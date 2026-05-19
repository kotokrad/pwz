const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const Reader = std.Io.Reader;

const channel = @import("channel.zig");
const codec = @import("../protocol/codec.zig");
const utils = @import("../utils/utils.zig");
const Vec3 = @import("../protocol/types.zig").Vec3;
const SessionId = @import("../world/world.zig").SessionId;

const c = utils.term.c;
const r = utils.term.r;
const shortTypeName = utils.shortTypeName;
const Channel = channel.Channel;

/// `Actions` are mapped to `subpackets` that server receives in a `Gamedata` packet.
/// They are `fire and forget`, and will be processed in the game loop
/// without blocking the session thread.
/// Server may respond with `Update` packets that will be aggregated
/// and sent in one `Container` packet and the end of the tick.
/// (but for now server responds immediately)
///
/// We have to send it together with the session id
pub const Action = struct { SessionId, ActionPayload };

pub const ActionPayload = union(enum(u16)) {
    // zig fmt: off
    move: Move                           = 0x00,
    stop: Stop                           = 0x07,
    respawn: Respawn                     = 0x04,
    get_base_info: GetBaseInfo           = 0x27,
    gm_teleport: GmTeleport              = 0x13,
    stop_meditation: StopMeditation      = 0x2F,
    enter_dungeon: EnterDungeon          = 0x56,
    move_item: MoveItem                  = 0x0C,
    move_equipment: MoveEquipment        = 0x10,
    take_off_equipment: TakeOffEquipment = 0x11,
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
                // const hex = reader.buffered();
                const payload = try codec.deserialize(T, reader, arena);
                print("{s}<- 0x{x:0>2}: {s}{s}\n", .{ c(4), opcode, shortTypeName(T), r() });
                // print("      hex: {X}\n", .{hex});
                // print("      {any}\n", .{payload});
                if (reader.bufferedLen() > 0) {
                    print("WARNING: [Actions] {any} has some leftover data: {X}\n", .{ T, reader.buffered() });
                }
                return @unionInit(ActionPayload, field.name, payload);
            }
        }

        print("{s}<- 0x{X:0>2}:{s} UNKNOWN ACTION ({X})\n", .{ c(4), opcode, r(), reader.buffered() });

        reader.toss(payload_len);
        return error.UnknownOpcode;
    }
};

const MoveFlags = packed struct(u8) {
    is_walking: bool = true,
    falling1: u1 = 0, // ??
    falling2: u1 = 0, // ??
    is_jumping: bool = false,
    unk3: u1 = 0,
    always_on: u1 = 1,
    is_flying: bool = false,
    unk4: u1 = 0,
};

const Move = struct {
    pos: Vec3,
    dest: Vec3,
    unk1: u16,
    unk2: u16,
    flags: MoveFlags,
    counter: u16,
};

const Stop = struct {
    pos: Vec3,
    unk1: u8,
    unk2: u8,
    angle: u8,
    flags: MoveFlags,
    counter: u16,
    unk5: u8,
    unk6: u8,
};

const GetBaseInfo = struct {
    unk1: u8,
    unk2: u8,
    null: u8,
};

const GmTeleport = struct {
    pos: Vec3,
};

const StopMeditation = struct {};
const Respawn = struct {};

// 0D0000006B000000
const EnterDungeon = struct {
    unk_id: u32,
    dungeon_id: u32, // 19lvl ids are 105-106-107
};

const MoveItem = struct {
    slot_from: u8,
    slot_to: u8,
};

const MoveEquipment = struct {
    slot_from: u8,
    slot_to: u8,
};

const TakeOffEquipment = struct {
    slot_from: u8,
    slot_to: u8,
};
