const std = @import("std");
const Io = std.Io;

const Parser = @import("parser.zig");
const Tokenizer = @import("Tokenizer.zig");
const Bencode = @import("bencode.zig");
const Torrent = @import("Torrent.zig");

const File = struct { path: ?[][]u8, length: u32 };
const BitTorrent = struct {
    announce: []const u8,
    @"announce-list": ?[][]const u8,
    info: BitInfo,

    pub fn hash(self: *const @This(), allocator: std.mem.Allocator) ![20]u8 {
        const encoded_info = try Bencode.encode(allocator, self.info);
        defer allocator.free(encoded_info);
        var hasher = std.crypto.hash.Sha1.init(.{});
        hasher.update(encoded_info);
        var hash_buffer: [20]u8 = undefined;
        hasher.final(&hash_buffer);
        return hash_buffer;
    }
};
const BitInfo = struct { length: u32, name: []const u8, @"piece length": u32, pieces: []u8 };
const TrackerResponse = struct { peers: []const u8, interval: u32 };

fn isUnreserved(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '.' or c == '_' or c == '~' or c == '&' or c == '=' or c == '/' or c == ':' or c == '?';
}

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
        try stdout.interface.print("Info Hash: {x}\n", .{try torrent.hash(arena)});
        try stdout.interface.print("Piece Length: {d}\n", .{torrent.info.@"piece length"});
        try stdout.interface.print("Piece Hashes:\n", .{});
        std.debug.assert(torrent.info.pieces.len % 20 == 0);
        const pieceHashes: [][20]u8 = @ptrCast(torrent.info.pieces);
        for (pieceHashes) |piece| {
            try stdout.interface.print("{x}\n", .{piece});
        }
    } else if (eql(u8, "peers", command)) {
        const torrentFile = argsIter.next() orelse return error.InvalidArgLength;
        const bencodeFile = try std.Io.Dir.cwd().readFileAlloc(io, torrentFile, arena, .unlimited);
        const torrent = try Bencode.decode(arena, BitTorrent, bencodeFile);
        var client = std.http.Client{ .allocator = arena, .io = io };
        defer client.deinit();
        var bodyWriter = std.Io.Writer.Allocating.init(arena);
        defer bodyWriter.deinit();

        const hash = try torrent.hash(arena);
        var hash_writer = std.Io.Writer.Allocating.init(arena);
        defer hash_writer.deinit();
        try std.Uri.Component.percentEncode(&hash_writer.writer, &hash, isUnreserved);
        const peer_id: [20]u8 = "iok198______________".*;
        const url = try arena.print(
            \\{s}?peer_id={s}&left={d}&port=6881&downloaded=0&uploaded=0&compact=1&info_hash={s}
        , .{ torrent.announce, peer_id, torrent.info.length, hash_writer.written() });

        _ = try client.fetch(.{
            .location = .{ .url = url },
            .method = .GET,
            .response_writer = &bodyWriter.writer,
        });

        const resp = try Bencode.decode(arena, TrackerResponse, bodyWriter.written());
        std.debug.assert(resp.peers.len % 6 == 0);
        const peers: []const [6]u8 = @ptrCast(resp.peers);
        for (peers) |peer| {
            const port = std.mem.readInt(u16, &[2]u8{ peer[4], peer[5] }, .big);
            try stdout.interface.print("{d}.{d}.{d}.{d}:{d}\n", .{ peer[0], peer[1], peer[2], peer[3], port });
        }
    } else if (eql(u8, "bencode", command)) {
        const torrentFile = argsIter.next() orelse return error.InvalidArgLength;
        const bencodeFile = try std.Io.Dir.cwd().readFileAlloc(io, torrentFile, arena, .unlimited);
        var tokenizer = Tokenizer.init(bencodeFile);
        var parsed = try Parser.parse(arena, &tokenizer);
        defer parsed.deinit(arena);
        std.debug.print("{s}\n", .{try parsed.toString(arena, true)});
    } else {
        return error.InvalidCommand;
    }
}
