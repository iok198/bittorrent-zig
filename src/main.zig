const std = @import("std");
const Io = std.Io;

const bittorrent_zig = @import("bittorrent_zig");

const Parser = @import("parser.zig");
const Tokenizer = @import("Tokenizer.zig");
const Bencode = @import("bencode.zig");

// TODO: Add list of trackers

const BitTorrent = struct { announce: []const u8, comment: []const u8, @"created by": ?[]const u8, @"creation date": i32, encoding: ?[]const u8, info: BitInfo, @"announce-list": ?[][][]u8 };
const BitInfo = struct { length: ?u32, name: []const u8, @"piece length": u32, pieces: []u8, path: ?[][][]u8 };

fn printStruct(value: anytype, comptime tab: u8) void {
    const tabs: [tab]u8 = @splat('\t');

    switch (@typeInfo(@TypeOf(value))) {
        .@"struct" => |@"struct"| {
            inline for (@"struct".field_names, @"struct".field_types) |field_name, field_type| {
                const val = @field(value, field_name);
                state: switch (@typeInfo(field_type)) {
                    .int => {
                        std.debug.print("{s}{s}: {d}\n", .{ tabs, field_name, val });
                    },
                    .pointer => |ptr| {
                        if (ptr.size != .slice) break;
                        if (ptr.child == u8) {
                            std.debug.print("{s}{s}: \"{s}\"\n", .{ tabs, field_name, val });
                            break :state;
                        }

                        std.debug.print("{s}{s}: [", .{ tabs, field_name });
                        defer std.debug.print("{s}: ]", .{tabs});

                        for (val) |item| {
                            printStruct(item, tab + 1);
                        }
                    },
                    .@"struct" => {
                        std.debug.print("{s}{s}:\n", .{ tabs, field_name });
                        printStruct(val, tab + 1);
                    },
                    .optional => {
                        if (val) |inner| {
                            std.debug.print("{s}{s}: \n", .{ tabs, field_name });
                            printStruct(inner, tab + 1);
                        } else {
                            std.debug.print("{s}{s}: X\n", .{ tabs, field_name });
                        }
                    },
                    else => {
                        std.debug.print("{s}{s}: {any}\n", .{ tabs, field_name, val });
                    },
                }
            }
        },
        .optional => {
            if (value) |inner| printStruct(inner, tab + 1);
        },
        .int => std.debug.print("{s}{d}\n", .{ tabs, value }),
        .pointer => |ptr| {
            if (ptr.size != .slice) return;
            if (ptr.child == u8) {
                std.debug.print("{s}\"{s}\"\n", .{ tabs, value });
                return;
            }

            std.debug.print("{s}[\n", .{
                tabs,
            });
            defer std.debug.print("{s}]\n", .{tabs});

            for (value) |item| {
                printStruct(item, tab + 1);
            }
        },
        else => |wa| {
            std.debug.print("bad type: {any}\nval: {any}\n", .{ wa, @TypeOf(value) });
            return;
        },
    }
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const Dir = std.Io.Dir;
    const bencode = try Dir.cwd().readFileAlloc(io, "./SXSW_2016_Showcasing_Artists_Part1.torrent", arena, .unlimited);
    const torrent = try Bencode.decode(arena, BitTorrent, bencode);
    std.debug.print("BitTorrent:\n", .{});
    printStruct(torrent, 1);
}
