const std = @import("std");

const DB = @import("db.zig").DB;
const character = @import("types/character.zig");
const inventory = @import("types/inventory.zig");

const Character = character.Character;
const Item = inventory.Item;
const EquipmentSlot = inventory.EquipmentSlot;

pub fn seed(db: *DB) !void {
    const account_id = try db.createAccount(try .init("qwer", "qwer"));

    const char = try Character.init("Hallo", account_id);
    const char_id = try db.createCharacter(char);

    const items = try exampleItems(char_id);
    for (items) |item| {
        _ = try db.createItem(item);
    }

    _ = try db.createSkill(.{ .skill_id = 167, .char_id = char_id, .level = 1 });
    _ = try db.createSkill(.{ .skill_id = 234, .char_id = char_id, .level = 1 });
    _ = try db.createSkill(.{ .skill_id = 235, .char_id = char_id, .level = 1 });
    _ = try db.createSkill(.{ .skill_id = 1000, .char_id = char_id, .level = 1 });
    _ = try db.createSkill(.{ .skill_id = 1001, .char_id = char_id, .level = 1 });
    _ = try db.createSkill(.{ .skill_id = 1002, .char_id = char_id, .level = 1 });

    const second_account_id = try db.createAccount(try .init("qwe", "qwe"));

    const another_char = try Character.init("Another", second_account_id);
    _ = try db.createCharacter(another_char);
}

