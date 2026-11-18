const std = @import("std");
const Io = std.Io;

const Parser = @import("parser.zig");
const Tokenizer = @import("Tokenizer.zig");
const Bencode = @import("bencode.zig");
const Torrent = @import("Torrent.zig");

const File = struct { path: [][]u8, length: u32 };
const BitTorrent = struct { announce: []const u8, comment: []const u8, @"created by": ?[]const u8, @"creation date": i32, encoding: ?[]const u8, info: BitInfo, @"announce-list": ?[][][]u8 };
const BitInfo = struct { length: ?u32, name: []const u8, @"piece length": u32, pieces: []u8, path: ?[][][]u8, files: ?[]File };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    var argsIter = init.minimal.args.iterate();
    _ = argsIter.next();
    const command = argsIter.next() orelse return error.InvalidArgLength;
    const eql = std.mem.eql;

    // const torrentFile = argsIter.next() orelse return error.InvalidArgLength;
    const stdout = std.Io.File.stdout();

    if (eql(u8, "decode", command)) {
        const input = argsIter.next() orelse return error.InvalidArgLength;
        var tokenizer = Tokenizer.init(input);
        while (tokenizer.next()) |token| {
            try stdout.writeStreamingAll(io, try token.toString(arena));
            if (token == .eof) break;
        } else |err| return err;
    } else if (eql(u8, "parse", command)) {
        // const bencodeFile = try std.Io.Dir.cwd().readFileAlloc(io, torrentFile, arena, .unlimited);
        // var tokenizer = Tokenizer.init(bencodeFile);
        // var parsed = try Parser.parse(arena, &tokenizer);
        // defer parsed.deinit(arena);
        // const stringified = try parsed.toString(arena);
        // defer arena.free(stringified);
        // try stdout.writeStreamingAll(io, stringified);
    } else if (eql(u8, "decode", command)) {
        // const bencodeFile = try std.Io.Dir.cwd().readFileAlloc(io, torrentFile, arena, .unlimited);
        // const torrent = try Bencode.decode(arena, BitTorrent, bencodeFile);
        // std.debug.print("BitTorrent:\n", .{});
        // Bencode.printStruct(torrent, 1);
    } else if (eql(u8, "torrent", command)) {
        // const bencodeFile = try std.Io.Dir.cwd().readFileAlloc(io, torrentFile, arena, .unlimited);
        // const torrent = try Torrent.BitTorrent.from(arena, bencodeFile);
        // std.debug.print("BitTorrent:\n", .{});
        // Bencode.printStruct(torrent, 1);
        // std.debug.print("{any}", .{torrent});
    } else {
        return error.InvalidCommand;
    }
}
