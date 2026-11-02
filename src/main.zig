const std = @import("std");
const Io = std.Io;

const bittorrent_zig = @import("bittorrent_zig");
const Tokenizer = @import("tokenizer.zig");
const Token = Tokenizer.Token;
const Parser = @import("parser.zig");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const input = "d7:meaningi42e4:wiki7:bencodee";
    var tokenizer = Tokenizer.init(input);

    const expr = try Parser.parse(arena, &tokenizer);
    std.debug.print("{any}", .{expr});
}
