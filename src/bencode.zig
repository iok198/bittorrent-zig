const std = @import("std");

const Parser = @import("parser.zig");
const Tokenizer = @import("Tokenizer.zig");

pub const DecodeError = Parser.ParseError || decodeError;

pub fn decode(allocator: std.mem.Allocator, T: type, input: []const u8) DecodeError!T {
    var tokenizer = Tokenizer.init(input);
    var expr = try Parser.parse(allocator, &tokenizer);
    defer expr.deinit(allocator);
    const result = try toStruct(allocator, T, &expr);
    return result.value;
}

const decodeError = error{ unexpectedType, missingField } || std.mem.Allocator.Error;
fn bencodeWrapper(comptime T: type) type {
    return struct { value: T };
}

fn toStruct(allocator: std.mem.Allocator, T: type, expr: *Parser.Expr) decodeError!bencodeWrapper(T) {
    switch (expr.*) {
        .int => |num| {
            if (@typeInfo(T) == .int) {
                return bencodeWrapper(T){ .value = @intCast(num) };
            } else {
                if (@typeInfo(T) == .optional) {
                    return bencodeWrapper(T){ .value = null };
                } else return error.unexpectedType;
            }
        },
        .string => |str| {
            switch (@typeInfo(T)) {
                .pointer => |ptr| {
                    if (ptr.child == u8 and ptr.size == .slice) {
                        return bencodeWrapper(T){ .value = @constCast(str) };
                    } else {
                        if (@typeInfo(T) == .optional) {
                            return bencodeWrapper(T){ .value = null };
                        } else return error.unexpectedType;
                    }
                },
                else => return error.unexpectedType,
            }
        },
        .list => |list| {
            if (list.len == 0) return bencodeWrapper(T){ .value = undefined };

            switch (@typeInfo(T)) {
                .pointer => |ptr| {
                    if (ptr.size != .slice) return error.unexpectedType;

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
                .optional => return bencodeWrapper(T){ .value = null },
                else => return error.unexpectedType,
            }
        },
        .dict => |dict| {
            switch (@typeInfo(T)) {
                .@"struct" => |s| {
                    var result: T = undefined;

                    inline for (s.field_types, s.field_names) |field_type, field_name| {
                        if (dict.get(field_name)) |entry| {
                            const value = try toStruct(allocator, field_type, @constCast(&entry));
                            @field(result, field_name) = value.value;
                        } else {
                            if (@typeInfo(field_type) == .optional) {
                                @field(result, field_name) = null;
                            } else {
                                return error.missingField;
                            }
                        }
                    }

                    return bencodeWrapper(T){ .value = result };
                },
                else => return error.unexpectedType,
            }
        },
    }
}

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

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
}
