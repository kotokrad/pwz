const std = @import("std");
const print = std.debug.print;
const Writer = std.Io.Writer;

const codec = @import("../protocol/codec.zig");
const utils = @import("../protocol/utils.zig");
const Vec3 = @import("../world/utils.zig").Vec3;
const character = @import("../world/character.zig");

const FixedArray = utils.FixedArray;
const EndianTable = utils.EndianTable;
const copyShallow = utils.copyShallow;
const OctetsU32LE = codec.OctetsU32LE;
const VecU32LE = codec.VecU32LE;

// `Updates` are mapped to `subpackets` that server sends
// to the client in a `Container` packet
pub const Update = union(enum(u16)) {
    // zig fmt: off
    role_status_info: RoleStatusInfo       = 0x26,
    role_world_info: RoleWorldInfo         = 0x08,
    nearby_players: NearbyPlayers          = 0x04,
    server_config_info: ServerConfigInfo   = 0xCE,
    unknown_010b: Unknown010B              = 0x010B,
    safety_lock_status: SafetyLockStatus   = 0x00,
    enter_safe_zone: EnterSafeZone         = 0xA4,
    enter_pvp_zone: EnterPvpZone           = 0xA5,
    player_combat_stats: PlayerCombatStats = 0x32,
    inventory: Inventory                   = 0x2B,
    quest_inventory: QuestInventory        = 0x2A,
    money: Money                           = 0x52,
    skills: Skills                         = 0x5A,
    unknown_69: Unknown69                  = 0x69,
    // zig fmt: on

    fn deinit(self: *Update) void {
        switch (self) {
            inline else => |payload| {
                if (@hasDecl(@TypeOf(payload), "deinit")) payload.deinit();
            },
        }
    }

    pub fn write(self: Update, writer: *Writer) !void {
        switch (self) {
            inline else => |variant, tag| {
                const T = @TypeOf(variant);
                const opcode = @intFromEnum(tag);

                var buf: [4096]u8 = undefined;
                var fw = Writer.fixed(&buf);

                try fw.writeInt(u16, opcode, .little);
                try codec.serialize(T, &fw, variant);
                const payload = buf[0..fw.end];

                try writer.writeByte(0x22);
                try codec.writeCuint(writer, payload.len + codec.cuintSize(payload.len));
                try codec.writeCuint(writer, payload.len);
                try writer.writeAll(payload);

                print("    0x{x:0>4}: -> {s}\n", .{ opcode, utils.shortTypeName(T) });
            },
        }
    }
};

pub const RoleStatusInfo = struct {
    level: u16,
    cultivation: u16,
    hp: u32,
    hp_max: u32,
    mp: u32,
    mp_max: u32,
    experience: u32,
    spirit: u32,
    chi: u32,
    chi_max: u32,

    pub const endian: EndianTable(@This(), .little) = .{ .cultivation = .big };

    pub fn from(char: character.Character) RoleStatusInfo {
        return copyShallow(character.Character, RoleStatusInfo, char, .{});
    }
};

pub const RoleWorldInfo = struct {
    experience: u32,
    spirit: u32,
    char_id: u32,
    position: Vec3,
    crc: u16,
    custom_crc: u16,
    angle: u8,
    sec_level: u8,
    flags: character.CharacterFlags,

    pub fn from(char: character.Character) RoleWorldInfo {
        return copyShallow(character.Character, RoleWorldInfo, char, .{
            .char_id = char.char_id,
            .crc = 0x15ac,
            .custom_crc = 0,
            .sec_level = 0,
        });
    }
};

const NearbyPlayer = struct {
    char_id: u32,
    position: Vec3,
    crc: u16,
    custom_crc: u16,
    angle: u8,
    sec_level: u8,
    flags: character.CharacterFlags,

    pub fn from(char: character.Character) NearbyPlayer {
        return copyShallow(character.Character, NearbyPlayer, char, .{
            .char_id = char.char_id,
            .crc = 0x15ac,
            .custom_crc = 0,
            .sec_level = 0,
        });
    }
};

pub const NearbyPlayers = FixedArray(NearbyPlayer, 64);

pub const ServerConfigInfo = struct {
    world_id: u32,
    region_time: u32,
    precinct_time: u32,
    mall_time1: u32,
    mall_time2: u32,

    pub fn init() ServerConfigInfo {
        return .{
            .world_id = 1,
            .region_time = 1_259_906_307,
            .precinct_time = 1_260_265_858,
            .mall_time1 = 1_704_668_700,
            .mall_time2 = 1_252_391_288,
        };
    }
};

