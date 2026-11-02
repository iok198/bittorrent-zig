const std = @import("std");
const Io = std.Io;

const bittorrent_zig = @import("bittorrent_zig");
const Tokenizer = @import("tokenizer.zig");
const Token = Tokenizer.Token;
const Parser = @import("parser.zig");

fn toString(allocator: std.mem.Allocator, input: Parser.Expr) ![]u8 {
    var result: std.ArrayList(u8) = .empty;

    switch (input) {
        .int => |num| try result.print(allocator, "{d}", .{num}),
        .string => |str| try result.print(allocator, "\"{s}\"", .{str}),
        .list => |list| {
            try result.print(allocator, "[ ", .{});
            for (list, 0..) |item, i| {
                if (i == 0) {
                    try result.print(allocator, "{s}", .{try toString(allocator, item)});
                } else {
                    try result.print(allocator, ", {s}", .{try toString(allocator, item)});
                }
            }
            try result.print(allocator, " ]", .{});
        },
        .dict => |dict| {
            try result.print(allocator, "{{ ", .{});
            for (dict, 0..) |entry, i| {
                if (i == 0) {
                    try result.print(allocator, "\"{s}\": {s}", .{ entry.key, try toString(allocator, entry.val) });
                } else {
                    try result.print(allocator, ", \"{s}\": {s}", .{ entry.key, try toString(allocator, entry.val) });
                }
            }
            try result.print(allocator, " }}", .{});
        },
    }

    return result.toOwnedSlice(allocator);
}

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const input = "d7:meaningi42e4:wiki7:bencode4:numsli1ei2ei3eee";
    var tokenizer = Tokenizer.init(input);
    const expr = try Parser.parse(arena, &tokenizer);
    std.debug.print("{s}\n", .{try toString(arena, expr)});
}
