const std = @import("std");
const print = std.debug.print;
const Md5 = std.crypto.hash.Md5;
const HmacMd5 = std.crypto.auth.hmac.HmacMd5;

const Session = @import("../session.zig").Session;
const codec = @import("../../protocol/codec.zig");
const packets = @import("../../protocol/packets.zig");
const InPacket = packets.InPacket;
const ServerError = packets.ServerError;
const ErrorCode = packets.ErrorCode;
const Challenge = packets.Challenge;
const ChallengeData = packets.ChallengeData;
const LoginRequest = packets.LoginRequest;
const KeyExchange = packets.KeyExchange;

pub fn handleAuth(session: *Session, packet: InPacket) !void {
    switch (packet) {
        .LoginRequest => |payload| try handleLoginRequest(session, payload),
        else => {
            print("ERROR: [Auth] Unexpected packet {any}\n", .{packet});
            return error.UnexpectedPacket;
        },
    }
}

pub fn sendChallenge(session: *Session) !void {
    const challenge_data = ChallengeData{
        .server_load = 0xff,
        .flags = .{ .is_pvp = true },
        .random_bytes = .{ 1, 2, 3, 4, 5, 6, 7, 8 },
    };

    const challenge = Challenge{
        .data = .init(challenge_data),
        .version = [4]u8{ 0, 1, 4, 2 },
        .auth_method = 0,
        .crc_signature = .init([26]u8{
            0x33, 0x30, 0x30, 0x30, 0x30, 0x30, 0x31, 0x62, 0x34, 0x62, 0x36, 0x35, 0x39, 0x62,
            0x32, 0x65, 0x31, 0x63, 0x34, 0x61, 0x61, 0x35, 0x66, 0x39, 0x37, 0x38,
        }),
        .exp_multiplier = 0,
    };

    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();
    var buf: [17]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try codec.serialize(ChallengeData, &writer, challenge_data, scratch.allocator());
    session.login.challenge = buf;

    try session.sendPacket(.{ .Challenge = challenge });
}

fn handleLoginRequest(session: *Session, payload: LoginRequest) !void {
    const valid_username = "qwer";
    const valid_password = "qwer";
    var hmac = HmacMd5.init(&Md5.hashResult(valid_username ++ valid_password));
    hmac.update(&session.login.challenge.?);
    var hash: [16]u8 = undefined;
    hmac.final(&hash);
    session.login.hash = hash;

    if (!std.mem.eql(u8, &payload.hash.value, &hash)) {
        const server_error = ServerError{
            .code = ErrorCode.invalid_credentials,
            .message = "Yoyoyo",
        };
        try session.enqueuePacket(.{ .ServerError = server_error });
        return;
    }

    const key_exchange = KeyExchange{
        .key = .init(@splat(69)),
    };
    codec.debug(key_exchange);
    try session.enqueuePacket(.{ .KeyExchange = key_exchange });

    print("INFO: [Auth] login request {s}:{X}\n", .{ payload.username, payload.hash.value });
    print("debug: [Auth] client hash {x}\n", .{payload.hash.value});
    print("debug: [Auth] valid hash  {x}\n", .{hash});
}
