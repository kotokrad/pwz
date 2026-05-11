const std = @import("std");
const print = std.debug.print;
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;

pub const LoggingWriter = struct {
    writer: Writer,
    out: *Writer,

    pub fn init(
        out: *Writer,
    ) @This() {
        return .{
            .out = out,
            .writer = .{
                .buffer = &[_]u8{},
                .vtable = &.{ .drain = @This().drain },
            },
        };
    }

    fn drain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
        const this: *@This() = @alignCast(@fieldParentPtr("writer", w));
        _ = splat;

        const buffered = w.buffered();
        if (buffered.len > 0) print("(b) {X}\n", .{buffered});
        _ = try this.out.write(buffered);
        try this.out.flush();
        _ = w.consumeAll();

        print("{X}\n", .{data[0]});
        const written = try this.out.write(data[0]);
        try this.out.flush();
        return written;
    }
};
//
// pub const LoggingReader = struct {
//     reader: Reader,
//     in: *Reader,
//
//     pub fn init(
//         in: *Reader,
//         buffer: []u8,
//     ) @This() {
//         return .{
//             .in = in,
//             .reader = .{
//                 .buffer = buffer,
//                 .end = 0,
//                 .seek = 0,
//                 .vtable = &.{ .stream = @This().stream },
//             },
//         };
//     }
//
//     fn stream(r: *Reader, w: *Writer, limit: std.Io.Limit) Reader.StreamError!usize {
//         const this: *@This() = @alignCast(@fieldParentPtr("reader", r));
//         const data = limit.slice(try w.writableSliceGreedy(1));
//         var vec: [1][]u8 = .{data};
//         const n = try this.in.readVec(&vec);
//         // this.rc4.processSlice(data[0..n]);
//         // Here;
//         w.advance(n);
//         return n;
//     }
// };
