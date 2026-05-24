const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const Io = std.Io;

const utils = @import("../utils/utils.zig");
const Channel = @import("../messages/channel.zig").Channel;
const ClientMessage = @import("../messages/messages.zig").ClientMessage;
const ServerMessage = @import("../messages/messages.zig").ServerMessage;
const AccountId = @import("../db/types/account.zig").AccountId;
const CharacterId = @import("../db/types/character.zig").CharacterId;
const InPacket = @import("../protocol/packets.zig").InPacket;
const OutPacket = @import("../protocol/packets.zig").OutPacket;
const Container = @import("../protocol/packets.zig").Container;
const Owned = @import("../protocol/packets.zig").Owned;
const sendChallenge = @import("handlers/auth.zig").sendChallenge;
const handleAuth = @import("handlers/auth.zig").handleAuth;
const handleCharList = @import("handlers/char_list.zig").handleCharList;
const handleInWorld = @import("handlers/in_world.zig").handleInWorld;
const processServerMessages = @import("handlers/server_messages.zig").processServerMessages;

const Rc4Writer = utils.rc4.Rc4Writer;
const Rc4Reader = utils.rc4.Rc4Reader;
const MppcWriter = utils.mppc.MppcWriter;

const SessionId = u32;

const Stage = union(enum) {
    auth,
    char_list,
    in_world,
};

const AuthState = struct {
    challenge: ?[16]u8 = null,
    hash: ?[16]u8 = null,
    username: ?[]const u8 = null,
};

pub const Session = struct {
    io: Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator, // Lives the whole session

    id: ?SessionId = null,
    account_id: ?AccountId = null,
    char_id: ?CharacterId = null,

    socket: Io.net.Socket,
    reader: *Io.Reader,
    writer: *Io.Writer,
    stage: Stage,
    auth: AuthState = .{},
    encryptor: ?*Io.Writer = null,
    decryptor: ?*Io.Reader = null,
    compressor: ?*Io.Writer = null,
    inbox: *Channel(Owned(InPacket)),
    outbox: *std.ArrayList(OutPacket),
    tx: *Channel(ClientMessage),
    rx: *Channel(ServerMessage),

    pub fn sendPendingPackets(self: Session) !void {
        const writer = self.compressor orelse self.writer;

        for (self.outbox.items) |packet| {
            errdefer print("error: sending pending packets\n", .{});
            try packet.write(writer, self.gpa);
        }
        try writer.flush();
        self.outbox.clearRetainingCapacity();
    }

    pub fn sendPacket(self: Session, packet: OutPacket) !void {
        const writer = self.compressor orelse self.writer;
        try packet.write(writer, self.gpa);
        try self.writer.flush();
    }

    pub fn enqueuePacket(self: Session, packet: OutPacket) !void {
        try self.outbox.appendBounded(packet);
    }

    pub fn enqueuePackets(self: Session, packets: []const OutPacket) !void {
        try self.outbox.appendSliceBounded(packets);
    }

    pub fn enableDecryption(self: *Session, username: []const u8, hash: [16]u8, sm_key: [16]u8) !void {
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
        assert(self.encryptor != null);
        // The buffer should be large enough to fit one packet
        const buf = try self.arena.alloc(u8, 4096);
        var compressor = try self.arena.create(MppcWriter);
        compressor.* = .init(self.encryptor.?, buf);
        self.compressor = &compressor.writer;
    }
};

pub fn start(
    io: Io,
    gpa: std.mem.Allocator,
    stream: *Io.net.Stream,
    tx: *Channel(ClientMessage),
) void {
    print("INFO: [Session] Client {f} connected\n", .{stream.socket.address});
    startSession(io, gpa, stream, tx) catch |err| {
        print("ERROR: [Session] Client {f} disconnected with error: {}\n", .{ stream.socket.address, err });
        stream.shutdown(io, .both) catch {};
        stream.close(io);
    };
}

