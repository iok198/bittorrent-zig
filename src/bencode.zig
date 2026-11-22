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

const Entry = struct { key: []u8, val: []u8 };
fn lessThan(_: void, lhs: Entry, rhs: Entry) std.math.Order {
    return std.mem.order(u8, lhs.key, rhs.key);
}

pub fn encode(allocator: std.mem.Allocator, val: anytype) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    state: switch (@typeInfo(@TypeOf(val))) {
        .optional => {
            if (val) |v| {
                const res = try encode(allocator, v);
                defer allocator.free(res);
                try result.appendSlice(allocator, res);
            }
        },
        .int => try result.print(allocator, "i{d}e", .{val}),
        .array => |arr| {
            if (arr.child == u8) {
                try result.print(allocator, "{d}:{s}", .{ val.len, val });
                break :state;
            }

            try result.append(allocator, 'l');
            for (val) |item| {
                const res = try encode(allocator, item);
                defer allocator.free(res);
                try result.appendSlice(allocator, res);
            }
            try result.append(allocator, 'e');
        },
        .@"struct" => |s| {
            try result.append(allocator, 'd');
            var sorted_fields: std.PriorityQueue(Entry, void, lessThan) = .initContext({});
            defer {
                var iter = sorted_fields.iterator();
                while (iter.next()) |entry| {
                    allocator.free(entry.val);
                }
                sorted_fields.deinit(allocator);
            }
            inline for (s.field_names) |field_name| {
                const encoded_val = try encode(allocator, @field(val, field_name));
                try sorted_fields.push(allocator, .{ .key = @constCast(field_name), .val = encoded_val });
            }
            var entryIter = sorted_fields.iterator();

            while (entryIter.next()) |entry| {
                const encodedKey = try encode(allocator, entry.key);
                defer allocator.free(encodedKey);
                try result.print(allocator, "{s}{s}", .{ encodedKey, entry.val });
            }
            try result.append(allocator, 'e');
        },
        .pointer => |ptr| {
            if (ptr.child == u8 and ptr.size == .slice or (@typeInfo(ptr.child) == .array and @typeInfo(ptr.child).array.child == u8)) {
                try result.print(allocator, "{d}:{s}", .{ val.len, val });
                break :state;
            }

            try result.append(allocator, 'l');
            for (val) |item| {
                const encoded_item = try encode(allocator, item);
                defer allocator.free(encoded_item);
                try result.appendSlice(allocator, encoded_item);
            }
            try result.append(allocator, 'e');
        },
        else => |bad_field| {
            std.debug.print("bad field: {any}\n", .{bad_field});
            return error.unexpectedField;
        },
    }

    return result.toOwnedSlice(allocator);
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
                                return DecodeError.missingField;
                            }
                        }
                    }

                    return bencodeWrapper(T){ .value = result };
                },
                else => return DecodeError.unexpectedType,
            }
        },
        else => return DecodeError.unexpectedField,
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

test encode {
    const allocator = std.testing.allocator;
    const num = try encode(allocator, @as(i32, 32));
    defer allocator.free(num);
    try expectEqualStrings("i32e", num);
    const str = try encode(allocator, "bob");
    defer allocator.free(str);
    try expectEqualStrings("3:bob", str);
    const numList = try encode(allocator, &[_]i32{ 1, 2, 3 });
    defer allocator.free(numList);
    try expectEqualStrings("li1ei2ei3ee", numList);
    const strList = try encode(allocator, &[_][]const u8{ "one", "two", "three" });
    defer allocator.free(strList);
    try expectEqualStrings("l3:one3:two5:threee", strList);
    const numListList = try encode(allocator, &[_][]const i32{ &.{1}, &.{2} });
    defer allocator.free(numListList);
    try expectEqualStrings("lli1eeli2eee", numListList);
    const numNums: [2][1][]const u8 = .{ [1][]const u8{"one"}, [1][]const u8{"two"} };
    const strListList = try encode(allocator, numNums);
    defer allocator.free(strListList);
    try expectEqualStrings("ll3:oneel3:twoee", strListList);
    const Person = struct { name: []const u8, age: u8 };
    const person = try encode(allocator, Person{ .name = "bob", .age = 32 });
    defer allocator.free(person);
    try expectEqualStrings("d3:agei32e4:name3:bobe", person);
    const people = try encode(allocator, &[_]Person{ .{ .name = "bob", .age = 32 }, .{ .name = "jeff", .age = 19 } });
    defer allocator.free(people);
    try expectEqualStrings("ld3:agei32e4:name3:bobed3:agei19e4:name4:jeffee", people);
    const Relationships = struct { friends: []const Person, enemies: []Person = &.{} };
    const relations = try encode(allocator, Relationships{ .friends = &[_]Person{.{ .name = "bob", .age = 32 }} });
    defer allocator.free(relations);
    try expectEqualStrings("d7:enemiesle7:friendsld3:agei32e4:name3:bobeee", relations);
}
