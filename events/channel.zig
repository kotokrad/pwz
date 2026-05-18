const std = @import("std");
const Io = std.Io;
const ArrayList = std.ArrayList;

pub fn Channel(comptime T: type) type {
    return struct {
        io: Io,
        gpa: std.mem.Allocator,
        mutex: Io.Mutex,
        front: ArrayList(T),
        back: ArrayList(T),

        const Self = @This();

        pub fn init(io: std.Io, gpa: std.mem.Allocator, buf_len: usize) !Self {
            const back = try gpa.alloc(T, buf_len);
            const front = try gpa.alloc(T, buf_len);
            return .{
                .io = io,
                .gpa = gpa,
                .mutex = .init,
                .back = .initBuffer(back),
                .front = .initBuffer(front),
            };
        }

        pub fn deinit(self: *Self) void {
            self.gpa.free(self.back);
            self.gpa.free(self.front);
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
