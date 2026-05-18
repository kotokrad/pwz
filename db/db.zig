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
    mutex: std.Io.Mutex = .init,

    accounts: EntityMap(Account, 1),
    items: EntityMap(Item, 10000),
    characters: EntityMap(Character, 1),
    skills: EntityMap(Skill, 1),

    // Calculated mappings
    account_by_username: StringHashMap(*Account) = undefined,
    chars_by_account: AutoHashMap(AccountId, ArrayList(*Character)) = undefined,
    items_by_char: AutoHashMap(CharacterId, ArrayList(*Item)) = undefined,
    skills_by_char: AutoHashMap(CharacterId, ArrayList(*Skill)) = undefined,

    pub fn load(self: *DB, gpa: std.mem.Allocator) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        inline for (@typeInfo(DB).@"struct".fields) |f| {
            if (!@hasDecl(f.type, "is_entity_map")) continue;

            std.debug.print("INFO: loading {s}...", .{f.name});

            var entity_map: f.type = .init(gpa);
            errdefer entity_map.deinit();
            const path = std.fmt.comptimePrint("data/{s}.txt", .{f.name});
            const data = try std.Io.Dir.cwd().readFileAlloc(self.io, path, gpa, .unlimited);
            defer gpa.free(data);
            const next_id = try readFile(@FieldType(f.type, "map"), &entity_map.map, data);
            entity_map.next_id = next_id;
            @field(self, f.name) = entity_map;
            std.debug.print("done.\n", .{});
        }

        std.debug.print("INFO: generating mappings...", .{});
        // Username -> *Account
        self.account_by_username = .init(gpa);
        errdefer self.account_by_username.deinit();
        var accounts = self.accounts.map.valueIterator();
        while (accounts.next()) |account| {
            try self.account_by_username.put(account.username.slice(), account);
        }

        // AccountId -> []*Character
        self.chars_by_account = .init(gpa);
        errdefer self.chars_by_account.deinit();
        var chars = self.characters.map.valueIterator();
        while (chars.next()) |char| {
            const account = try self.chars_by_account.getOrPutValue(char.account_id, .empty);
            try account.value_ptr.append(gpa, char);
        }

        // CharacterId -> []*Item
        self.items_by_char = .init(gpa);
        errdefer self.items_by_char.deinit();
        var items = self.items.map.valueIterator();
        while (items.next()) |item| {
            const char = try self.items_by_char.getOrPutValue(item.char_id, .empty);
            try char.value_ptr.append(gpa, item);
        }

        // CharacterId -> []*Skill
        self.skills_by_char = .init(gpa);
        errdefer self.skills_by_char.deinit();
        var skills = self.skills.map.valueIterator();
        while (skills.next()) |skill| {
            const char = try self.skills_by_char.getOrPutValue(skill.char_id, .empty);
            try char.value_ptr.append(gpa, skill);
        }
        std.debug.print("done.\n", .{});
    }

    pub fn save(self: *DB) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
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

    pub fn getAccount(self: *DB, id: AccountId) ?*Account {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        return self.accounts.get(id);
    }

    pub fn getCharacter(self: *DB, id: CharacterId) ?*Character {
        self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        return self.characters.get(id);
    }

    pub fn getItem(self: *DB, id: ItemId) ?*Item {
        self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        return self.items.get(id);
    }

    pub fn getSkill(self: *DB, id: SkillId) ?*Item {
        self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        return self.skills.get(id);
    }

    pub fn getAccountByUsername(self: *DB, username: []const u8) !?*Account {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        return self.account_by_username.get(username);
    }

    pub fn getCharactersByAccountId(self: *DB, id: AccountId) !BoundedArray(Character, Account.MAX_CHARACTERS) {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        const maybe_result = self.chars_by_account.get(id);
        if (maybe_result) |result| {
            return try deref(Character, result.items, Account.MAX_CHARACTERS);
        }
        return .{};
    }

    pub fn getItemsByCharId(self: *DB, id: CharacterId) !BoundedArray(Item, Item.MAX_GENERAL_ITEMS) {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        const maybe_result = self.items_by_char.get(id);
        if (maybe_result) |result| {
            return try deref(Item, result.items, Item.MAX_GENERAL_ITEMS);
        }
        return .{};
    }

    pub fn getSkillByCharId(self: *DB, id: CharacterId) !BoundedArray(Skill, Character.MAX_SKILLS) {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        const maybe_result = self.skills_by_char.get(id);
        if (maybe_result) |result| {
            return try deref(Skill, result.items, Character.MAX_SKILLS);
        }
        return .{};
    }
};

fn deref(comptime T: type, slice: []*T, comptime cap: usize) !BoundedArray(T, cap) {
    var result: BoundedArray(T, cap) = .{};
    for (slice) |p| try result.append(p.*);
    return result;
}