fn startSession(io: Io, gpa: std.mem.Allocator, stream: *Io.net.Stream, tx: *Channel(ClientMessage)) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var reader_buf: [4096]u8 = undefined;
    var writer_buf: [4096]u8 = undefined;
    var stream_reader = stream.reader(io, &reader_buf);
    var stream_writer = stream.writer(io, &writer_buf);
    var inbox: Channel(Owned(InPacket)) = try .init(io, arena.allocator(), 64);
    const outbox_buf = try arena.allocator().alloc(OutPacket, 64);
    var outbox: std.ArrayList(OutPacket) = .initBuffer(outbox_buf);
    var rx: Channel(ServerMessage) = try .init(io, arena.allocator(), 128);

    var session: Session = .{
        .io = io,
        .gpa = gpa,
        .arena = arena.allocator(),

        .stage = .auth,
        .socket = stream.socket,
        .reader = &stream_reader.interface,
        .writer = &stream_writer.interface,
        .inbox = &inbox,
        .outbox = &outbox,
        .tx = tx,
        .rx = &rx,
    };

    print("INFO: [Session] Sending challenge...\n", .{});
    try sendChallenge(&session);

    // Syncronous loop, before entering world
    while (true) {
        var packet_arena = std.heap.ArenaAllocator.init(gpa);
        errdefer arena.deinit();
        const reader = session.decryptor orelse session.reader;
        const packet = InPacket.read(reader, packet_arena.allocator()) catch |err| {
            packet_arena.deinit();
            switch (err) {
                error.UnknownOpcode => continue,
                error.EndOfStream => {
                    print("INFO: [Session Sync] Client {f} disconnected\n", .{session.socket.address});
                    return;
                },
                else => {
                    print("ERROR: [Session Sync] Client {f} disconnected with error: {}\n", .{ session.socket.address, err });
                    return;
                },
            }
        };
        try processPacket(&session, .{ .arena = packet_arena, .value = packet });
        try session.sendPendingPackets();

        if (session.stage == .in_world) {
            print("INFO: [Session Sync] Switching to async loop\n", .{});
            break;
        }
    }

    var reader_task = try io.concurrent(streamReader, .{&session});
    defer reader_task.cancel(io) catch {};

    // Async loop
    while (true) {
        errdefer print("error: async loop\n", .{});
        try processServerMessages(&session);
        try session.sendPendingPackets();
        for (try session.inbox.drain()) |packet| {
            try processPacket(&session, packet);
        }
        try io.sleep(.fromMilliseconds(50), .awake);
    }
}

fn streamReader(session: *Session) !void {
    while (true) {
        var arena = std.heap.ArenaAllocator.init(session.gpa);
        errdefer arena.deinit();
        const reader = session.decryptor.?;

        if (InPacket.read(reader, arena.allocator())) |packet| {
            session.inbox.send(.{ .arena = arena, .value = packet }) catch break;
        } else |err| {
            arena.deinit();
            switch (err) {
                error.UnknownOpcode => continue,
                error.EndOfStream => {
                    print("INFO: [Session Async] Client {f} disconnected\n", .{session.socket.address});
                    return;
                },
                else => {
                    print("ERROR: [Session Async] Client {f} disconnected with error: {}\n", .{ session.socket.address, err });
                    return;
                },
            }
        }
    }
}

fn processPacket(session: *Session, owned: Owned(InPacket)) !void {
    const packet = owned.value;

    // Handle global packets
    switch (packet) {
        .keep_alive => {
            defer owned.deinit();
            try session.sendPacket(.{ .keep_alive = .{ .data = 0xf0 } });
            return;
        },
        else => {},
    }

    switch (session.stage) {
        .auth => {
            defer owned.deinit();
            try handleAuth(session, packet);
        },
        .char_list => {
            defer owned.deinit();
            try handleCharList(session, packet);
        },
        .in_world => {
            try handleInWorld(session, owned);
        },
    }
}
