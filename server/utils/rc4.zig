const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const HmacMd5 = std.crypto.auth.hmac.HmacMd5;

const KeyInputs = struct {
    username: []const u8,
    hash: [16]u8,
    key: [16]u8,
};

pub fn generate_key(inputs: KeyInputs) [16]u8 {
    var hmac: HmacMd5 = .init(inputs.username);
    hmac.update(&inputs.hash ++ &inputs.key);
    var key: [16]u8 = undefined;
    hmac.final(&key);
    return key;
}

pub const Rc4Writer = struct {
    writer: Writer,
    out: *Writer,
    rc4: Rc4,

    pub fn init(
        out: *Writer,
        buffer: []u8,
        inputs: KeyInputs,
    ) @This() {
        const cm_key = generate_key(inputs);
        return .{
            .out = out,
            .rc4 = .init(cm_key),
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
        // print("Compressed: {X}\n", .{buffered});
        this.rc4.processSlice(buffered);
        _ = try this.out.write(buffered);
        try this.out.flush();
        // print("Encrypted:  {X}\n", .{buffered});
        _ = w.consumeAll();

        var buf: [128]u8 = undefined;
        const slice = data[0];
        @memcpy(buf[0..slice.len], slice);
        const processed_slice = buf[0..slice.len];
        this.rc4.processSlice(processed_slice);
        const written = try this.out.write(processed_slice);
        try this.out.flush();
        return written;
    }
};

pub const Rc4Reader = struct {
    reader: Reader,
    in: *Reader,
    rc4: Rc4,

    pub fn init(
        in: *Reader,
        buffer: []u8,
        inputs: KeyInputs,
    ) @This() {
        const sm_key = generate_key(inputs);
        return .{
            .in = in,
            .rc4 = .init(sm_key),
            .reader = .{
                .buffer = buffer,
                .end = 0,
                .seek = 0,
                .vtable = &.{ .stream = @This().stream },
            },
        };
    }

    fn stream(r: *Reader, w: *Writer, limit: std.Io.Limit) Reader.StreamError!usize {
        const this: *@This() = @alignCast(@fieldParentPtr("reader", r));
        const data = limit.slice(try w.writableSliceGreedy(1));
        var vec: [1][]u8 = .{data};
        const n = try this.in.readVec(&vec);
        this.rc4.processSlice(data[0..n]);
        w.advance(n);
        return n;
    }
};

pub const Rc4 = struct {
    cipher: [256]usize,
    i: usize = 0,
    j: usize = 0,

    pub fn init(key: [16]u8) Rc4 {
        var cipher: [256]usize = undefined;
        for (0..256) |i| {
            cipher[i] = i;
        }
        var j: usize = 0;
        for (0..256) |i| {
            j = (j + cipher[i] + key[i % key.len]) & 0xff;
            swap(&cipher[i], &cipher[j]);
        }
        return .{
            .cipher = cipher,
        };
    }

    pub fn process(self: *Rc4, byte: u8) u8 {
        self.i = (self.i + 1) & 0xff;
        self.j = (self.j + self.cipher[self.i]) & 0xff;
        swap(&self.cipher[self.i], &self.cipher[self.j]);
        const t = (self.cipher[self.i] + self.cipher[self.j]) & 0xff;
        const k: u8 = @intCast(self.cipher[t]);
        return byte ^ k;
    }

    pub fn processSlice(self: *Rc4, slice: []u8) void {
        for (slice, 0..) |byte, i| {
            slice[i] = process(self, byte);
        }
    }

    fn swap(a: *usize, b: *usize) void {
        const tmp = a.*;
        a.* = b.*;
        b.* = tmp;
    }
};

test "encrypt with RC4" {
    const key = "Key";
    const plaintext = "Plaintext";
    const plaintext_data_hex = "506C61696E74657874";
    const encrypted_data_hex = "BBF316E8D940AF0AD3";

    var rc4: Rc4 = .init(key.*);
    var result = plaintext.*;
    rc4.processSlice(&result);

    try std.testing.expectFmt(plaintext_data_hex, "{X}", .{plaintext});
    try std.testing.expectFmt(encrypted_data_hex, "{X}", .{result});
}

test "encrypt/decrypt using Reader and Writer" {
    const key = "Key";
    const plaintext = "Plaintext";
    const plaintext_data_hex = "506C61696E74657874";
    const encrypted_data_hex = "BBF316E8D940AF0AD3";

    // Writer
    // ----------------------------------------
    var rc4_for_writer: Rc4 = .init(key.*);
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    var w_buf: [64]u8 = undefined;
    var writer: Rc4Writer = .init(&aw.writer, &rc4_for_writer, &w_buf);
    _ = try writer.writer.write(plaintext);
    try writer.writer.flush();
    const w_result = aw.written();

    // Reader
    // ----------------------------------------
    var rc4_for_reader: Rc4 = .init(key.*);
    var r_buf: [64]u8 = undefined;
    var fr: std.Io.Reader = .fixed(w_result);
    var reader: Rc4Reader = .init(&fr, &rc4_for_reader, &r_buf);
    const r_result = try reader.reader.peekGreedy(1);

    try std.testing.expectFmt(encrypted_data_hex, "{X}", .{w_result});
    try std.testing.expectFmt(plaintext_data_hex, "{X}", .{r_result});
}
