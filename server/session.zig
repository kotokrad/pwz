const std = @import("std");
const Io = std.Io;
const print = std.debug.print;

const packets = @import("../protocol/packets.zig");
const InPacket = packets.InPacket;
const OutPacket = packets.OutPacket;
const ServerError = packets.ServerError;
const ErrorCode = packets.ErrorCode;
const handleAuth = @import("./handlers/auth.zig").handleAuth;
const sendChallenge = @import("./handlers/auth.zig").sendChallenge;

const Stage = union(enum) {
    Auth,
    CharSelect,
    InWorld,
};

const LoginState = struct {
    challenge: ?[17]u8 = null,
    hash: ?[16]u8 = null,
    account_id: ?u32 = null,
    session_id: ?u32 = null,
    username: ?[]const u8 = null,
};

pub const Session = struct {
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator, // Lives the whole session
    scratch: std.mem.Allocator, // Reset after processing every request
    reader: *Io.Reader,
    writer: *Io.Writer,
    stage: Stage,
    login: LoginState = .{},
    encryptor: ?*Io.Writer = null,
    decryptor: ?*Io.Reader = null,
    compressor: ?*std.Io.Writer = null,
    outbox: *std.ArrayList(OutPacket),

    pub fn sendPendingPackets(self: Session) !void {
        const writer = self.encryptor orelse self.compressor orelse self.writer;
        for (self.outbox.items) |packet| {
            try packet.write(self.writer, self.scratch);
        }
        try writer.flush();
    }

    pub fn sendPacket(self: Session, packet: OutPacket) !void {
        const writer = self.encryptor orelse self.compressor orelse self.writer;
        try packet.write(writer, self.scratch);
        try writer.flush();
    }

    pub fn enqueuePacket(self: Session, packet: OutPacket) !void {
        try self.outbox.append(self.scratch, packet);
    }
};

pub fn start(io: Io, gpa: std.mem.Allocator, stream: Io.net.Stream) void {
    print("INFO: Client {f} connected\n", .{stream.socket.address});
    startSession(io, gpa, stream) catch |err| switch (err) {
        error.EndOfStream => print("INFO: Client {f} disconnected\n", .{stream.socket.address}),
        else => print("ERROR: Client {f} disconnected with error: {}", .{ stream.socket.address, err }),
    };
}

fn startSession(io: Io, gpa: std.mem.Allocator, stream: Io.net.Stream) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var scratch = std.heap.ArenaAllocator.init(gpa);
    errdefer scratch.deinit();
    var reader_buf: [4096]u8 = undefined;
    var writer_buf: [4096]u8 = undefined;
    var stream_reader = stream.reader(io, &reader_buf);
    var stream_writer = stream.writer(io, &writer_buf);
    // const reader = &stream_reader.interface;
    // const writer = &stream_writer.interface;
    var outbox: std.ArrayList(OutPacket) = try .initCapacity(gpa, 64);
    var session: Session = .{
        .gpa = gpa,
        .arena = arena.allocator(),
        .scratch = scratch.allocator(),
        .stage = .Auth,
        .reader = &stream_reader.interface,
        .writer = &stream_writer.interface,
        .outbox = &outbox,
    };
    try sendChallenge(&session);

    while (true) {
        defer _ = scratch.reset(.retain_capacity);
        print("parsing\n", .{});
        var packet_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        errdefer packet_arena.deinit();

        const reader = session.decryptor orelse session.reader;

        const packet = InPacket.read(reader, packet_arena.allocator()) catch |err| switch (err) {
            error.UnknownOpcode => {
                packet_arena.deinit();
                continue;
            },
            else => return err,
        };

        // Handle global packets
        switch (packet) {
            .KeepAlive => {
                defer packet_arena.deinit();
                try session.sendPacket(.{ .KeepAlive = .{ .data = 0xf0 } });
                continue;
            },
            else => {},
        }

        switch (session.stage) {
            .Auth => {
                defer packet_arena.deinit();
                try handleAuth(&session, packet);
            },
            .CharSelect => {
                defer packet_arena.deinit();
            },
            .InWorld => {},
        }

        print("sending\n", .{});
        try session.sendPendingPackets();
    }
}