fn exampleItems(char_id: u32) ![21]Item {
    return .{
        // Inventory
        .{
            .char_id = char_id,
            .item_id = 2250,
            .inventory_type = .general,
            .slot = 1,
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{
                1, 0, 255, 0, 5,  0, 0, 0, 5, 0, 0,   0,  152, 8, 0,   0,  152, 8, 0, 0, 44, 0, 3, 0, 1, 0,
                0, 0, 13,  0, 0,  0, 0, 0, 0, 0, 98,  33, 0,   0, 5,   0,  0,   0, 9, 0, 0,  0, 0, 0, 0, 0,
                0, 0, 0,   0, 30, 0, 0, 0, 0, 0, 160, 65, 0,   0, 160, 64, 0,   0, 0, 0, 0,  0, 0, 0,
            }),
            .proc_type = 0,
            .expire_date = 0,
            .guid1 = 0,
            .guid2 = 0,
            .mask = 0,
        },

        .{
            .char_id = char_id,
            .item_id = 8543,
            .inventory_type = .general,
            .slot = 11,
            .count = 200,
            .max_count = 50000,
            .data = try .fromSlice(&.{
                0, 0, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0, 100, 0, 0,  0, 100, 0, 0, 0, 20, 0, 0, 0, 98, 33,
                0, 0, 1,   0,   0, 0, 0, 0, 0, 0, 0, 0, 0,   0, 15, 0, 0,   0, 0, 0, 0,  0, 0, 0, 0,  0,
            }),
            .proc_type = 0,
            .expire_date = 0,
            .guid1 = 0,
            .guid2 = 0,
            .mask = 0,
        },

        .{
            .char_id = char_id,
            .item_id = 2096,
            .inventory_type = .general,
            .slot = 12,
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{ 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 3, 0, 154, 68 }),
            .proc_type = 0,
            .expire_date = 0,
            .guid1 = 0,
            .guid2 = 0,
            .mask = 0,
        },

        // Equipment
        .{
            .char_id = char_id,
            .item_id = 14903,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.weapon),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{
                80,  0,   255, 0, 44,  0,  0,   0,  0,   0,  240, 0, 122, 18, 0,   0,   4,   41, 0,  0, 44,  0,
                4,   16,  87,  0, 97,  0,  110, 0,  100, 0,  101, 0, 114, 0,  101, 0,   114, 0,  0,  0, 0,   0,
                36,  1,   0,   0, 10,  0,  0,   0,  0,   0,  0,   0, 114, 1,  0,   0,   43,  2,  0,  0, 161, 2,
                0,   0,   172, 3, 0,   0,  16,  0,  0,   0,  0,   0, 64,  64, 0,   0,   0,   0,  2,  0, 18,  0,
                232, 24,  0,   0, 232, 24, 0,   0,  6,   0,  0,   0, 185, 33, 0,   0,   3,   0,  0,  0, 221, 35,
                0,   0,   118, 0, 0,   0,  218, 36, 0,   0,  165, 0, 0,   0,  134, 164, 0,   0,  32, 0, 0,   0,
                134, 164, 0,   0, 32,  0,  0,   0,  225, 70, 0,   0, 103, 0,  0,   0,   5,   0,  0,  0,
            }),
            .proc_type = 0,
            .expire_date = 0,
            .guid1 = 1_751_064_266,
            .guid2 = 16_784_156,
            .mask = 1_073_741_825,
        },

        .{
            .char_id = char_id,
            .item_id = 5094,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.head),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{
                31,  0,   255, 0,  50,  0,  0,   0,   0,   0,   0,   0,   100, 25,  0,   0,   248, 42,  0,  0,   36,
                0,   4,   16,  26, 4,   62, 4,   66,  4,   62,  4,   58,  4,   64,  4,   48,  4,   52,  4,  69,  0,
                0,   0,   0,   0,  0,   0,  0,   0,   0,   0,   100, 0,   0,   0,   0,   0,   0,   0,   0,  0,   0,
                0,   80,  0,   0,  0,   0,  0,   0,   0,   0,   0,   0,   0,   4,   0,   1,   0,   204, 7,  0,   0,
                204, 7,   0,   0,  204, 7,  0,   0,   204, 7,   0,   0,   8,   0,   0,   0,   117, 36,  0,  0,   3,
                0,   0,   0,   37, 38,  0,  0,   80,  0,   0,   0,   143, 34,  0,   0,   69,  0,   0,   0,  221, 161,
                0,   0,   26,  0,  0,   0,  221, 161, 0,   0,   26,  0,   0,   0,   221, 161, 0,   0,   26, 0,   0,
                0,   221, 161, 0,  0,   26, 0,   0,   0,   240, 70,  0,   0,   126, 0,   0,   0,   5,   0,  0,   0,
            }),
            .proc_type = 0,
            .expire_date = 0,
            .guid1 = 1_755_088_179,
            .guid2 = 16_785_187,
            .mask = 1_073_741_826,
        },

        .{
            .char_id = char_id,
            .item_id = 15001,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.neck),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{
                31,  0,   255, 0,  50,  0,  0,   0,   0,   0,   0,   0,   100, 25,  0,   0,   248, 42,  0,  0,   36,
                0,   4,   16,  26, 4,   62, 4,   66,  4,   62,  4,   58,  4,   64,  4,   48,  4,   52,  4,  69,  0,
                0,   0,   0,   0,  0,   0,  0,   0,   0,   0,   100, 0,   0,   0,   0,   0,   0,   0,   0,  0,   0,
                0,   80,  0,   0,  0,   0,  0,   0,   0,   0,   0,   0,   0,   4,   0,   1,   0,   204, 7,  0,   0,
                204, 7,   0,   0,  204, 7,  0,   0,   204, 7,   0,   0,   8,   0,   0,   0,   117, 36,  0,  0,   3,
                0,   0,   0,   37, 38,  0,  0,   80,  0,   0,   0,   143, 34,  0,   0,   69,  0,   0,   0,  221, 161,
                0,   0,   26,  0,  0,   0,  221, 161, 0,   0,   26,  0,   0,   0,   221, 161, 0,   0,   26, 0,   0,
                0,   221, 161, 0,  0,   26, 0,   0,   0,   240, 70,  0,   0,   126, 0,   0,   0,   5,   0,  0,   0,
            }),
            .proc_type = 0,
            .expire_date = 0,
            .guid1 = 1_755_753_355,
            .guid2 = 16_782_497,
            .mask = 1_073_741_828,
        },

        .{
            .char_id = char_id,
            .item_id = 1869,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.cape),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{
                67,  0,   255, 0, 0,   0, 0,   0,   0,   0,   0,   0, 43, 47, 0,   0,   84,  61, 0,   0, 36,  0,
                4,   18,  83,  0, 116, 0, 111, 0,   110, 0,   101, 0, 72, 0,  97,  0,   114, 0,  100, 0, 0,   0,
                0,   0,   134, 0, 0,   0, 0,   0,   0,   0,   0,   0, 0,  0,  0,   0,   0,   0,  0,   0, 0,   0,
                0,   0,   0,   0, 0,   0, 0,   0,   0,   0,   0,   0, 4,  0,  1,   0,   204, 7,  0,   0, 204, 7,
                0,   0,   204, 7, 0,   0, 204, 7,   0,   0,   8,   0, 0,  0,  40,  33,  0,   0,  0,   0, 128, 62,
                118, 36,  0,   0, 4,   0, 0,   0,   118, 36,  0,   0, 4,  0,  0,   0,   7,   71, 0,   0, 42,  0,
                0,   0,   2,   0, 0,   0, 221, 161, 0,   0,   26,  0, 0,  0,  221, 161, 0,   0,  26,  0, 0,   0,
                221, 161, 0,   0, 26,  0, 0,   0,   221, 161, 0,   0, 26, 0,  0,   0,
            }),
            .proc_type = 0,
            .expire_date = 0,
            .guid1 = 0,
            .guid2 = 0,
            .mask = 1_073_741_832,
        },

        .{
            .char_id = char_id,
            .item_id = 12670,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.shirt),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{
                60,  0,   2,   0,  0,  0,  0,   0,   0,  0,  0,   0,  171, 34, 0,   0,   188, 52, 0,   0,  36,  0,
                0,   0,   124, 0,  0,  0,  0,   0,   0,  0,  0,   0,  0,   0,  80,  0,   0,   0,  86,  4,  0,   0,
                86,  4,   0,   0,  86, 4,  0,   0,   86, 4,  0,   0,  86,  4,  0,   0,   4,   0,  1,   0,  223, 24,
                0,   0,   223, 24, 0,  0,  223, 24,  0,  0,  223, 24, 0,   0,  8,   0,   0,   0,  116, 34, 0,   0,
                80,  0,   0,   0,  76, 33, 0,   0,   3,  0,  0,   0,  114, 36, 0,   0,   5,   0,  0,   0,  123, 164,
                0,   0,   41,  0,  0,  0,  123, 164, 0,  0,  41,  0,  0,   0,  123, 164, 0,   0,  41,  0,  0,   0,
                123, 164, 0,   0,  41, 0,  0,   0,   26, 71, 0,   0,  48,  0,  0,   0,   3,   0,  0,   0,
            }),
            .proc_type = 16403,
            .expire_date = 0,
            .guid1 = 1_757_777_655,
            .guid2 = 16_785_180,
            .mask = 1_073_741_840,
        },

        .{
            .char_id = char_id,
            .item_id = 20950,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.belt),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{
                80,  0, 255, 0, 0,   0,  0, 0, 0,   0, 0, 0, 250, 100, 0, 0, 48,  117, 0, 0, 36,  0,  1, 0,
                0,   0, 0,   0, 0,   0,  0, 0, 172, 0, 0, 0, 0,   0,   0, 0, 100, 0,   0, 0, 100, 0,  0, 0,
                100, 0, 0,   0, 100, 0,  0, 0, 100, 0, 0, 0, 0,   0,   0, 0, 3,   0,   0, 0, 98,  37, 0, 0,
                90,  0, 0,   0, 76,  36, 0, 0, 1,   0, 0, 0, 149, 35,  0, 0, 72,  0,   0, 0,
            }),
            .proc_type = 19,
            .expire_date = 0,
            .guid1 = 1_757_532_150,
            .guid2 = 1_224_740_496,
            .mask = 1_073_741_856,
        },

        .{
            .char_id = char_id,
            .item_id = 5968,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.legs),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{
                73,  0,   255, 0,   41,  0,   0,   0,   0,   0,   113, 0,   107, 28,  0,   0,  24,  46, 0,  0,   36,
                0,   0,   0,   61,  1,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,  0,   0,  0,  222, 3,
                0,   0,   222, 3,   0,   0,   222, 3,   0,   0,   222, 3,   0,   0,   222, 3,  0,   0,  4,  0,   1,
                0,   225, 24,  0,   0,   225, 24,  0,   0,   225, 24,  0,   0,   225, 24,  0,  0,   8,  0,  0,   0,
                143, 34,  0,   0,   69,  0,   0,   0,   143, 34,  0,   0,   69,  0,   0,   0,  143, 34, 0,  0,   69,
                0,   0,   0,   121, 164, 0,   0,   33,  0,   0,   0,   121, 164, 0,   0,   33, 0,   0,  0,  121, 164,
                0,   0,   33,  0,   0,   0,   121, 164, 0,   0,   33,  0,   0,   0,   28,  71, 0,   0,  86, 0,   0,
                0,   4,   0,   0,   0,
            }),
            .proc_type = 0,
            .expire_date = 0,
            .guid1 = 1_751_143_809,
            .guid2 = 738_201_398,
            .mask = 1_073_741_888,
        },

        .{
            .char_id = char_id,
            .item_id = 5266,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.feet),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{
                76,  0,   255, 0,   42,  0,   0,   0,   0,   0,   117, 0,   228, 12,  0,   0,   64, 31,  0,  0,   36,
                0,   4,   22,  120, 0,   77,  0,   111, 0,   111, 0,   110, 0,   108, 0,   105, 0,  103, 0,  104, 0,
                116, 0,   64,  178, 18,  1,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,  0,   0,  0,   93,
                2,   0,   0,   93,  2,   0,   0,   93,  2,   0,   0,   93,  2,   0,   0,   93,  2,  0,   0,  4,   0,
                1,   0,   225, 24,  0,   0,   225, 24,  0,   0,   225, 24,  0,   0,   225, 24,  0,  0,   8,  0,   0,
                0,   143, 34,  0,   0,   69,  0,   0,   0,   143, 34,  0,   0,   69,  0,   0,   0,  143, 34, 0,   0,
                69,  0,   0,   0,   121, 164, 0,   0,   33,  0,   0,   0,   121, 164, 0,   0,   33, 0,   0,  0,   121,
                164, 0,   0,   33,  0,   0,   0,   121, 164, 0,   0,   33,  0,   0,   0,   28,  71, 0,   0,  61,  0,
                0,   0,   3,   0,   0,   0,
            }),
            .proc_type = 0,
            .expire_date = 0,
            .guid1 = 0,
            .guid2 = 0,
            .mask = 1_073_741_952,
        },

        .{
            .char_id = char_id,
            .item_id = 8356,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.wrists),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{
                77,  0,   255, 0,   43,  0,   0,   0,   0,  0,   119, 0,   101, 29,  0,   0,   212, 48,  0,   0,   36,
                0,   4,   22,  120, 0,   77,  0,   111, 0,  111, 0,   110, 0,   108, 0,   105, 0,   103, 0,   104, 0,
                116, 0,   106, 221, 63,  0,   0,   0,   0,  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   53,
                2,   0,   0,   53,  2,   0,   0,   53,  2,  0,   0,   53,  2,   0,   0,   53,  2,   0,   0,   4,   0,
                1,   0,   223, 24,  0,   0,   223, 24,  0,  0,   223, 24,  0,   0,   223, 24,  0,   0,   7,   0,   0,
                0,   125, 34,  0,   0,   205, 204, 76,  62, 77,  33,  0,   0,   6,   0,   0,   0,   123, 164, 0,   0,
                41,  0,   0,   0,   123, 164, 0,   0,   41, 0,   0,   0,   123, 164, 0,   0,   41,  0,   0,   0,   123,
                164, 0,   0,   41,  0,   0,   0,   28,  71, 0,   0,   115, 0,   0,   0,   5,   0,   0,   0,
            }),
            .proc_type = 0,
            .expire_date = 0,
            .guid1 = 1_755_503_770,
            .guid2 = 16_781_264,
            .mask = 1_073_742_080,
        },

        .{
            .char_id = char_id,
            .item_id = 6203,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.ring_left),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{
                78, 0,  255, 0, 0,  0, 0,  0, 0,  0, 0,  0, 59, 36, 0,  0, 64, 56, 0,  0,  36, 0,
                4,  16, 26,  4, 62, 4, 66, 4, 62, 4, 58, 4, 64, 4,  48, 4, 52, 4,  0,  0,  0,  0,
                64, 0,  0,   0, 0,  0, 0,  0, 0,  0, 0,  0, 0,  0,  0,  0, 0,  0,  0,  0,  0,  0,
                0,  0,  0,   0, 0,  0, 0,  0, 0,  0, 0,  0, 0,  0,  1,  0, 0,  0,  83, 34, 0,  0,
                6,  0,  0,   0,
            }),
            .proc_type = 0,
            .expire_date = 0,
            .guid1 = 0,
            .guid2 = 0,
            .mask = 1_073_743_360,
        },

        .{
            .char_id = char_id,
            .item_id = 6210,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.ring_right),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{
                78, 0,  255, 0, 0,  0,  0,  0, 0,  0, 0,  0, 55, 45, 0,  0, 184, 61, 0,   0,  36, 0,
                4,  16, 26,  4, 62, 4,  66, 4, 62, 4, 58, 4, 64, 4,  48, 4, 52,  4,  0,   0,  0,  0,
                92, 0,  0,   0, 0,  0,  0,  0, 0,  0, 0,  0, 0,  0,  0,  0, 0,   0,  0,   0,  0,  0,
                0,  0,  0,   0, 0,  0,  0,  0, 0,  0, 0,  0, 0,  0,  2,  0, 0,   0,  125, 35, 0,  0,
                24, 0,  0,   0, 82, 34, 0,  0, 3,  0, 0,  0,
            }),
            .proc_type = 0,
            .expire_date = 0,
            .guid1 = 1_755_494_744,
            .guid2 = 16_781_226,
            .mask = 1_073_743_360,
        },

        .{
            .char_id = char_id,
            .item_id = 8551,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.projectile),
            .count = 1,
            .max_count = 50000,
            .data = try .fromSlice(&.{
                0, 0, 255, 255, 0, 0, 0,  0, 0,   0,  0, 0, 100, 0, 0, 0, 100, 0, 0,  0, 20, 0,
                0, 0, 98,  33,  0, 0, 10, 0, 0,   0,  0, 0, 0,   0, 1, 0, 0,   0, 16, 0, 0,  0,
                0, 0, 0,   0,   1, 0, 0,  0, 230, 37, 0, 0, 1,   0, 0, 0,
            }),
            .proc_type = 0,
            .expire_date = 0,
            .guid1 = 0,
            .guid2 = 0,
            .mask = 1_073_743_872,
        },

        .{
            .char_id = char_id,
            .item_id = 24365,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.flyer),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{
                165, 2,  0,   0,   132, 3,  0, 0, 20, 0,  1, 0, 3, 0, 0, 0, 15, 0, 0, 0, 51, 51,
                83,  64, 154, 153, 201, 64, 3, 0, 87, 68,
            }),
            .proc_type = 8,
            .expire_date = 0,
            .guid1 = 1_753_777_767,
            .guid2 = 16_781_932,
            .mask = 4096,
        },

        .{
            .char_id = char_id,
            .item_id = 15803,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.fashion_legs),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{ 30, 0, 0, 0, 98, 12, 0, 0, 3, 0, 8, 255 }),
            .proc_type = 8,
            .expire_date = 0,
            .guid1 = 1_754_509_603,
            .guid2 = 16_782_616,
            .mask = 16384,
        },

        .{
            .char_id = char_id,
            .item_id = 15800,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.fashion_feet),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{ 30, 0, 0, 0, 66, 4, 0, 0, 3, 0, 0, 0 }),
            .proc_type = 8,
            .expire_date = 0,
            .guid1 = 1_754_138_307,
            .guid2 = 16_780_862,
            .mask = 32768,
        },

        .{
            .char_id = char_id,
            .item_id = 17602,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.tome),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{}),
            .proc_type = 0,
            .expire_date = 0,
            .guid1 = 0,
            .guid2 = 0,
            .mask = 262_144,
        },

        .{
            .char_id = char_id,
            .item_id = 26647,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.hp_charm),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{ 252, 138, 0, 0, 0, 0, 0, 63 }),
            .proc_type = 19,
            .expire_date = 0,
            .guid1 = 0,
            .guid2 = 0,
            .mask = 1_048_576,
        },

        .{
            .char_id = char_id,
            .item_id = 12817,
            .inventory_type = .equipment,
            .slot = @intFromEnum(EquipmentSlot.mp_charm),
            .count = 1,
            .max_count = 1,
            .data = try .fromSlice(&.{ 208, 184, 12, 0, 0, 0, 64, 63 }),
            .proc_type = 8,
            .expire_date = 0,
            .guid1 = 0,
            .guid2 = 0,
            .mask = 2_097_152,
        },
    };
}
