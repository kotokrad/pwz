const std = @import("std");
const Md5 = std.crypto.hash.Md5;

const String = @import("../../utils/utils.zig").String;

pub const AccountId = u32;

/// Account IDs have pattern:
/// 0x400
/// 0x410
/// 0x420
/// ...
/// Then Character ID is calculated from account ID,
/// starting with the same number, allowing up to 16 characters
pub const Account = struct {
    id: AccountId = undefined,
    username: String(16),
    hash: [16]u8,

    pub const MAX_CHARACTERS = 8;

    pub fn init(username: []const u8, password: []const u8) !Account {
        if (username.len > 16) return error.UsernameTooLong;
        if (password.len > 16) return error.PasswordTooLong;
        var buf: [32]u8 = undefined;
        var fba: std.heap.FixedBufferAllocator = .init(&buf);
        const hash = Md5.hashResult(try std.mem.concat(fba.allocator(), u8, &.{ username, password }));
        return .{
            .username = try .fromSlice(username),
            .hash = hash,
        };
    }
};
