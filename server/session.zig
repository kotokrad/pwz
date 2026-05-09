const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const Io = std.Io;

const events = @import("../events/events.zig");
const Rc4Writer = @import("utils/rc4.zig").Rc4Writer;
const Rc4Reader = @import("utils/rc4.zig").Rc4Reader;
const MppcWriter = @import("utils/mppc.zig").MppcWriter;
const InPacket = @import("../protocol/packets.zig").InPacket;
const OutPacket = @import("../protocol/packets.zig").OutPacket;
const Container = @import("../protocol/packets.zig").Container;
const Account = @import("../world/world.zig").Account;
const Owned = @import("../protocol/packets.zig").Owned;
const sendChallenge = @import("handlers/auth.zig").sendChallenge;
const handleAuth = @import("handlers/auth.zig").handleAuth;
const handleCharList = @import("handlers/char_list.zig").handleCharList;
const handleInWorld = @import("handlers/in_world.zig").handleInWorld;

const Channel = events.Channel;
const Message = events.Message;
const Action = events.Action;
const Update = events.Update;

const Stage = union(enum) {
    auth,
    char_list,
    in_world,
};

const AuthState = struct {
    challenge: ?[17]u8 = null,
    hash: ?[16]u8 = null,
    username: ?[]const u8 = null,
};

pub const Session = struct {
    id: ?u32 = null,
    io: Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator, // Lives the whole session
    scratch: std.mem.Allocator, // Reset after processing every request
    socket: Io.net.Socket,
    reader: *Io.Reader,
    writer: *Io.Writer,
    stage: Stage,
    account: ?Account = null,
    auth: AuthState = .{},
    encryptor: ?*Io.Writer = null,
    decryptor: ?*Io.Reader = null,
    compressor: ?*Io.Writer = null,
    inbox: *Channel(Owned(InPacket)),
    outbox: *std.ArrayList(Owned(OutPacket)),
    messages_tx: *Channel(Message),
    actions_tx: *Channel(Action),
    updates_rx: *Channel(Update),

    pub fn sendPendingPackets(self: Session) !void {
        const writer = self.compressor orelse self.writer;
        const updates = try self.updates_rx.drain();
        for (updates) |update| {
            print("INCOMING!!! {any}\n", .{update});
        }
        if (updates.len > 0) {
            const packet: OutPacket = .{ .container = .{ .list = updates } };
            try packet.write(writer, self.scratch);
        }

        for (self.outbox.items) |packet| {
            try packet.value.write(writer, self.scratch);
        }
        self.outbox.clearRetainingCapacity();
        try writer.flush();
    }

    pub fn sendPacket(self: Session, packet: OutPacket) !void {
        try packet.write(self.writer, self.scratch);
        try self.writer.flush();
    }

    pub fn enqueuePacket(self: Session, packet: OutPacket) !void {
        try self.outbox.appendBounded(.{ .value = packet });
    }

    pub fn enqueuePacketAlloc(self: Session, arena: std.heap.ArenaAllocator, packet: OutPacket) !void {
        try self.outbox.appendBounded(.{ .arena = arena, .value = packet });
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
    stream: Io.net.Stream,
    messages_tx: *Channel(Message),
    actions_tx: *Channel(Action),
) void {
    print("INFO: [Session] Client {f} connected\n", .{stream.socket.address});
    startSession(io, gpa, stream, messages_tx, actions_tx) catch |err| {
        print("ERROR: [Session] Client {f} disconnected with error: {}\n", .{ stream.socket.address, err });
    };
}

fn startSession(
    io: Io,
    gpa: std.mem.Allocator,
    stream: Io.net.Stream,
    messages_tx: *Channel(Message),
    actions_tx: *Channel(Action),
) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var scratch = std.heap.ArenaAllocator.init(gpa);
    errdefer scratch.deinit();
    var reader_buf: [4096]u8 = undefined;
    var writer_buf: [4096]u8 = undefined;
    var stream_reader = stream.reader(io, &reader_buf);
    var stream_writer = stream.writer(io, &writer_buf);
    var inbox_back: [64]Owned(InPacket) = undefined;
    var inbox_front: [64]Owned(InPacket) = undefined;
    var inbox: Channel(Owned(InPacket)) = .init(io, &inbox_back, &inbox_front);
    var outbox_buf: [64]Owned(OutPacket) = undefined;
    var outbox: std.ArrayList(Owned(OutPacket)) = .initBuffer(&outbox_buf);
    var upd_back: [128]Update = undefined;
    var upd_front: [128]Update = undefined;
    var updates_rx: Channel(Update) = .init(io, &upd_back, &upd_front);
    var session: Session = .{
        .io = io,
        .gpa = gpa,
        .arena = arena.allocator(),
        .scratch = scratch.allocator(),
        .stage = .auth,
        .socket = stream.socket,
        .reader = &stream_reader.interface,
        .writer = &stream_writer.interface,
        .inbox = &inbox,
        .outbox = &outbox,
        .messages_tx = messages_tx,
        .actions_tx = actions_tx,
        .updates_rx = &updates_rx,
    };

    print("Sending challenge...\n", .{});
    try sendChallenge(&session);

    // Syncronous loop, before entering world
    while (true) {
        var packet_arena = std.heap.ArenaAllocator.init(gpa);
        errdefer arena.deinit();
        defer _ = scratch.reset(.retain_capacity);
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
        try session.sendPendingPackets();
        defer _ = scratch.reset(.retain_capacity);
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
            session.inbox.append(.{ .arena = arena, .value = packet }) catch break;
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
