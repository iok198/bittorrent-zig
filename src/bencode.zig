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

test "Test decode" {
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
