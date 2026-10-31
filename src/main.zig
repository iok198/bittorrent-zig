const std = @import("std");
const Io = std.Io;

const bittorrent_zig = @import("bittorrent_zig");
const Tokenizer = @import("tokenizer.zig");
const Parser = @import("parser.zig");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const input = "d7:meaningi42e4:wiki7:bencodee";
    // const input = "0:i32e";
    const tokens = try Tokenizer.tokenize(arena, input);
    Tokenizer.printTokens(tokens.items);
    const expr = try Parser.parse(tokens.items);
    std.debug.print("{any}", .{expr});
}