pub const Unknown010B = struct {};

pub const SafetyLockStatus = struct {
    enabled: u8,
    time_now: u32,
    lock_time: u32,

    pub fn init() SafetyLockStatus {
        return .{
            .enabled = 1,
            .time_now = 1761908466,
            .lock_time = 60,
        };
    }
};

pub const EnterSafeZone = struct {};
pub const EnterPvpZone = struct {};

pub const PlayerCombatStats = struct {
    data: [168]u8,

    // NOTE: It's supposed to be this:
    // free_stats: u32 = 0,
    // atk_lvl: u32 = 0,
    // def_lvl: u32 = 0,
    // crit_chance: u32 = 0,
    // crit_multiplier: u32 = 0,
    // vitality: u32 = 0,
    // intelligence: u32 = 0,
    // strength: u32 = 0,
    // dexterity: u32 = 0,
    // hp_regen: u32 = 0,
    // mp_regen: u32 = 0,
    // walk_speed: f32 = 0,
    // run_speed: f32 = 0,
    // swim_speed: f32 = 0,
    // flight_speed: f32 = 0,
    // accuracy: u32 = 0,
    // damage_low: u32 = 0,
    // damage_high: u32 = 0,
    // attack_speed: u32 = 0,
    // attack_range: f32 = 0,
    // addon_dmg_low_metal: u32 = 0,
    // addon_dmg_low_wood: u32 = 0,
    // addon_dmg_low_water: u32 = 0,
    // addon_dmg_low_fire: u32 = 0,
    // addon_dmg_low_earth: u32 = 0,
    // addon_dmg_high_metal: u32 = 0,
    // addon_dmg_high_wood: u32 = 0,
    // addon_dmg_high_water: u32 = 0,
    // addon_dmg_high_fire: u32 = 0,
    // addon_dmg_high_earth: u32 = 0,
    // magic_dmg_low: u32 = 0,
    // magic_dmg_high: u32 = 0,
    // resist_metal: u32 = 0,
    // resist_wood: u32 = 0,
    // resist_water: u32 = 0,
    // resist_fire: u32 = 0,
    // resist_earth: u32 = 0,
    // defense_physical: u32 = 0,
    // evasion: u32 = 0,
    // +
    // character.chi_max at the end?

    pub fn init() !PlayerCombatStats {
        var out: [168]u8 = undefined;
        _ = try std.fmt.hexToBytes(&out, "00000000000000000000000001000000000000000500000005000000050000000500000041000000370000000400000002000000000000406666a640000040400000a04028000000070000000b0000001e0000006666a2410000000000000000000000000000000000000000000000000000000000000000000000000000000001000000010000000200000002000000020000000200000002000000030000001e00000000000000");
        return .{ .data = out };
    }
};

const InventoryType = enum(u8) {
    general = 0,
    equipment = 1,
    fashion = 5,
};

pub const Inventory = struct {
    type: InventoryType,
    slot_count: u8 = 32,
    items: OctetsU32LE(VecU32LE(character.InventoryItem, 32)),

    pub fn from(inv_type: InventoryType, char: character.Character) !Inventory {
        _ = char;
        switch (inv_type) {
            .general => return .{ .type = inv_type, .items = .init(try .init(&.{})) },
            .fashion => return .{ .type = inv_type, .items = .init(try .init(&.{})) },
            .equipment => {
                return .{ .type = inv_type, .items = .init(try .init(&.{})) };
            },
        }
    }
};

pub const QuestInventory = struct {
    type: u8 = 2,
    slot_count: u8 = 32,
    items: OctetsU32LE([128]u8) = .{ .value = @splat(0xFF) },
};

pub const Money = struct {
    current: u32,
    max: u32,

    pub const endian: EndianTable(@This(), .big) = .{};
};

pub const Skills = VecU32LE(character.Skill, 32);

pub const Unknown69 = struct {
    data: [34]u8,

    pub fn init() !Unknown69 {
        var out: [34]u8 = undefined;
        _ = try std.fmt.hexToBytes(&out, "08000000000001000001000006000000010000005f04020000000000020000000000");
        return .{ .data = out };
    }
};
