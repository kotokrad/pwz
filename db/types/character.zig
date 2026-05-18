const std = @import("std");

const Vec3 = @import("../../protocol/types.zig").Vec3;
const BoundedArray = @import("../../utils/utils.zig").BoundedArray;
const String = @import("../../utils/utils.zig").String;

pub const CharacterId = u32;
pub const SkillId = u32;

const DateTime = u32;

pub const Skill = struct {
    id: SkillId = undefined,
    skill_id: u16,
    char_id: CharacterId,
    level: u16,
    null: u8 = 0,
};

/// When `invalid` flags set, client ignores the RoleWorldInfo packet
/// They might depend on other flags? Only tested in isolation
pub const CharacterFlags = packed struct(u32) {
    // zig fmt: off
    unk00: bool         = false,
    unk01: bool         = false,
    gm_invis: bool      = false,
    unk03: bool         = false,
    unk04: bool         = false,
    unk05: bool         = false,
    unk06: bool         = false,
    unk07: bool         = false,
    invalid08: bool     = false,
    in_combat: bool     = false,
    unk10: bool         = false,
    invalid11: bool     = false,
    invalid12: bool     = false,
    is_pk: bool         = true,
    unk14: bool         = false,
    invalid15: bool     = false,
    unk16: bool         = false,
    unk17: bool         = false,
    invalid18: bool     = false,
    in_faction: bool    = false, // probably?
    unk20: bool         = false,
    is_fashion: bool    = false,
    is_gm: bool         = true,
    is_pvp: bool        = false,
    invalid24: bool     = false,
    invalid25: bool     = false,
    is_flagged: bool    = false,
    unk27: bool         = false,
    is_flying: bool     = false,
    is_meditating: bool = false,
    invalid30: bool     = false,
    is_dead: bool       = false,
    // zig fmt: on
};

pub const Character = struct {
    id: CharacterId = undefined,
    account_id: u32,

    // Base
    gender: u8 = 0,
    race: u8 = 1,
    class: u8 = 1,
    level: u16 = 0,
    cultivation: u16 = 0,
    name: String(16),
    custom_data: BoundedArray(u8, 256),
    // equipment: BoundedArray(u32, MAX_EQUIPMENT_ITEMS),
    is_active: bool = true,
    delete_time: DateTime = 0,
    create_time: DateTime = 0,
    lastlogin_time: DateTime = 12312311,
    position: Vec3,

    // Status
    hp: u32 = 0,
    hp_max: u32 = 0,
    mp: u32 = 0,
    mp_max: u32 = 0,
    experience: u32 = 0,
    spirit: u32 = 0,
    chi: u32 = 0,
    chi_max: u32 = 0,

    // NOTE: Combat stats are not implemented. Just skip them
    // and return hardcoded data in Updates->PlayerCombatStats
    // Though `run_speed` etc might be useful later
    //
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

    // Flags
    flags: CharacterFlags = .{},

    // World
    angle: u8 = 0,

    // Etc
    // skills: BoundedArray(Skill, MAX_SKILLS),

    ui_config: BoundedArray(u8, 512),

    pub const MAX_SKILLS = 32;
};

pub fn getExampleChar() !Character {
    var ui_config_buf: [512]u8 = undefined;
    return .{
        .account_id = 1,

        .race = 1,
        .class = 6,
        .level = 86,
        .name = try .fromSlice("Hallo"),

        .hp = 3000,
        .hp_max = 3000,
        .mp = 7000,
        .mp_max = 7000,
        .experience = 100_000,
        .spirit = 100_500_000,
        .chi = 299,
        .chi_max = 299,

        .custom_data = try .fromSlice(&.{
            // zig fmt: off
            0,112,0,16,138,128,163,0,62,0,62,0,50,145,137,0,44,0,102,
            118,128,128,128,113,128,131,128,128,128,128,128,128,128,
            128,128,112,139,128,128,128,115,128,74,0,51,0,93,1,48,0,
            149,136,128,128,124,128,128,149,136,128,128,124,128,128,
            45,0,68,0,128,128,128,128,128,128,128,128,128,128,128,128,
            42,0,58,0,133,125,115,169,57,0,130,172,80,0,77,0,83,0,91,
            83,126,132,52,0,119,119,128,128,59,0,128,128,8,1,58,1,210,
            0,186,0,84,2,177,1,181,1,0,0,242,244,248,255,17,17,17,255,
            17,17,17,255,17,17,17,255,21,21,21,255,19,18,19,255,18,17,
            18,255,0,0,0,0,242,244,248,255,123,110,110,110,117,128,0,0
            // zig fmt: on
        }),
        .create_time = 1_753_704_763,
        .lastlogin_time = 1_753_704_763,
        // .position = .{ .x = 111, .y = 40, .z = 40 }, // GM zone
        .position = .{ .x = 330, .y = 440, .z = 40 }, // 19

        .angle = 120,

        .ui_config = try .fromSlice(try std.fmt.hexToBytes(&ui_config_buf, "c2eb0b227801dbc3ccc0c0cec0c0f01f0b000a3330413188cd082280e0351083c441e01510038d00f3f9410240c002c43079109f15cae703718000641f082c076290b52036cc6c109bdf02e11e107f148c86c06808600f011360c6e100661f18c0ae6a988a9e81941dc4f80e54bec0ca18107d0d4840cb2b68d081c290c10848b03032448b1994382832093030fcf8efa808d20a62333078826967ab1886a2fcf4a2c45c05b7cc9cd462058d0a0b06cd9830471fffa098d49cd4dcd4bc921886e2d42297c492c4189fc4cafcd2921853060b5373bdccbc4c06d13f7fa2c5166cae615800a443d4575583cc0599ceb0b946f40d9fadc49abfd1620e25968ae03214ec3a700483ddcf08212114d0c9405d4002a21d9d03f2104406e277089b5a8e03068807d09189c7cb181a7ecc65e885d2207f1840d93f7a64445f083828820a7c105be0e96c05a06f151c19181aec99806e83b90ea4895a000078ab7ae4")),
    };
}
