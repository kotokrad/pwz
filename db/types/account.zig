const String = @import("../../utils/utils.zig").String;

pub const AccountId = u32;

pub const Account = struct {
    id: AccountId = undefined,
    username: String(16),
    hash: [16]u8,

    pub const MAX_CHARACTERS = 8;
};
