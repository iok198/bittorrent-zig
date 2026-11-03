const std = @import("std");
const Io = std.Io;

const bittorrent_zig = @import("bittorrent_zig");

const Parser = @import("parser.zig");
const Tokenizer = @import("tokenizer.zig");

const bla = struct { meaning: u8, wiki: []const u8, nums: []i32 };

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const input = "d7:meaningi42e4:wiki7:bencode4:numsli1ei2ei3eee";
    var tokenizer = Tokenizer.init(input);
    var expr = try Parser.parse(arena, &tokenizer);
    const wa = try Parser.toStruct(arena, bla, &expr);
    std.debug.print("data: {any}\n", .{wa});
    std.debug.print("{s}\n", .{try Parser.toString(arena, expr)});
}
