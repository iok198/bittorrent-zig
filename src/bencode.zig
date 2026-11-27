const std = @import("std");

const Parser = @import("parser.zig");
const Tokenizer = @import("Tokenizer.zig");

pub const DecodeError = Parser.ParseError || error{ unexpectedType, missingField };

pub fn decode(allocator: std.mem.Allocator, T: type, input: []const u8) DecodeError!T {
    var tokenizer = Tokenizer.init(input);
    var expr = try Parser.parse(allocator, &tokenizer);
    defer expr.deinit(allocator);
    const result = try toStruct(allocator, T, &expr);
    return result.value;
}

pub fn encode(writer: *std.Io.Writer, val: anytype) !void {
    state: switch (@typeInfo(@TypeOf(val))) {
        .optional => {
            if (val) |v| {
                try encode(writer, v);
            }
        },
        .int => try writer.print("i{d}e", .{val}),
        .array => |arr| {
            if (arr.child == u8) {
                try writer.print("{d}:{s}", .{ val.len, val });
                break :state;
            }

            try writer.printAsciiChar('l', .{});
            for (val) |item| try encode(writer, item);
            try writer.printAsciiChar('e', .{});
        },
        .@"struct" => |s| {
            try writer.printAsciiChar('d', .{});
            comptime var sorted_fields: [s.field_names.len]Entry = undefined;
            inline for (s.field_names, s.field_types, 0..) |field_name, field_type, i| {
                sorted_fields[i] = .{ .key = field_name, .val = field_type };
            }
            comptime std.mem.sort(Entry, &sorted_fields, {}, lessThan);
            inline for (sorted_fields) |entry| {
                // TODO: Add logic to filter out optionals that don't pass though

                try encode(writer, entry.key);
                try encode(writer, @field(val, entry.key));
            }
            try writer.printAsciiChar('e', .{});
        },
        .pointer => |ptr| {
            if (ptr.size == .one) {
                try encode(writer, val.*);
                break :state;
            }

            if (ptr.child == u8 and ptr.size == .slice) {
                try writer.print("{d}:{s}", .{ val.len, val });
                break :state;
            }

            try writer.printAsciiChar('l', .{});
            for (val) |item| {
                try encode(writer, item);
            }
            try writer.printAsciiChar('e', .{});
        },
        else => |bad_field| {
            std.debug.print("bad field: {any}\n", .{bad_field});
            return error.unexpectedField;
        },
    }
}

const Entry = struct { key: []const u8, val: type };
fn lessThan(_: void, lhs: Entry, rhs: Entry) bool {
    return std.mem.order(u8, lhs.key, rhs.key) == .lt;
}

fn bencodeWrapper(comptime T: type) type {
    return struct { value: T };
}

fn toStruct(allocator: std.mem.Allocator, T: type, expr: *Parser.Expr) DecodeError!bencodeWrapper(T) {
    switch (@typeInfo(T)) {
        .optional => |opt| {
            return bencodeWrapper(T){
                .value = res: {
                    if (toStruct(allocator, opt.child, expr)) |value| {
                        break :res value.value;
                    } else |_| {
                        break :res null;
                    }
                },
            };
        },
        .int => {
            switch (expr.*) {
                .int => |num| return bencodeWrapper(T){ .value = @intCast(num) },
                else => return DecodeError.unexpectedType,
            }
        },
        .pointer => |ptr| {
            if (ptr.size != .slice) return DecodeError.unexpectedType;
            switch (expr.*) {
                .string => |str| {
                    if (ptr.child == u8) {
                        return bencodeWrapper(T){ .value = @constCast(str) };
                    } else {
                        return DecodeError.unexpectedType;
                    }
                },
                .list => |list| {
                    if (list.len == 0) return bencodeWrapper(T){ .value = &.{} };

                    var items = try allocator.alloc(ptr.child, list.len);
                    for (list, 0..) |*item, i| {
                        const val = toStruct(allocator, ptr.child, item) catch |err| {
                            allocator.free(items);
                            return err;
                        };
                        items[i] = val.value;
                    }
                    return bencodeWrapper(T){ .value = items };
                },
                else => return DecodeError.unexpectedType,
            }
        },
        .@"struct" => |s| {
            switch (expr.*) {
                .dict => |dict| {
                    var result: T = undefined;

                    inline for (s.field_types, s.field_names) |field_type, field_name| {
                        if (dict.get(field_name)) |entry| {
                            const value = try toStruct(allocator, field_type, @constCast(&entry));
                            @field(result, field_name) = value.value;
                        } else {
                            if (@typeInfo(field_type) == .optional) {
                                @field(result, field_name) = null;
                            } else {
                                std.debug.print("Missing field: {s}\n", .{field_name});
                                return DecodeError.missingField;
                            }
                        }
                    }

                    return bencodeWrapper(T){ .value = result };
                },
                else => return DecodeError.unexpectedType,
            }
        },
        else => return DecodeError.unexpectedType,
    }
}

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

test decode {
    const allocator = std.testing.allocator;
    const Person = struct { name: []const u8, age: u8 };
    const People = struct { data: []Person };
    const input = "d4:datald4:name3:bob3:agei32eeee";
    const result = try decode(allocator, People, input);
    defer allocator.free(result.data);
    try expectEqual(1, result.data.len);
    try expectEqual(32, result.data[0].age);
    try expectEqualStrings("bob", result.data[0].name);
    const MysteriousPerson = struct { name: []const u8, age: ?u8 };
    const normal = try decode(allocator, MysteriousPerson, "d4:name3:bob3:agei32ee");
    try expectEqualStrings("bob", normal.name);
    try expectEqual(32, normal.age.?);
    const spy = try decode(allocator, MysteriousPerson, "d4:name3:bobe");
    try expectEqualStrings("bob", spy.name);
    try expectEqual(null, spy.age);
    try expectError(DecodeError.missingField, decode(allocator, MysteriousPerson, "d8:realname5:bobbye"));
    try expectError(DecodeError.unexpectedType, decode(allocator, Person, "d4:name3:bob3:age6:secrete"));
    try expectError(DecodeError.unexpectedType, decode(allocator, *People, input));
}

fn testEncode(expected: []const u8, val: anytype) !void {
    var writer = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer writer.deinit();
    try encode(&writer.writer, val);
    try expectEqualStrings(expected, writer.written());
}

test encode {
    try testEncode("i32e", @as(i32, 32));
    try testEncode("3:bob", "bob");
    try testEncode("li1ei2ei3ee", &[_]i32{ 1, 2, 3 });
    try testEncode("l3:one3:two5:threee", &[_][]const u8{ "one", "two", "three" });
    try testEncode("lli1eeli2eee", &[_][]const i32{ &.{1}, &.{2} });
    const numNums: [2][1][]const u8 = .{ [1][]const u8{"one"}, [1][]const u8{"two"} };
    try testEncode("ll3:oneel3:twoee", numNums);
    const Person = struct { name: []const u8, age: u8 };
    try testEncode("d3:agei32e4:name3:bobe", Person{ .name = "bob", .age = 32 });
    try testEncode("ld3:agei32e4:name3:bobed3:agei19e4:name4:jeffee", &[_]Person{ .{ .name = "bob", .age = 32 }, .{ .name = "jeff", .age = 19 } });
    const Relationships = struct { friends: []const Person, enemies: []Person = &.{} };
    try testEncode("d7:enemiesle7:friendsld3:agei32e4:name3:bobeee", Relationships{ .friends = &[_]Person{.{ .name = "bob", .age = 32 }} });
}
