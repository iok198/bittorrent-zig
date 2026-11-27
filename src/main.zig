const std = @import("std");
const Io = std.Io;

const Parser = @import("parser.zig");
const Tokenizer = @import("Tokenizer.zig");
const Bencode = @import("bencode.zig");
const BitTorrent = @import("Torrent.zig").BitTorrent;
const Peer = @import("Peer.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    var argsIter = init.minimal.args.iterate();
    _ = argsIter.next();
    const command = argsIter.next() orelse return error.InvalidArgLength;
    const eql = std.mem.eql;

    var stdout = std.Io.File.stdout().writer(io, &.{});

    if (eql(u8, "decode", command)) {
        const input = argsIter.next() orelse return error.InvalidArgLength;
        var tokenizer = Tokenizer.init(input);
        var parsed = try Parser.parse(allocator, &tokenizer);
        defer parsed.deinit(allocator);
        try stdout.interface.print("{s}", .{try parsed.toString(allocator, true)});
    } else if (eql(u8, "info", command)) {
        const torrentFile = argsIter.next() orelse return error.InvalidArgLength;
        const torrent = try BitTorrent.readFile(allocator, io, torrentFile);
        try stdout.interface.print("Tracker URL: {s}\n", .{torrent.announce});
        try stdout.interface.print("Length: {d}\n", .{torrent.info.length});
        try stdout.interface.print("Info Hash: {x}\n", .{try torrent.infoHash(allocator)});
        try stdout.interface.print("Piece Length: {d}\n", .{torrent.info.@"piece length"});
        try stdout.interface.print("Piece Hashes:\n", .{});
        for (torrent.pieces()) |piece| {
            try stdout.interface.print("{x}\n", .{piece});
        }
    } else if (eql(u8, "peers", command)) {
        const torrentFile = argsIter.next() orelse return error.InvalidArgLength;
        const torrent = try BitTorrent.readFile(allocator, io, torrentFile);
        const resp = try torrent.getPeers(allocator, io);
        for (resp.peers) |peer| {
            try stdout.interface.print("{f}\n", .{peer});
        }
    } else if (eql(u8, "bencode", command)) {
        const torrentFile = argsIter.next() orelse return error.InvalidArgLength;
        const bencodeFile = try std.Io.Dir.cwd().readFileAlloc(io, torrentFile, allocator, .unlimited);
        var tokenizer = Tokenizer.init(bencodeFile);
        var parsed = try Parser.parse(allocator, &tokenizer);
        defer parsed.deinit(allocator);
        std.debug.print("{s}\n", .{try parsed.toString(allocator, true)});
    } else if (eql(u8, "handshake", command)) {
        const torrentFile = argsIter.next() orelse return error.InvalidArgLength;
        const url = argsIter.next() orelse return error.InvalidArgLength;
        const torrent = try BitTorrent.readFile(allocator, io, torrentFile);
        const address = try std.Io.net.IpAddress.parseLiteral(url);
        var peer = Peer{ .stream = try address.connect(io, .{ .mode = .stream, .protocol = .tcp }) };
        defer peer.close(io);
        const response = try peer.handshake(io, try torrent.infoHash(allocator));
        try stdout.interface.print("Peer ID: {x}\n", .{response.peer_id});
    } else if (eql(u8, "download_piece", command)) {
        _ = argsIter.next();
        _ = argsIter.next();
        const torrentFile = argsIter.next() orelse return error.InvalidArgLength;
        _ = argsIter.next();
        std.debug.print("File: {s}\n", .{torrentFile});
        const torrent = try BitTorrent.readFile(allocator, io, torrentFile);
        const tracker_resp = try torrent.getPeers(allocator, io);
        const peers = p: {
            var peers = try allocator.alloc(Peer, tracker_resp.peers.len);
            var i: usize = 0;
            for (tracker_resp.peers) |address| {
                peers[i] = Peer{ .stream = address.connect(io, .{ .mode = .stream, .protocol = .tcp }) catch continue };
                i += 1;
            }
            if (i == 0) return error.NoAvailablePeers;
            break :p peers[0..i];
        };
        defer {
            for (peers) |*peer| peer.close(io);
            allocator.free(peers);
        }

        const info_hash = try torrent.infoHash(allocator);
        var group = Io.Group.init;
        for (peers) |*peer| try group.concurrent(io, Peer.getPiece, .{ peer, io, info_hash });
        try group.await(io);
    } else {
        return error.InvalidCommand;
    }
}
