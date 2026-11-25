const std = @import("std");
const Io = std.Io;

const Parser = @import("parser.zig");
const Tokenizer = @import("Tokenizer.zig");
const Bencode = @import("bencode.zig");
const BitTorrent = @import("Torrent.zig").BitTorrent;

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
        const stream = try address.connect(io, .{ .mode = .stream });
        defer stream.close(io);
        var payload: [68]u8 = undefined;
        var payload_writer = std.Io.Writer.fixed(&payload);
        try payload_writer.print("{u}BitTorrent protocol{s}{s}{s}", .{ 19, @as([8]u8, @splat(0)), try torrent.infoHash(allocator), "01234567890123456789" });

        var buffer: [68]u8 = undefined;
        try stream.socket.send(io, &address, &payload);
        const response = try stream.socket.receive(io, &buffer);
        try stdout.interface.print("Peer ID: {x}\n", .{response.data[48..]});
    } else {
        return error.InvalidCommand;
    }
}
