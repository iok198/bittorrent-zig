const std = @import("std");
const Io = std.Io;

const bittorrent_zig = @import("bittorrent_zig");

const Parser = @import("parser.zig");
const Tokenizer = @import("Tokenizer.zig");
const Bencode = @import("bencode.zig");

// TODO: Add list of trackers

const BitTorrent = struct { announce: []const u8, comment: []const u8, @"created by": ?[]const u8, @"creation date": i32, encoding: ?[]const u8, info: BitInfo };
const BitInfo = struct { length: ?u32, name: []const u8, @"piece length": u32, pieces: []u8, path: ?[][]const u8 };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const Dir = std.Io.Dir;
    const bencode = try Dir.cwd().readFileAlloc(io, "./ubuntu-16.04-desktop-amd64.iso.torrent", arena, .unlimited);
    const torrent = try Bencode.decode(arena, BitTorrent, bencode);
    std.debug.print("announce: {s}\n", .{torrent.announce});
    std.debug.print("comment: {s}\n", .{torrent.comment});
    std.debug.print("length: {any}\n", .{torrent.info.length});
    std.debug.print("piece length: {d}\n", .{torrent.info.@"piece length"});
    std.debug.print("name: {s}\n", .{torrent.info.name});
    std.debug.print("pieces length: {d}\n", .{torrent.info.pieces.len});
    std.debug.print("path: {any}\n", .{torrent.info.path});
}
