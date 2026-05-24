const std = @import("std");
const Io = std.Io;
const ArrayList = std.ArrayList;

pub fn Reply(comptime T: type) type {
    return struct {
        done: Io.Event = .waiting,
        result: T = undefined,

        const Self = @This();

        pub fn set(self: *Self, io: Io, result: T) void {
            self.result = result;
            self.done.set(io);
        }

        pub fn await(self: *Self, io: Io) !T {
            try self.done.wait(io);
            return self.result;
        }
    };
}

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

        pub fn send(self: *Self, item: T) !void {
            try self.mutex.lock(self.io);
            defer self.mutex.unlock(self.io);
            try self.back.appendBounded(item);
        }

        pub fn sendMany(self: *Self, items: []const T) !void {
            try self.mutex.lock(self.io);
            defer self.mutex.unlock(self.io);
            try self.back.appendSliceBounded(items);
        }

        pub fn request(self: *Self, comptime R: type, comptime tag: std.meta.Tag(T), init_payload: @FieldType(T, @tagName(tag))) !R {
            var payload = init_payload;
            var reply: Reply(R) = .{};
            payload.reply = &reply;
            try self.send(@unionInit(T, @tagName(tag), payload));
            const result = try reply.await(self.io);
            return result;
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
