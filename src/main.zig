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
    // comment: []const u8,
    // @"created by": ?[]const u8,
    // @"creation date": i32,
    // encoding: ?[]const u8,
    // @"announce-list": ?[][][]u8
};
const BitInfo = struct { length: u32, name: []const u8, @"piece length": u32, pieces: []u8, path: ?[][][]u8, files: ?[]File };

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
        const wa = try Bencode.encode(arena, torrent.info);
        var waTok = Tokenizer.init(wa);
        const waPa = try Parser.parse(arena, &waTok);
        std.debug.print("test: {s}\n", .{try waPa.toString(arena, true)});
        var hasher = std.crypto.hash.Sha1.init(.{});
        // for (0..torrent.info.pieces.len / 20) |i| {
        //     hasher.update(torrent.info.pieces[i * 20 ..][0..20]);
        // }
        hasher.update(torrent.info.pieces);
        // hasher.update();
        var hash_buffer: [20]u8 = undefined;
        hasher.final(&hash_buffer);
        try stdout.interface.print("Info Hash: {x}\n", .{hash_buffer});
    } else {
        return error.InvalidCommand;
    }
}
