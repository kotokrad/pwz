const std = @import("std");

const BoundedArray = @import("../../utils/utils.zig").BoundedArray;
const String = @import("../../utils/utils.zig").String;

pub const ItemId = u32;
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

pub const InventoryType = enum(u8) {
    general = 0,
    equipment = 1,
    fashion = 5,
};

pub const Item = struct {
    id: ItemId = undefined,
    char_id: u32,
    item_id: u32,
    inventory_type: InventoryType,
    slot: u32,
    count: u32,
    max_count: u32,
    data: BoundedArray(u8, 256),
    proc_type: u32,
    expire_date: u32,
    guid1: u32,
    guid2: u32,
    mask: u32,

    pub const MAX_GENERAL_ITEMS = 32;
    pub const MAX_EQUIPMENT_ITEMS = 22;
    pub const MAX_FASHION_ITEMS = 8;
};
