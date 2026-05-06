const std = @import("std");
const print = std.debug.print;
const Md5 = std.crypto.hash.Md5;
const HmacMd5 = std.crypto.auth.hmac.HmacMd5;

const Session = @import("../session.zig").Session;
const codec = @import("../../protocol/codec.zig");
const packets = @import("../../protocol/packets.zig");
const types = @import("../../protocol/types.zig");
const Reply = @import("../../world/events.zig").Reply;
const Account = @import("../../world/world.zig").Account;
const InPacket = packets.InPacket;
const ServerError = packets.ServerError;
const ErrorCode = types.ErrorCode;
const Challenge = packets.Challenge;
const ChallengeData = types.ChallengeData;
const LoginRequest = packets.LoginRequest;
const KeyExchange = packets.KeyExchange;
const OnlineAnnounce = packets.OnlineAnnounce;

fn getHmacMd5(username: []const u8, password: []const u8, challenge: [17]u8) [16]u8 {
    var hmac: HmacMd5 = .init(&Md5.hashResult(username ++ password));
    hmac.update(&challenge);
    var hash: [16]u8 = undefined;
    hmac.final(&hash);
}

pub fn handleAuth(session: *Session, packet: InPacket) !void {
    switch (packet) {
        .login_request => |payload| try handleLoginRequest(session, payload),
        .key_exchange => |payload| try handleKeyExchange(session, payload),
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
        .version = .{ 0, 1, 4, 2 },
        .auth_method = 0,
        .crc_signature = .init(.{
            0x33, 0x30, 0x30, 0x30, 0x30, 0x30, 0x31, 0x62, 0x34, 0x62, 0x36, 0x35, 0x39, 0x62,
            0x32, 0x65, 0x31, 0x63, 0x34, 0x61, 0x61, 0x35, 0x66, 0x39, 0x37, 0x38,
        }),
        .exp_multiplier = 0,
    };

    // Saving serialized challenge_data
    // it will be used to hash the auth creds
    var buf: [17]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try codec.serialize(ChallengeData, &writer, challenge_data, session.scratch);
    session.auth.challenge = buf;

    try session.sendPacket(.{ .challenge = challenge });
}

fn handleLoginRequest(session: *Session, payload: LoginRequest) !void {
    session.auth.hash = payload.hash.value;
    session.auth.username = payload.username;

    var reply: Reply(?Account) = .{};
    try session.actions_tx.append(.{
        .auth = .{
            // Just sending the pointer because we're waiting for reply
            .username = session.auth.username.?,
            .reply = &reply,
        },
    });

    const account = try reply.await(session.io);

    print("INFO: [Auth] login request {s}:{X}\n", .{ payload.username, payload.hash.value });
    // print("debug: [Auth] client hash {X}\n", .{payload.hash.value});
    // if (account) |a| print("debug: [Auth] hash for {s}: {X}\n", .{ payload.username, a.hash });

    if (account == null or !std.mem.eql(u8, &payload.hash.value, &account.?.hash)) {
        const server_error = ServerError{
            .code = ErrorCode.invalid_credentials,
            .message = "Yoyoyo",
        };
        try session.enqueuePacket(.{ .server_error = server_error });
        return;
    }

    const sm_key: [16]u8 = @splat(69);
    // session.account_id = 0xEFBE3713;
    // session.session_id = 0xEFBEADDE;
    session.account = account;

    try session.enableDecryption(payload.username, payload.hash.value, sm_key);

    const key_exchange = KeyExchange{ .key = .init(sm_key) };
    try session.enqueuePacket(.{ .key_exchange = key_exchange });
}

fn handleKeyExchange(session: *Session, payload: KeyExchange) !void {
    try session.enableEncryption(session.auth.username.?, session.auth.hash.?, payload.key.value);
    try session.enableCompression();

    var reply: Reply(u8) = .{};
    try session.actions_tx.append(.{
        .init_session = .{
            .channel = session.updates_rx,
            .reply = &reply,
        },
    });
    const session_id = try reply.await(session.io);
    session.id = session_id;

    const online_announce = OnlineAnnounce{
        .account_id = session.account.?.id,
        .session_id = session_id,
        .time_remaining = 0,
        .zone_id = 1,
        .free_time_left = 0,
        .free_time_end = 0xFFFFFFFF,
        .create_time = 0,
        .referrer_flag = 0,
    };
    try session.enqueuePacket(.{ .online_announce = online_announce });
    session.stage = .char_list;
}
