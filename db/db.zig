const std = @import("std");
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const StringHashMap = std.StringHashMap;

const BoundedArray = @import("../utils/utils.zig").BoundedArray;
const String = @import("../utils/utils.zig").String;
const EntityMap = @import("entity.zig").EntityMap;

const Account = @import("types/account.zig").Account;
const AccountId = @import("types/account.zig").AccountId;
const Character = @import("types/character.zig").Character;
const CharacterId = @import("types/character.zig").CharacterId;
const Item = @import("types/inventory.zig").Item;
const ItemId = @import("types/inventory.zig").ItemId;
const Skill = @import("types/character.zig").Skill;
const SkillId = @import("types/character.zig").SkillId;

const writeFile = @import("file.zig").writeFile;
const readFile = @import("file.zig").readFile;

pub const DB = struct {
    io: std.Io,
    gpa: std.mem.Allocator,

    accounts: EntityMap(Account, null),
    items: EntityMap(Item, 10000),
    characters: EntityMap(Character, null),
    skills: EntityMap(Skill, 1),

    // Calculated mappings
    account_by_username: StringHashMap(*Account) = undefined,
    chars_by_account: AutoHashMap(AccountId, ArrayList(*Character)) = undefined,
    items_by_char: AutoHashMap(CharacterId, ArrayList(*Item)) = undefined,
    skills_by_char: AutoHashMap(CharacterId, ArrayList(*Skill)) = undefined,

    pub fn init(gpa: std.mem.Allocator, io: std.Io) DB {
        return .{
            .gpa = gpa,
            .io = io,
            .accounts = .init(gpa),
            .items = .init(gpa),
            .skills = .init(gpa),
            .characters = .init(gpa),
            .account_by_username = .init(gpa),
            .chars_by_account = .init(gpa),
            .items_by_char = .init(gpa),
            .skills_by_char = .init(gpa),
        };
    }

    pub fn deinit(self: *DB) void {
        self.accounts.deinit();
        self.items.deinit();
        self.characters.deinit();
        self.skills.deinit();
        self.account_by_username.deinit();
        self.chars_by_account.deinit();
        self.items_by_char.deinit();
        self.skills_by_char.deinit();
    }

    // Create/Get
    // ----------------------------------------

    pub fn createAccount(self: *DB, account: Account) !AccountId {
        const next_id: u32 = @truncate(1024 + self.accounts.list.items.len * 16);
        const ptr = self.accounts.createWithId(account, next_id);
        try self.account_by_username.put(account.username.slice(), ptr);
        return ptr.id;
    }

    pub fn getAccount(self: *DB, id: AccountId) ?*Account {
        return self.accounts.get(id);
    }

    pub fn createCharacter(self: *DB, char: Character) !CharacterId {
        const next_id: u32 = @truncate(char.account_id + getCharactersByAccountId(self, char.account_id).len);
        const ptr = self.characters.createWithId(char, next_id);
        var account = try self.chars_by_account.getOrPutValue(char.account_id, .empty);
        try account.value_ptr.append(self.gpa, ptr);
        return ptr.id;
    }

    pub fn getCharacter(self: *DB, id: CharacterId) ?*Character {
        return self.characters.get(id);
    }

    pub fn createItem(self: *DB, item: Item) !ItemId {
        const ptr = self.items.create(item);
        var char = try self.items_by_char.getOrPutValue(item.char_id, .empty);
        try char.value_ptr.append(self.gpa, ptr);
        return ptr.id;
    }

    pub fn getItem(self: *DB, id: ItemId) ?*Item {
        return self.items.get(id);
    }

    pub fn createSkill(self: *DB, skill: Skill) !SkillId {
        const ptr = self.skills.create(skill);
        var char = try self.skills_by_char.getOrPutValue(skill.char_id, .empty);
        try char.value_ptr.append(self.gpa, ptr);
        return ptr.id;
    }

    pub fn getSkill(self: *DB, id: SkillId) ?*Item {
        return self.skills.get(id);
    }

    // Mappings
    // ----------------------------------------

    pub fn getAccountByUsername(self: *DB, username: []const u8) ?Account {
        return if (self.account_by_username.get(username)) |result| result.* else null;
    }

    pub fn getCharactersByAccountId(self: *DB, id: AccountId) BoundedArray(Character, Account.MAX_CHARACTERS) {
        const maybe_result = self.chars_by_account.get(id);
        if (maybe_result) |result| {
            return deref(Character, result.items, Account.MAX_CHARACTERS);
        }
        return .{};
    }

    pub fn getItemsByCharId(self: *DB, id: CharacterId) BoundedArray(Item, Item.MAX_GENERAL_ITEMS) {
        const maybe_result = self.items_by_char.get(id);
        if (maybe_result) |result| {
            return deref(Item, result.items, Item.MAX_GENERAL_ITEMS);
        }
        return .{};
    }

    pub fn getSkillByCharId(self: *DB, id: CharacterId) BoundedArray(Skill, Character.MAX_SKILLS) {
        const maybe_result = self.skills_by_char.get(id);
        if (maybe_result) |result| {
            return deref(Skill, result.items, Character.MAX_SKILLS);
        }
        return .{};
    }

    // Persistence
    // ----------------------------------------

    pub fn load(self: *DB) !void {
        inline for (@typeInfo(DB).@"struct".fields) |f| {
            if (!@hasDecl(f.type, "is_entity_map")) continue;

            std.debug.print("INFO: loading {s}...", .{f.name});

            var entity_map: f.type = .init(self.gpa);
            errdefer entity_map.deinit();
            const path = std.fmt.comptimePrint("data/{s}.txt", .{f.name});
            const data = try std.Io.Dir.cwd().readFileAlloc(self.io, path, self.gpa, .unlimited);
            defer self.gpa.free(data);
            const next_id = try readFile(@FieldType(f.type, "map"), &entity_map.map, data);
            entity_map.next_id = next_id;
            @field(self, f.name) = entity_map;
            std.debug.print("done.\n", .{});
        }

        std.debug.print("INFO: generating mappings...", .{});
        // Username -> *Account
        var accounts = self.accounts.map.valueIterator();
        self.account_by_username.clearRetainingCapacity();
        while (accounts.next()) |account| {
            try self.account_by_username.put(account.username.slice(), account);
        }

        // AccountId -> []*Character
        var chars = self.characters.map.valueIterator();
        self.chars_by_account.clearRetainingCapacity();
        while (chars.next()) |char| {
            const account = try self.chars_by_account.getOrPutValue(char.account_id, .empty);
            try account.value_ptr.append(self.gpa, char);
        }

        // CharacterId -> []*Item
        var items = self.items.map.valueIterator();
        self.items_by_char.clearRetainingCapacity();
        while (items.next()) |item| {
            const char = try self.items_by_char.getOrPutValue(item.char_id, .empty);
            try char.value_ptr.append(self.gpa, item);
        }

        // CharacterId -> []*Skill
        var skills = self.skills.map.valueIterator();
        self.skills_by_char.clearRetainingCapacity();
        while (skills.next()) |skill| {
            const char = try self.skills_by_char.getOrPutValue(skill.char_id, .empty);
            try char.value_ptr.append(self.gpa, skill);
        }
        std.debug.print("done.\n", .{});
    }

    pub fn save(self: *DB) !void {
        inline for (@typeInfo(DB).@"struct".fields) |f| {
            if (!@hasDecl(f.type, "is_entity_map")) continue;

            std.debug.print("INFO: saving {s}...", .{f.name});

            const path = std.fmt.comptimePrint("data/{s}.txt", .{f.name});
            const file = try std.Io.Dir.cwd().createFile(self.io, path, .{});
            var writer_buf: [512]u8 = undefined;
            var writer = file.writer(self.io, &writer_buf);
            try writeFile(@FieldType(f.type, "map"), &writer.interface, @field(self, f.name).map);
            try writer.interface.flush();
            std.debug.print("done.\n", .{});
        }
    }
};

fn deref(comptime T: type, slice: []*T, comptime cap: usize) BoundedArray(T, cap) {
    var result: BoundedArray(T, cap) = .{};
    for (slice) |p| result.append(p.*) catch {};
    return result;
}
