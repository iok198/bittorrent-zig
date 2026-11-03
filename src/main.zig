const std = @import("std");
const Io = std.Io;

const bittorrent_zig = @import("bittorrent_zig");

const Parser = @import("parser.zig");
const Tokenizer = @import("tokenizer.zig");
const Bencode = @import("bencode.zig");

const bla = struct { meaning: u8, wiki: []const u8, nums: []i32 };
const people = struct { data: []struct { name: []const u8, age: u8 } };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const input = "d4:datald4:name3:bob3:agei32eeee";
    const wa = try Bencode.decode(arena, people, input);
    std.debug.print("data: {any}\n", .{wa});
}
