const std = @import("std");
const print = std.debug.print;
const HmacMd5 = std.crypto.auth.hmac.HmacMd5;

const codec = @import("../../protocol/codec.zig");
const packets = @import("../../protocol/packets.zig");
const types = @import("../../protocol/types.zig");
const Session = @import("../session.zig").Session;
const SessionId = @import("../../world/world.zig").SessionId;
const Account = @import("../../db/types/account.zig").Account;

const InPacket = packets.InPacket;
const ServerError = packets.ServerError;
const ErrorCode = types.ErrorCode;
const Challenge = packets.Challenge;
const ChallengeData = types.ChallengeData;
const LoginRequest = packets.LoginRequest;
const KeyExchange = packets.KeyExchange;
const OnlineAnnounce = packets.OnlineAnnounce;

fn getHmacMd5(account_hash: [16]u8, challenge: [16]u8) [16]u8 {
    var hmac: HmacMd5 = .init(&account_hash);
    hmac.update(&challenge);
    var hash: [16]u8 = undefined;
    hmac.final(&hash);
    return hash;
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
        .server_load = 0x00,
        // .flags = .{ .is_pvp = true },
        .flags = .{},
        .random_bytes = .{ 1, 2, 3, 4, 5, 6, 7, 8 },
    };

    const challenge = Challenge{
        .data = .init(challenge_data),
        .version = .{ 0, 1, 4, 4 },
        .auth_method = 0,
        .crc_signature = .init(.{
            0x33, 0x30, 0x30, 0x30, 0x30, 0x30, 0x33, 0x63, 0x35, 0x64, 0x34, 0x64, 0x36, 0x37,
            0x35, 0x63, 0x65, 0x62, 0x34, 0x63, 0x66, 0x39, 0x66, 0x63, 0x35, 0x36,
        }),
        .exp_multiplier = 0,
    };

    // Saving serialized challenge_data
    // it will be used to hash the auth creds
    var buf: [16]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try codec.serialize(ChallengeData, &writer, challenge_data);
    session.auth.challenge = buf;

    try session.sendPacket(.{ .challenge = challenge });
}

fn handleLoginRequest(session: *Session, payload: LoginRequest) !void {
    const hash = payload.hash.value;
    const username = payload.username.slice();
    session.auth.hash = hash;
    session.auth.username = try session.arena.dupe(u8, username);

    const account = try session.tx.request(?Account, .get_account, .{ .username = username }) orelse {
        return try sendServerError(session, .invalid_credentials, "Not found");
    };

    const challenge = session.auth.challenge orelse unreachable;

    print("INFO: [Auth] login request {s}:{X}\n", .{ username, hash });

    if (!std.mem.eql(u8, &hash, &getHmacMd5(account.hash, challenge))) {
        return try sendServerError(session, .invalid_credentials, "Not found");
    }

    const sm_key: [16]u8 = @splat(69);
    session.account_id = account.id;

    try session.enableDecryption(payload.username.slice(), payload.hash.value, sm_key);

    const key_exchange = KeyExchange{ .key = .init(sm_key) };
    try session.enqueuePacket(.{ .key_exchange = key_exchange });
}

fn sendServerError(session: *Session, code: ErrorCode, message: []const u8) !void {
    const server_error = ServerError{
        .code = code,
        .message = try .fromSlice(message),
    };
    try session.enqueuePacket(.{ .server_error = server_error });
}

fn handleKeyExchange(session: *Session, payload: KeyExchange) !void {
    try session.enableEncryption(session.auth.username.?, session.auth.hash.?, payload.key.value);
    try session.enableCompression();

    const session_id = try session.tx.request(SessionId, .init_session, .{
        .channel = session.rx,
    });
    session.id = session_id;

    const online_announce = OnlineAnnounce{
        .account_id = session.account_id.?,
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
