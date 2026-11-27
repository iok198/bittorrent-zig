const std = @import("std");
const Bencode = @import("bencode.zig");
const IpAddress = std.Io.net.IpAddress;

pub const BitTorrent = struct {
    const Self = @This();

    announce: []const u8,
    info: BitInfo,

    pub fn readFile(allocator: std.mem.Allocator, io: std.Io, file: []const u8) !Self {
        const bencodeFile = try std.Io.Dir.cwd().readFileAlloc(io, file, allocator, .unlimited);
        const torrent = try Bencode.decode(allocator, BitTorrent, bencodeFile);

        if (torrent.info.pieces.len % 20 != 0) return error.invalidPieces;
        return torrent;
    }

    pub fn pieces(self: *const Self) []const [20]u8 {
        const pieceHashes: []const [20]u8 = @ptrCast(self.info.pieces);
        return pieceHashes;
    }

    pub fn infoHash(self: *const Self) ![20]u8 {
        var buffer: [1024]u8 = undefined;
        var writer: std.Io.Writer.Hashing(std.crypto.hash.Sha1) = .init(buffer[0..]);
        try Bencode.encode(&writer.writer, self.info);
        try writer.writer.flush();
        var hash_buffer: [20]u8 = undefined;
        writer.hasher.final(&hash_buffer);
        return hash_buffer;
    }

    pub fn getPeers(self: *const Self, allocator: std.mem.Allocator, io: std.Io) !TrackerResponse {
        var client = std.http.Client{ .allocator = allocator, .io = io };
        defer client.deinit();
        var bodyWriter = std.Io.Writer.Allocating.init(allocator);
        defer bodyWriter.deinit();

        const hash = try self.infoHash();
        var hash_writer = std.Io.Writer.Allocating.init(allocator);
        defer hash_writer.deinit();
        try std.Uri.Component.percentEncode(&hash_writer.writer, &hash, isUnreserved);
        const peer_id: [20]u8 = "iok198______________".*;
        const url = try allocator.print(
            \\{s}?peer_id={s}&left={d}&port=6881&downloaded=0&uploaded=0&compact=1&info_hash={s}
        , .{ self.announce, peer_id, self.info.length, hash_writer.written() });

        _ = try client.fetch(.{
            .location = .{ .url = url },
            .method = .GET,
            .response_writer = &bodyWriter.writer,
        });

        const resp = try Bencode.decode(allocator, struct { peers: []const u8, interval: u32 }, bodyWriter.written());
        if (resp.peers.len % 6 != 0) return error.BadPeersLength;

        const peers: []const [6]u8 = @ptrCast(resp.peers);
        var peers_list: []IpAddress = try allocator.alloc(IpAddress, peers.len);

        for (peers, 0..) |peer, i| {
            const port = std.mem.readInt(u16, &[2]u8{ peer[4], peer[5] }, .big);
            const bytes: [4]u8 = @constCast(peer[0..4]).*;
            const address = IpAddress{ .ip4 = .{ .bytes = bytes, .port = port } };
            peers_list[i] = address;
        }

        return .{ .peers = peers_list, .interval = resp.interval };
    }
};
pub const BitInfo = struct { length: u32, name: []const u8, @"piece length": u32, pieces: []const u8 };
pub const TrackerResponse = struct { peers: []IpAddress, interval: u32 };

fn isUnreserved(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '.' or c == '_' or c == '~' or c == '&' or c == '=' or c == '/' or c == ':' or c == '?';
}
