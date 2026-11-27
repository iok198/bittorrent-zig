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
        try stdout.interface.print("Info Hash: {x}\n", .{try torrent.infoHash()});
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
        var url_buffer: [Io.net.HostName.max_len]u8 = undefined;
        const torrentFile = argsIter.next() orelse return error.InvalidArgLength;
        const url = argsIter.next() orelse return error.InvalidArgLength;

        const formattedUrl = try allocator.print("http://{s}", .{url});
        defer allocator.free(formattedUrl);
        const torrent = try BitTorrent.readFile(allocator, io, torrentFile);
        const uri = try std.Uri.parse(formattedUrl);
        var client = std.http.Client{ .allocator = allocator, .io = io };

        var connection = try client.connectTcp(try .fromUri(uri, url_buffer[0..]), uri.port.?, .plain);
        defer connection.destroy(io);
        const reader = connection.reader();
        const writer = connection.writer();

        const hs = try Peer.handshake(reader, writer, try torrent.infoHash());
        try stdout.interface.print("Peer ID: {x}\n", .{hs.peer_id});
    } else if (eql(u8, "download_piece", command)) {
        _ = argsIter.next();
        _ = argsIter.next();
        const torrentFile = argsIter.next() orelse return error.InvalidArgLength;
        _ = argsIter.next();
        var url_buffer: [Io.net.HostName.max_len]u8 = undefined;
        const torrent = try BitTorrent.readFile(allocator, io, torrentFile);
        const hash = try torrent.infoHash();
        const tracker_resp = try torrent.getPeers(allocator, io);
        var client = std.http.Client{ .allocator = allocator, .io = io };
        const connections = c: {
            var connections = try allocator.alloc(*std.http.Client.Connection, tracker_resp.peers.len);
            var i: usize = 0;

            for (tracker_resp.peers) |address| {
                const formatted_uri = try allocator.print("http://{f}", .{address});
                defer allocator.free(formatted_uri);
                const uri = std.Uri.parse(formatted_uri) catch continue;
                const connection = client.connectTcp(try .fromUri(uri, url_buffer[0..]), uri.port.?, .plain) catch continue;
                connections[i] = connection;
                i += 1;
            }

            if (i == 0) return error.NoAvailablePeers;
            break :c connections[0..i];
        };
        defer {
            for (connections) |connection| connection.destroy(io);
            allocator.free(connections);
        }

        var group = Io.Group.init;
        for (connections) |connection| group.async(io, download, .{ connection, hash });
        try group.await(io);
    } else {
        return error.InvalidCommand;
    }
}

fn download(connection: *std.http.Client.Connection, info_hash: [20]u8) Io.Cancelable!void {
    downloadPiece(connection, info_hash) catch return error.Canceled;
}

fn downloadPiece(connection: *std.http.Client.Connection, info_hash: [20]u8) !void {
    const reader = connection.reader();
    const writer = connection.writer();
    const handshake = try Peer.handshake(reader, writer, info_hash);
    std.debug.print("Peer ID: {x}\n", .{handshake.peer_id});

    if (handshake.bitfield) |bitfield| {
        std.debug.print("Bitfield included: {any}\n", .{bitfield});
    } else {
        const bitfield = try Peer.receiveMessage(reader, .bitfield);
        std.debug.print("Bitfield requested: {any}\n", .{bitfield});
    }

    try Peer.sendMessage(writer, .interested);
    std.debug.print("Sent interested\n", .{});
    try Peer.receiveMessage(reader, .unchoke);
    std.debug.print("Received unchoke\n", .{});
}
