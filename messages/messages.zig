const std = @import("std");
const Io = std.Io;

const utils = @import("../utils/utils.zig");
const types = @import("../protocol/types.zig");
const packets = @import("../protocol/packets.zig");
const Channel = @import("channel.zig").Channel;
const Reply = @import("channel.zig").Reply;
const UTF16String = @import("../protocol/codec.zig").UTF16String;
const Vec = @import("../protocol/codec.zig").Vec;
const Action = @import("../protocol/actions.zig").Action;
const Update = @import("../protocol/updates.zig").Update;
const SessionId = @import("../world/world.zig").SessionId;
const Account = @import("../db/types/account.zig").Account;
const AccountId = @import("../db/types/account.zig").AccountId;
const Character = @import("../db/types/character.zig").Character;
const CharacterId = @import("../db/types/character.zig").CharacterId;
const Item = @import("../db/types/inventory.zig").Item;
const PublicChatMessage = @import("../world/chat.zig").PublicChatMessage;
const PrivateChatMessage = @import("../world/chat.zig").PrivateChatMessage;
const WorldChatBroadcast = @import("../world/chat.zig").WorldChatBroadcast;
const PublicChatBroadcast = @import("../world/chat.zig").PublicChatBroadcast;

const BE = utils.BE;
const BoundedArray = utils.BoundedArray;
const String = utils.String;
const RoleInfo = types.RoleInfo;

/// Message to the game loop from a session thread.
/// Sender may expect a reply and will block until it's received.
pub const ClientMessage = union(enum) {
    // zig fmt: off
    action:           struct { session_id: SessionId, char_id: CharacterId, action: Action },
    get_account:      struct { username: []const u8, reply: *Reply(?Account) = undefined },
    get_characters:   struct { account_id: AccountId, reply: *Reply(BoundedArray(Character, 8)) = undefined },
    get_items:        struct { char_id: CharacterId, reply: *Reply(BoundedArray(Item, Item.MAX_GENERAL_ITEMS)) = undefined },
    init_session:     struct { channel: *Channel(ServerMessage), reply: *Reply(SessionId) = undefined },
    enter_world:      struct { session_id: SessionId, char_id: CharacterId },
    get_ui_config:    struct { session_id: SessionId, char_id: CharacterId, reply: *Reply(BoundedArray(u8, 512)) = undefined },
    set_char_flag:    struct { session_id: SessionId, char_id: CharacterId, flag: u5 },
    player_base_info: struct { session_id: SessionId, id_list: Vec(BE(u32), 10) },
    public_message:   PublicChatMessage,
    private_message:  PrivateChatMessage,
    // zig fmt: on
};

/// Message to the session thread.
pub const ServerMessage = union(enum) {
    // zig fmt: off
    update:           Update,
    public_chat:      PublicChatBroadcast,
    world_chat:       WorldChatBroadcast,
    send_player_info: Character,
    // zig fmt: on
};
