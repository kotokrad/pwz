const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const Io = std.Io;

const Rc4Writer = @import("utils/rc4.zig").Rc4Writer;
const Rc4Reader = @import("utils/rc4.zig").Rc4Reader;
const MppcWriter = @import("utils/mppc.zig").MppcWriter;
const packets = @import("../protocol/packets.zig");
const InPacket = packets.InPacket;
const OutPacket = packets.OutPacket;
const handleAuth = @import("./handlers/auth.zig").handleAuth;
const sendChallenge = @import("./handlers/auth.zig").sendChallenge;

const Stage = union(enum) {
    auth,
    char_select,
    in_world,
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
        const writer = self.compressor orelse self.writer;
        for (self.outbox.items) |packet| {
            try packet.write(writer, self.scratch);
            // TODO: use ring buffer or something
            _ = self.outbox.orderedRemove(0);
        }
        try writer.flush();
    }

    pub fn sendPacket(self: Session, packet: OutPacket) !void {
        try packet.write(self.writer, self.scratch);
        try self.writer.flush();
    }

    pub fn enqueuePacket(self: Session, packet: OutPacket) !void {
        try self.outbox.append(self.scratch, packet);
    }

    pub fn enableDecryption(self: *Session, username: []u8, hash: [16]u8, sm_key: [16]u8) !void {
        const buf = try self.arena.alloc(u8, 4096);
        var decryptor = try self.arena.create(Rc4Reader);
        decryptor.* = .init(self.reader, buf, .{
            .username = username,
            .hash = hash,
            .key = sm_key,
        });
        self.decryptor = &decryptor.reader;
    }

    pub fn enableEncryption(self: *Session, username: []const u8, hash: [16]u8, cm_key: [16]u8) !void {
        const buf = try self.arena.alloc(u8, 4096);
        var encryptor = try self.arena.create(Rc4Writer);
        encryptor.* = .init(self.writer, buf, .{
            .username = username,
            .hash = hash,
            .key = cm_key,
        });
        self.encryptor = &encryptor.writer;
    }

    pub fn enableCompression(self: *Session) !void {
        // The buffer should be large enough to fit one packet
        const buf = try self.arena.alloc(u8, 4096);
        var compressor = try self.arena.create(MppcWriter);
        assert(self.encryptor != null);
        compressor.* = .init(self.encryptor.?, buf);
        self.compressor = &compressor.writer;
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
        .stage = .auth,
        .reader = &stream_reader.interface,
        .writer = &stream_writer.interface,
        .outbox = &outbox,
    };
    try sendChallenge(&session);

    while (true) {
        defer _ = scratch.reset(.retain_capacity);
        print("parsing\n", .{});
        var packet_arena = std.heap.ArenaAllocator.init(gpa);
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
            .keep_alive => {
                defer packet_arena.deinit();
                try session.sendPacket(.{ .keep_alive = .{ .data = 0xf0 } });
                continue;
            },
            else => {},
        }

        switch (session.stage) {
            .auth => {
                defer packet_arena.deinit();
                try handleAuth(&session, packet);
            },
            .char_select => {
                defer packet_arena.deinit();
                // TODO: handleCharSelect
            },
            .in_world => {},
        }

        print("sending\n", .{});
        try session.sendPendingPackets();
    }
}
