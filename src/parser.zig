const std = @import("std");
const ArrayList = std.ArrayList;
const Tokenizer = @import("tokenizer.zig");
const Token = Tokenizer.Token;

const DictEntry = struct { key: []const u8, val: Expr };
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
            .dict => |dict| {
                for (dict) |*entry| entry.val.deinit(allocator);
                allocator.free(dict);
            },
            else => {},
        }
    }
};
const ParseError = error{ NullRootValue, MultipleRootValues, InvalidToken, UnendedList } || Tokenizer.TokenizerError || std.mem.Allocator.Error;

fn parseList(allocator: std.mem.Allocator, tokenizer: *Tokenizer) ParseError!Expr {
    var list: ArrayList(Expr) = .empty;
    errdefer {
        for (list.items) |*item| {
            item.deinit(allocator);
        }
        list.deinit(allocator);
    }

    while (tokenizer.next()) |token| {
        switch (token) {
            .end => break,
            .int => |num| try list.append(allocator, .{ .int = num }),
            .string => |str| try list.append(allocator, .{ .string = str }),
            .list_begin => {
                const sublist = try parseList(allocator, tokenizer);
                list.append(allocator, sublist) catch |err| {
                    var _sublist = sublist;
                    _sublist.deinit(allocator);
                    return err;
                };
            },
            .eof => return ParseError.UnendedList,
            else => {
                std.debug.print("Unexpected token: {any}\n", .{token});
                return ParseError.InvalidToken;
            },
        }
    } else |err| return err;

    return .{ .list = try list.toOwnedSlice(allocator) };
}

pub fn parse(allocator: std.mem.Allocator, tokenizer: *Tokenizer) ParseError!Expr {
    const first = tokenizer.next() catch return ParseError.NullRootValue;

    switch (first) {
        .int => |num| {
            if (try tokenizer.next() != .eof) return ParseError.MultipleRootValues;
            return .{ .int = num };
        },
        .string => |str| {
            if (try tokenizer.next() != .eof) return ParseError.MultipleRootValues;
            return .{ .string = str };
        },
        .list_begin => {
            const list = try parseList(allocator, tokenizer);
            if (try tokenizer.next() != .eof) return ParseError.MultipleRootValues;
            return list;
        },
        .eof => return ParseError.NullRootValue,
        else => return ParseError.InvalidToken,
    }
}

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;

test "Parses root integers and strings" {
    const allocator = std.testing.allocator;
    var numInput = Tokenizer.init("i32e");
    const numExpr = try parse(allocator, &numInput);

    switch (numExpr) {
        .int => |num| try expectEqual(32, num),
        else => @panic("Int not returned"),
    }

    var strInput = Tokenizer.init("5:hello");
    const strExpr = try parse(allocator, &strInput);

    switch (strExpr) {
        .string => |str| try expectEqualStrings("hello", str),
        else => @panic("String not returned"),
    }

    var multipleNums = Tokenizer.init("i32ei32e");
    try expectError(ParseError.MultipleRootValues, parse(allocator, &multipleNums));

    var noTokens = Tokenizer.init("");
    try expectError(ParseError.NullRootValue, parse(allocator, &noTokens));
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
                    for (left_dict, right_dict) |left_entry, right_entry| {
                        try expectEqualStrings(left_entry.key, right_entry.key);
                        try expectEqualExprs(&left_entry.val, &right_entry.val);
                    }
                },
                else => @panic("not same type"),
            }
        },
    }
}

test "Parses lists" {
    const allocator = std.testing.allocator;
    var tokens = Tokenizer.init("li32e3:owoe");
    var expr = try parse(allocator, &tokens);
    defer expr.deinit(allocator);
    var temp = [_]Expr{ .{ .int = 32 }, .{ .string = "owo" } };
    try expectEqualExprs(&expr, &Expr{ .list = &temp });
    var embeddedListTokens = Tokenizer.init("lli32e2:hili27eeee");
    var embeddedListExpr = try parse(allocator, &embeddedListTokens);
    defer embeddedListExpr.deinit(allocator);
    var level3 = [_]Expr{.{ .int = 27 }};
    var level2 = [_]Expr{ .{ .int = 32 }, .{ .string = "hi" }, .{ .list = &level3 } };
    var level1 = [_]Expr{.{ .list = &level2 }};
    try expectEqualExprs(&Expr{ .list = &level1 }, &embeddedListExpr);
    var noEnd = Tokenizer.init("li32e2:hi");
    try expectError(ParseError.UnendedList, parse(allocator, &noEnd));
    var noEndEmbedded = Tokenizer.init("li32e2:hili21ee");
    try expectError(ParseError.UnendedList, parse(allocator, &noEndEmbedded));
}

test "Expr allocation" {
    const allocator = std.testing.allocator;
    const num = try allocator.create(Expr);
    defer allocator.destroy(num);
    num.* = .{ .int = 32 };
    const str = try allocator.create(Expr);
    defer allocator.destroy(str);
    str.* = .{ .int = 32 };
    const list = try allocator.create(Expr);
    defer allocator.destroy(list);
    var vals = [_]Expr{ .{ .int = 32 }, .{ .string = "hello" } };
    list.* = .{ .list = &vals };
    const embeddedList = try allocator.create(Expr);
    defer allocator.destroy(embeddedList);
    var embeddedVal = [_]Expr{.{ .list = &vals }};
    embeddedList.* = .{ .list = &embeddedVal };
}
