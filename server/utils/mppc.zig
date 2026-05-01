// Quick implementation of MPPC compression variant used in PW
// Spec: https://datatracker.ietf.org/doc/html/rfc2118
// Differences:
// - no header, no flags, no coherency count
// - byte alignment flag (1111 000000) at the end of the packet

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const Writer = std.Io.Writer;

const HISTORY_SIZE = 10240;
const HISTORY_KEEP = 8192;

const Match = struct {
    offset: u16,
    len: u16,
};

pub const MppcWriter = struct {
    writer: Writer,
    mppc: Mppc,

    pub fn init(
        out: *Writer,
        buffer: []u8,
    ) @This() {
        return .{
            .mppc = .init(out),
            .writer = .{
                .buffer = buffer,
                .vtable = &.{ .drain = @This().drain },
            },
        };
    }

    fn drain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
        const this: *@This() = @alignCast(@fieldParentPtr("writer", w));
        _ = splat;

        const buffered = w.buffered();
        // print("Plaintext:  {X}\n", .{buffered});
        try this.mppc.compress(buffered);
        _ = w.consumeAll();

        // Non-empty data means buffer overflow
        var overflow: usize = 0;
        for (data) |s| overflow += s.len;
        if (overflow > 0) return error.WriteFailed;
        return 0;
    }
};

pub const Mppc = struct {
    hist: [HISTORY_SIZE]u8 = @splat(0),
    out: *Writer,
    cur: u16 = 0,

    pub fn init(out: *Writer) Mppc {
        return .{ .out = out };
    }

    pub fn compress(self: *Mppc, data: []u8) !void {
        var bs: BitStream = .init(self.out);
        // Slide the history buffer if needed
        // Check if there are packets >= 2K bytes
        assert(data.len <= 2048);
        if (self.cur >= HISTORY_SIZE) {
            std.mem.copyForwards(u8, self.hist[0..HISTORY_KEEP], self.hist[self.cur - HISTORY_KEEP .. self.cur]);
            self.cur = HISTORY_KEEP;
        }

        var i: usize = 0;
        while (i < data.len) {
            if (self.findLongestMatch(data, i)) |match| {
                try bs.writeCopyTuple(match);
                self.appendHist(data[i .. i + match.len]);
                i += match.len;
            } else {
                try bs.writeLit(data[i]);
                self.appendHist(data[i .. i + 1]);
                i += 1;
            }
        }
        try bs.finalize();
    }

    // TODO: use hash chain, current search method is very slow
    fn findLongestMatch(self: *Mppc, data: []u8, start: usize) ?Match {
        var match: ?Match = null;

        var last_pos: usize = 0;
        while (true) {
            if (self.cur < 3 or data.len - start < 3) break;
            if (std.mem.findPos(u8, self.hist[0..self.cur], last_pos, data[start .. start + 3])) |pos| {
                const len = if (std.mem.findDiff(u8, self.hist[pos..], data[start..])) |len| blk: {
                    break :blk len;
                } else blk: {
                    break :blk data.len - start;
                };

                if (match == null or match.?.len <= len) {
                    match = .{ .offset = @intCast(self.cur - pos), .len = @intCast(len) };
                }

                last_pos = pos + len;
            } else {
                break;
            }
        }
        return match;
    }

    fn appendHist(self: *Mppc, data: []u8) void {
        std.mem.copyForwards(u8, self.hist[self.cur..], data);
        self.cur += @intCast(data.len);
    }
};

pub const BitStream = struct {
    out: *Writer,
    buffer: u64 = 0,
    nbits: u6 = 0,

    pub fn init(out: *Writer) BitStream {
        return .{ .out = out };
    }

    pub fn writeBits(self: *BitStream, value: usize, count: u6) !void {
        const mask = (@as(u64, 1) << count) - 1;
        self.buffer <<= count;
        self.buffer |= value & mask;
        self.nbits += count;

        while (self.nbits >= 8) {
            const byte: u8 = @truncate(self.buffer >> (self.nbits - 8));
            const rest_mask = (@as(u64, 1) << self.nbits - 8) - 1;
            self.buffer &= rest_mask;
            self.nbits -= 8;
            try self.out.writeByte(byte);
        }
    }

    pub fn writeLit(self: *BitStream, byte: u8) !void {
        // print("literal({X})\n", .{byte});
        if (byte < 0x80) {
            try self.writeBits(byte, 8);
        } else {
            try self.writeBits(0b10, 2);
            try self.writeBits(byte, 7);
        }
    }

    pub fn writeCopyTuple(self: *BitStream, match: Match) !void {
        // Write offset
        const offset = match.offset;
        const len = match.len;
        // print("copy_tuple({}, {})\n", .{ offset, len });

        if (offset < 64) {
            try self.writeBits(0b1111, 4);
            try self.writeBits(offset, 6);
        } else if (offset < 320) {
            try self.writeBits(0b1110, 4);
            try self.writeBits(offset - 64, 8);
        } else if (offset < 8191) {
            try self.writeBits(0b110, 3);
            try self.writeBits(offset - 320, 13);
        }

        // Write length-of-match
        if (len == 3) {
            try self.writeBits(0, 1);
        } else if (len < 7) {
            try self.writeBits(0b10, 2);
            try self.writeBits(len, 2);
        } else if (len < 15) {
            try self.writeBits(0b110, 3);
            try self.writeBits(len, 3);
        } else if (len < 31) {
            try self.writeBits(0b1110, 4);
            try self.writeBits(len, 4);
        } else if (len < 63) {
            try self.writeBits(0b11110, 5);
            try self.writeBits(len, 5);
        } else if (len < 127) {
            try self.writeBits(0b111110, 6);
            try self.writeBits(len, 6);
        } else if (len < 255) {
            try self.writeBits(0b1111110, 7);
            try self.writeBits(len, 7);
        } else if (len < 511) {
            try self.writeBits(0b11111110, 8);
            try self.writeBits(len, 8);
        } else if (len < 1023) {
            try self.writeBits(0b111111110, 9);
            try self.writeBits(len, 9);
        } else if (len < 2047) {
            try self.writeBits(0b1111111110, 10);
            try self.writeBits(len, 10);
        } else if (len < 4095) {
            try self.writeBits(0b11111111110, 11);
            try self.writeBits(len, 11);
        } else if (len < 8191) {
            try self.writeBits(0b111111111110, 12);
            try self.writeBits(len, 12);
        }
    }

    pub fn finalize(self: *BitStream) !void {
        // Align packet to the byte boundary
        // All extra bits after alignment flag will be discarded
        try self.writeBits(0b1111000000, 10);
        if (self.nbits > 0) {
            const padding_len: u6 = 8 - self.nbits;
            try self.writeBits(self.buffer << padding_len, padding_len);
        }

        try self.out.flush();
    }
};

test "compress data with MPPC" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();

    const plaintext = "ABC12345ABC67890";
    const compressed_hex = "4142433132333435F206C6E707261E00";

    var data = plaintext.*;
    var mppc: Mppc = .init(&aw.writer);
    try mppc.compress(&data);
    const mppc_result = aw.written();

    try std.testing.expectFmt(compressed_hex, "{X}", .{mppc_result});
}
