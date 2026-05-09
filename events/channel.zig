const std = @import("std");
const Io = std.Io;
const ArrayList = std.ArrayList;

pub fn Owned(comptime T: type) type {
    return struct {
        arena: std.heap.ArenaAllocator,
        value: T,

        pub fn deinit(self: *@This()) void {
            self.arena.deinit();
        }
    };
}

pub fn Channel(comptime T: type) type {
    return struct {
        mutex: Io.Mutex,
        front: ArrayList(T),
        back: ArrayList(T),
        io: Io,

        const Self = @This();

        pub fn init(io: std.Io, back: []T, front: []T) Self {
            return .{
                .back = .initBuffer(back),
                .front = .initBuffer(front),
                .mutex = .init,
                .io = io,
            };
        }

        pub fn append(self: *Self, item: T) !void {
            try self.mutex.lock(self.io);
            defer self.mutex.unlock(self.io);
            try self.back.appendBounded(item);
        }

        pub fn appendMany(self: *Self, items: []const T) !void {
            try self.mutex.lock(self.io);
            defer self.mutex.unlock(self.io);
            try self.back.appendSliceBounded(items);
        }

        pub fn drain(self: *Self) ![]T {
            try self.mutex.lock(self.io);
            defer self.mutex.unlock(self.io);
            std.mem.swap(ArrayList(T), &self.back, &self.front);
            self.back.clearRetainingCapacity();
            return self.front.items;
        }
    };
}
