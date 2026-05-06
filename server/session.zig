const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const Io = std.Io;

const Rc4Writer = @import("utils/rc4.zig").Rc4Writer;
const Rc4Reader = @import("utils/rc4.zig").Rc4Reader;
const MppcWriter = @import("utils/mppc.zig").MppcWriter;
const InPacket = @import("../protocol/packets.zig").InPacket;
const OutPacket = @import("../protocol/packets.zig").OutPacket;
const Channel = @import("../world/events.zig").Channel;
const Action = @import("../world/events.zig").Action;
const Update = @import("../world/events.zig").Update;
const Account = @import("../world/world.zig").Account;
const Owned = @import("../protocol/packets.zig").Owned;
const sendChallenge = @import("handlers/auth.zig").sendChallenge;
const handleAuth = @import("handlers/auth.zig").handleAuth;
const handleCharList = @import("handlers/char_list.zig").handleCharList;

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
    reader: *Io.Reader,
    writer: *Io.Writer,
    stage: Stage,
    account: ?Account = null,
    auth: AuthState = .{},
    encryptor: ?*Io.Writer = null,
    decryptor: ?*Io.Reader = null,
    compressor: ?*std.Io.Writer = null,
    outbox: *std.ArrayList(Owned(OutPacket)),
    actions_tx: *Channel(Action),
    updates_rx: *Channel(Update),

    pub fn sendPendingPackets(self: Session) !void {
        const writer = self.compressor orelse self.writer;
        for (self.outbox.items) |packet| {
            try packet.value.write(writer, self.scratch);
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
        try self.outbox.append(self.scratch, .{ .value = packet });
    }

    pub fn enqueuePacketAlloc(self: Session, arena: std.heap.ArenaAllocator, packet: OutPacket) !void {
        try self.outbox.append(self.scratch, .{ .arena = arena, .value = packet });
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

pub fn start(io: Io, gpa: std.mem.Allocator, stream: Io.net.Stream, actions_tx: *Channel(Action)) void {
    print("INFO: Client {f} connected\n", .{stream.socket.address});
    startSession(io, gpa, stream, actions_tx) catch |err| switch (err) {
        error.EndOfStream => print("INFO: Client {f} disconnected\n", .{stream.socket.address}),
        else => print("ERROR: Client {f} disconnected with error: {}", .{ stream.socket.address, err }),
    };
}

fn startSession(io: Io, gpa: std.mem.Allocator, stream: Io.net.Stream, actions_tx: *Channel(Action)) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var scratch = std.heap.ArenaAllocator.init(gpa);
    errdefer scratch.deinit();
    var reader_buf: [4096]u8 = undefined;
    var writer_buf: [4096]u8 = undefined;
    var stream_reader = stream.reader(io, &reader_buf);
    var stream_writer = stream.writer(io, &writer_buf);
    var outbox_buf: [64]Owned(OutPacket) = undefined;
    var outbox: std.ArrayList(Owned(OutPacket)) = .initBuffer(&outbox_buf);
    var upd_back_buf: [128]Update = undefined;
    var upd_front_buf: [128]Update = undefined;
    var updates_rx: Channel(Update) = .{
        .back = .initBuffer(&upd_back_buf),
        .front = .initBuffer(&upd_front_buf),
        .mutex = .init,
        .io = io,
    };
    var session: Session = .{
        .io = io,
        .gpa = gpa,
        .arena = arena.allocator(),
        .scratch = scratch.allocator(),
        .stage = .auth,
        .reader = &stream_reader.interface,
        .writer = &stream_writer.interface,
        .outbox = &outbox,
        .actions_tx = actions_tx,
        .updates_rx = &updates_rx,
    };
    try sendChallenge(&session);

    while (true) {
        defer _ = scratch.reset(.retain_capacity);
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
            .char_list => {
                defer packet_arena.deinit();
                try handleCharList(&session, packet);
            },
            .in_world => {},
        }

        try session.sendPendingPackets();
    }
}
