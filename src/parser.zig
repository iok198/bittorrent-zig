const std = @import("std");

const DictEntry = struct { key: []u8, val: *Expr };
const Expr = union(enum) { string: []const u8, int: i32, dict: []DictEntry, list: []*Expr };
const Tokenizer = @import("tokenizer.zig");

const ParseError = error{ NullRootValue, MultipleRootValues, InvalidToken } || std.mem.Allocator.Error;

pub fn parse(comptime input: []const u8, tokens: []Tokenizer.Token) ParseError!Expr {
    if (tokens.len == 0) return ParseError.NullRootValue;

    switch (tokens[0]) {
        .int => |num| {
            if (tokens.len == 1) {
                return .{ .int = num };
            } else {
                return ParseError.MultipleRootValues;
            }
        },
        .string => |str| {
            if (tokens.len == 1) {
                return .{ .string = input[str.pos .. str.pos + str.len] };
            } else {
                return ParseError.MultipleRootValues;
            }
        },
        else => return ParseError.InvalidToken,
    }
}

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

test "Parses root integers and strings" {
    const allocator = std.testing.allocator;
    const numInput = "i32e";
    var numTokens = try Tokenizer.tokenize(allocator, numInput);
    defer numTokens.deinit(allocator);
    const numExpr = try parse(numInput, numTokens.items);

    switch (numExpr) {
        .int => |num| try expectEqual(32, num),
        else => @panic("Int not returned"),
    }

    const strInput = "5:hello";
    var strTokens = try Tokenizer.tokenize(allocator, strInput);
    defer strTokens.deinit(allocator);
    const strExpr = try parse(strInput, strTokens.items);

    switch (strExpr) {
        .string => |str| try expectEqualStrings("hello", str),
        else => @panic("String not returned"),
    }

    const multipleNums = "i32ei32e";
    var multipleNumsTokens = try Tokenizer.tokenize(allocator, multipleNums);
    defer multipleNumsTokens.deinit(allocator);
    try expectError(ParseError.MultipleRootValues, parse(multipleNums, multipleNumsTokens.items));

    var noTokens = try Tokenizer.tokenize(allocator, "");
    defer noTokens.deinit(allocator);
    try expectError(ParseError.NullRootValue, parse("", noTokens.items));
}
