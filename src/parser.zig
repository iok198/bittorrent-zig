const std = @import("std");
const ArrayList = std.ArrayList;

const DictEntry = struct { key: []const u8, val: *Expr };
const Expr = union(enum) {
    const Self = @This();

    string: []const u8,
    int: i32,
    dict: []DictEntry,
    list: []Expr,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .list => |list| {
                for (list) |*item| item.deinit(allocator);
                allocator.free(list);
            },
            .dict => |dict| allocator.free(dict),
            else => {},
        }
    }
};
const Tokenizer = @import("tokenizer.zig");
const Token = Tokenizer.Token;
const tokenize = Tokenizer.tokenize;

const ParseError = error{ NullRootValue, MultipleRootValues, InvalidToken, UnendedList } || std.mem.Allocator.Error;

fn parseList(allocator: std.mem.Allocator, tokens: []const Token) ParseError!struct { Expr, usize } {
    var list: ArrayList(Expr) = .empty;
    var ended = false;
    errdefer {
        for (list.items) |*item| {
            item.deinit(allocator);
        }
        list.deinit(allocator);
    }

    var i = @as(usize, 0);
    while (i < tokens.len) : (i += 1) {
        const token = tokens[i];
        switch (token) {
            .end => {
                ended = true;
                break;
            },
            .int => |num| try list.append(allocator, .{ .int = num }),
            .string => |str| try list.append(allocator, .{ .string = str }),
            .list_begin => {
                const sublist, const skip = try parseList(allocator, tokens[1 + i ..]);
                try list.append(allocator, sublist);
                i += skip;
            },
            else => @panic("todo"),
        }
    }

    if (!ended) return ParseError.UnendedList;

    return .{ Expr{ .list = try list.toOwnedSlice(allocator) }, i };
}

pub fn parse(allocator: std.mem.Allocator, tokens: []const Token) ParseError!Expr {
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
                return .{ .string = str };
            } else {
                return ParseError.MultipleRootValues;
            }
        },
        .list_begin => {
            const list, _ = try parseList(allocator, tokens[1..]);
            return list;
        },
        else => return ParseError.InvalidToken,
    }
}

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;

test "Parses root integers and strings" {
    const allocator = std.testing.allocator;
    const numInput = "i32e";
    const numTokens = try tokenize(allocator, numInput);
    defer allocator.free(numTokens);
    const numExpr = try parse(allocator, numTokens);

    switch (numExpr) {
        .int => |num| try expectEqual(32, num),
        else => @panic("Int not returned"),
    }

    const strInput = "5:hello";
    const strTokens = try tokenize(allocator, strInput);
    defer allocator.free(strTokens);
    const strExpr = try parse(allocator, strTokens);

    switch (strExpr) {
        .string => |str| try expectEqualStrings("hello", str),
        else => @panic("String not returned"),
    }

    const multipleNums = "i32ei32e";
    const multipleNumsTokens = try tokenize(allocator, multipleNums);
    defer allocator.free(multipleNumsTokens);
    try expectError(ParseError.MultipleRootValues, parse(allocator, multipleNumsTokens));

    const noTokens = try tokenize(allocator, "");
    defer allocator.free(noTokens);
    try expectError(ParseError.NullRootValue, parse(allocator, noTokens));
}

fn expectEqualExprs(left: *const Expr, right: *const Expr) !void {
    switch (left.*) {
        .int => |left_num| {
            switch (right.*) {
                .int => |right_num| try expectEqual(left_num, right_num),
                else => @panic("not same type"),
            }
        },
        .string => |left_str| {
            switch (right.*) {
                .string => |right_str| try expectEqualStrings(left_str, right_str),
                else => @panic("not same type"),
            }
        },
        .list => |left_list| {
            switch (right.*) {
                .list => |right_list| {
                    try expectEqual(left_list.len, right_list.len);
                    for (left_list, right_list) |*left_item, *right_item| {
                        try expectEqualExprs(left_item, right_item);
                    }
                },
                else => @panic("not same type"),
            }
        },
        .dict => |left_dict| {
            switch (right.*) {
                .dict => |right_dict| {
                    try expectEqual(left_dict.len, right_dict.len);
                    for (left_dict, right_dict) |*left_entry, *right_entry| {
                        try expectEqualStrings(left_entry.key, right_entry.key);
                        try expectEqualExprs(left_entry.val, right_entry.val);
                    }
                },
                else => @panic("not same type"),
            }
        },
    }
}

test "Parses lists" {
    const allocator = std.testing.allocator;
    const tokens = try tokenize(allocator, "li32e3:owoe");
    defer allocator.free(tokens);
    var expr = try parse(allocator, tokens);
    defer expr.deinit(allocator);
    var temp = [_]Expr{ .{ .int = 32 }, .{ .string = "owo" } };
    try expectEqualExprs(&expr, &Expr{ .list = &temp });
    const embeddedListTokens = try tokenize(allocator, "lli32e2:hili27eee");
    defer allocator.free(embeddedListTokens);
    var embeddedListExpr = try parse(allocator, embeddedListTokens);
    defer embeddedListExpr.deinit(allocator);
    var level3 = [_]Expr{.{ .int = 27 }};
    var level2 = [_]Expr{ .{ .int = 32 }, .{ .string = "hi" }, .{ .list = &level3 } };
    var level1 = [_]Expr{.{ .list = &level2 }};
    try expectEqualExprs(&Expr{ .list = &level1 }, &embeddedListExpr);
}
