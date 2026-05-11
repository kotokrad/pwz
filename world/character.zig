const std = @import("std");

const Vec3 = @import("utils.zig").Vec3;
const FixedArray = @import("../protocol/utils.zig").FixedArray;
const String = @import("../protocol/utils.zig").String;

const DateTime = u32;
const CustomData = FixedArray(u8, 256);

pub const InventoryItem = struct {
    slot: u32,
    id: u32,
    expire_date: u32,
    proc_type: u32,
    count: u32,
    guid_or_unk: u16,
    data: FixedArray(u8, 256),
};

pub const EquipmentSlot = enum(u32) {
    // zig fmt: off
    weapon        = 0,
    head          = 1,
    neck          = 2,
    cape          = 3,
    shirt         = 4,
    belt          = 5,
    legs          = 6,
    feet          = 7,
    wrists        = 8,
    ring_left     = 9,
    ring_right    = 10,
    projectile    = 11,
    flyer         = 12,
    fashion_top   = 13,
    fashion_legs  = 14,
    fashion_feet  = 15,
    fashion_arms  = 16,
    utility_charm = 17,
    tome          = 18,
    emoji_set     = 19,
    hp_charm      = 20,
    mp_charm      = 21,
    // zig fmt: on
};

pub const EquipmentItem = struct {
    id: u32,
    slot: EquipmentSlot,
    count: u32,
    max_count: u32,
    data: FixedArray(u8, 256),
    proc_type: u32,
    expire_date: u32,
    guid1: u32,
    guid2: u32,
    mask: u32,
};

pub const Skill = struct {
    id: u16,
    level: u16,
    null: u8 = 0,
};

pub const CharacterFlags = packed struct(u32) {
    unk0: u10 = 0,
    in_faction: bool = false,
    unk1: u1 = 0,
    is_fashion: bool = false,
    is_gm: bool = false,
    is_pvp: bool = false,
    unk2: u10 = 0,
    unk_half_invis: bool = false,
    unk3: u6 = 0,
};

pub const Character = struct {
    // Base
    char_id: u8,
    gender: u8 = 0,
    race: u8 = 1,
    class: u8 = 1,
    level: u16 = 0,
    cultivation: u16 = 0,
    name: String,
    custom_data: CustomData,
    equipment: FixedArray(EquipmentItem, 22),
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

    // Combat stats
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
    skills: FixedArray(Skill, 32),

    ui_config: FixedArray(u8, 512),
};

pub fn getExampleChar() !Character {
    var ui_config_buf: [512]u8 = undefined;
    return .{
        .char_id = 123,
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
        .chi = 50,
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
        .equipment = try .fromSlice(&.{
            .{
                .id = 14903,
                .slot = EquipmentSlot.weapon,
                .count = 1,
                .max_count = 1,
                .data = try .fromSlice(&.{
                    // zig fmt: off
                    80,0,255,0,44,0,0,0,0,0,240,0,122,18,0,0,4,41,0,0,44,0,
                    4,16,87,0,97,0,110,0,100,0,101,0,114,0,101,0,114,0,0,0,
                    0,0,36,1,0,0,10,0,0,0,0,0,0,0,114,1,0,0,43,2,0,0,161,2,
                    0,0,172,3,0,0,16,0,0,0,0,0,64,64,0,0,0,0,2,0,18,0,232,
                    24,0,0,232,24,0,0,6,0,0,0,185,33,0,0,3,0,0,0,221,35,0,
                    0,118,0,0,0,218,36,0,0,165,0,0,0,134,164,0,0,32,0,0,0,
                    134,164,0,0,32,0,0,0,225,70,0,0,103,0,0,0,5,0,0,0,
                    // zig fmt: on
                }),
                .proc_type = 0,
                .expire_date = 0,
                .guid1 = 1_751_064_266,
                .guid2 = 16_784_156,
                .mask = 1_073_741_825,
            },
        }),
        .create_time = 1_753_704_763,
        .lastlogin_time = 1_753_704_763,
        // .position = .{ .x = 197.0, .y = 197.0, .z = 68.156 },
        .position = .{ .x = 3_305_352_214, .y = 3_306_588_949, .z = 1_143_469_817 },

        .angle = 120,

        .skills = try .fromSlice(&.{
            Skill{ .id = 167, .level = 1 },
            Skill{ .id = 234, .level = 1 },
            Skill{ .id = 235, .level = 1 },
        }),

        .ui_config = try .fromSlice(try std.fmt.hexToBytes(&ui_config_buf, "c2eb0b227801dbc3ccc0c0cec0c0f01f0b000a3330413188cd082280e0351083c441e01510038d00f3f9410240c002c43079109f15cae703718000641f082c076290b52036cc6c109bdf02e11e107f148c86c06808600f011360c6e100661f18c0ae6a988a9e81941dc4f80e54bec0ca18107d0d4840cb2b68d081c290c10848b03032448b1994382832093030fcf8efa808d20a62333078826967ab1886a2fcf4a2c45c05b7cc9cd462058d0a0b06cd9830471fffa098d49cd4dcd4bc921886e2d42297c492c4189fc4cafcd2921853060b5373bdccbc4c06d13f7fa2c5166cae615800a443d4575583cc0599ceb0b946f40d9fadc49abfd1620e25968ae03214ec3a700483ddcf08212114d0c9405d4002a21d9d03f2104406e277089b5a8e03068807d09189c7cb181a7ecc65e885d2207f1840d93f7a64445f083828820a7c105be0e96c05a06f151c19181aec99806e83b90ea4895a000078ab7ae4")),
    };
}
