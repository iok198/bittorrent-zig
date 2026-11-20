const std = @import("std");
const Io = std.Io;

const Parser = @import("parser.zig");
const Tokenizer = @import("Tokenizer.zig");
const Bencode = @import("bencode.zig");
const Torrent = @import("Torrent.zig");

const File = struct { path: ?[][]u8, length: u32 };
const BitTorrent = struct {
    announce: []const u8,
    info: BitInfo,
};
const BitInfo = struct { length: u32, name: []const u8, @"piece length": u32, pieces: []u8 };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    var argsIter = init.minimal.args.iterate();
    _ = argsIter.next();
    const command = argsIter.next() orelse return error.InvalidArgLength;
    const eql = std.mem.eql;

    var stdout = std.Io.File.stdout().writer(io, &.{});

    if (eql(u8, "decode", command)) {
        const input = argsIter.next() orelse return error.InvalidArgLength;
        var tokenizer = Tokenizer.init(input);
        var parsed = try Parser.parse(arena, &tokenizer);
        defer parsed.deinit(arena);
        try stdout.interface.print("{s}", .{try parsed.toString(arena, true)});
    } else if (eql(u8, "info", command)) {
        const torrentFile = argsIter.next() orelse return error.InvalidArgLength;
        const bencodeFile = try std.Io.Dir.cwd().readFileAlloc(io, torrentFile, arena, .unlimited);
        const torrent = try Bencode.decode(arena, BitTorrent, bencodeFile);
        try stdout.interface.print("Tracker URL: {s}\n", .{torrent.announce});
        try stdout.interface.print("Length: {d}\n", .{torrent.info.length});
        const encoded_info = try Bencode.encode(arena, torrent.info);
        var hasher = std.crypto.hash.Sha1.init(.{});
        hasher.update(encoded_info);
        var hash_buffer: [20]u8 = undefined;
        hasher.final(&hash_buffer);
        try stdout.interface.print("Info Hash: {x}\n", .{hash_buffer});
        try stdout.interface.print("Piece Length: {d}\n", .{torrent.info.@"piece length"});
        try stdout.interface.print("Piece Hashes:\n", .{});
        std.debug.assert(torrent.info.pieces.len % 20 == 0);
        const pieceHashes: [][20]u8 = @ptrCast(torrent.info.pieces);
        for (pieceHashes) |piece| {
            try stdout.interface.print("{x}\n", .{piece});
        }
    } else {
        return error.InvalidCommand;
    }
}
