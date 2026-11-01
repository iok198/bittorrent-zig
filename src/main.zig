const std = @import("std");
const Io = std.Io;

const bittorrent_zig = @import("bittorrent_zig");
const Tokenizer = @import("tokenizer.zig");
const Token = Tokenizer.Token;
const Parser = @import("parser.zig");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    // const input = "d7:meaningi42e4:wiki7:bencodee";
    const input = "li32ee";
    // const input = "0:i32e";
    const tokens = try Tokenizer.tokenize(arena, input);
    Tokenizer.printTokens(tokens.items);
    // std.debug.print("{any}", .{tokens.items[0]});

    // std.debug.print("wawa: {any}", .{enumField(Token, token, "string")});

    // const expr = try Parser.parse(arena, tokens.items);
    // std.debug.print("{any}", .{expr});
}
