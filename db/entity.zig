const std = @import("std");

pub fn EntityMap(comptime T: type, comptime start_id: ?u32) type {
    return struct {
        gpa: std.mem.Allocator,
        map: std.AutoHashMap(u32, T),
        list: std.ArrayList(*T),
        next_id: u32 = start_id orelse 0,

        const Self = @This();

        // pub const Id = @FieldType(T, "id");
        pub const is_entity_map = true;

        pub fn init(gpa: std.mem.Allocator) Self {
            return .{ .gpa = gpa, .map = .init(gpa), .list = .empty };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
            self.list.deinit(self.gpa);
        }

        pub fn get(self: *Self, id: u32) ?*T {
            return self.map.getPtr(id);
        }

        pub fn create(self: *Self, item: T) *T {
            if (start_id == null) @compileError("Use createWithId instead");
            const id = self.getNextId();

            self.map.put(id, item) catch {
                std.debug.panic("The system is dying anyway", .{});
            };
            const ptr = self.map.getPtr(id).?;
            ptr.id = id;
            self.list.append(self.gpa, ptr) catch {
                std.debug.panic("The system is dying anyway", .{});
            };
            return ptr;
        }

        pub fn createWithId(self: *Self, item: T, id: u32) *T {
            self.map.put(id, item) catch {
                std.debug.panic("The system is dying anyway", .{});
            };
            const ptr = self.map.getPtr(id).?;
            ptr.id = id;
            self.list.append(self.gpa, ptr) catch {
                std.debug.panic("The system is dying anyway", .{});
            };
            return ptr;
        }

        pub fn delete(self: *Self, id: u32) !void {
            self.map.remove(id);
        }

        fn getNextId(self: *Self) u32 {
            defer self.next_id += 1;
            return self.next_id;
        }
    };
}
