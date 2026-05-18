const std = @import("std");

pub fn EntityMap(comptime V: type, comptime start_id: u32) type {
    return struct {
        map: std.AutoHashMap(u32, V),
        next_id: u32 = start_id,
        // free_ids: std.ArrayList(u32) = .empty,

        const Self = @This();

        // pub const Id = @FieldType(V, "id");
        pub const is_entity_map = true;

        pub fn init(gpa: std.mem.Allocator) Self {
            return .{ .map = .init(gpa) };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
        }

        pub fn get(self: *Self, id: u32) ?*V {
            return self.map.getPtr(id);
        }

        pub fn create(self: *Self, item: V) !u32 {
            const id = self.getNextId();
            try self.map.put(id, item);
            self.map.getPtr(id).?.id = id;
            return id;
        }

        pub fn delete(self: *Self, id: u32) !void {
            // self.free_ids.append(self.gpa, id);
            self.map.remove(id);
        }

        fn getNextId(self: *Self) u32 {
            defer self.next_id += 1;
            return self.next_id;
        }

        // TODO: generations
        // fn getNextId(self: *Self) u32 {
        //     if (self.free_ids.pop()) |id| return id;
        //     defer self.next_id += 1;
        //     return self.next_id;
        // }
    };
}
