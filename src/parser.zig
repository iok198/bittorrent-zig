const std = @import("std");
const ArrayList = std.ArrayList;
const Map = std.StringHashMap(Expr);
const Tokenizer = @import("tokenizer.zig");
const Token = Tokenizer.Token;

// const DictEntry = struct { key: []const u8, val: Expr };
pub const Expr = union(enum) {
    const Self = @This();

    string: []const u8,
    int: i32,
    dict: Map,
    list: []Expr,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .list => |list| {
                for (list) |*item| item.deinit(allocator);
                allocator.free(list);
            },
            .dict => |*dict| {
                var iter = dict.valueIterator();
                while (iter.next()) |val| val.deinit(allocator);
                dict.deinit();
            },
            else => {},
        }
    }
};
const ParseError = error{ NullRootValue, MultipleRootValues, InvalidToken, UnendedList, UnendedDict } || Tokenizer.TokenizerError || std.mem.Allocator.Error;

fn parseList(allocator: std.mem.Allocator, tokenizer: *Tokenizer) ParseError!Expr {
    var list: ArrayList(Expr) = .empty;
    errdefer {
        for (list.items) |*item| item.deinit(allocator);
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
                    var temp = sublist;
                    temp.deinit(allocator);
                    return err;
                };
            },
            .dict_begin => {
                const dict = try parseDict(allocator, tokenizer);
                list.append(allocator, dict) catch |err| {
                    var temp = dict;
                    temp.deinit(allocator);
                    return err;
                };
            },
            .eof => return ParseError.UnendedList,
        }
    } else |err| return err;

    return .{ .list = try list.toOwnedSlice(allocator) };
}

fn parseDict(allocator: std.mem.Allocator, tokenizer: *Tokenizer) ParseError!Expr {
    var entries = Map.init(allocator);
    errdefer {
        var iter = entries.valueIterator();
        while (iter.next()) |entry| entry.deinit(allocator);
        entries.deinit();
    }

    while (tokenizer.next()) |token| {
        switch (token) {
            .end => break,
            .eof => return ParseError.UnendedDict,
            .string => |key| {
                const val = try parseExpr(allocator, tokenizer);
                entries.put(key, val) catch |err| {
                    var temp = val;
                    temp.deinit(allocator);
                    return err;
                };
            },
            else => return ParseError.InvalidToken,
        }
    } else |err| return err;

    return .{ .dict = entries };
}

fn parseExpr(allocator: std.mem.Allocator, tokenizer: *Tokenizer) ParseError!Expr {
    const first = tokenizer.next() catch return ParseError.NullRootValue;

    switch (first) {
        .int => |num| return .{ .int = num },
        .string => |str| return .{ .string = str },
        .list_begin => return try parseList(allocator, tokenizer),
        .dict_begin => return try parseDict(allocator, tokenizer),
        .eof => return ParseError.NullRootValue,
        .end => return ParseError.InvalidToken,
    }
}

pub fn parse(allocator: std.mem.Allocator, tokenizer: *Tokenizer) ParseError!Expr {
    const expr = try parseExpr(allocator, tokenizer);
    const eos = try tokenizer.next();
    if (eos != .eof) return ParseError.MultipleRootValues;
    return expr;
}

const decodeError = error{ unexpectedType, missingField } || std.mem.Allocator.Error;
fn bencodeWrapper(comptime T: type) type {
    return struct { value: T };
}

pub fn toStruct(allocator: std.mem.Allocator, T: type, expr: *Expr) decodeError!bencodeWrapper(T) {
    switch (expr.*) {
        .int => |num| {
            if (@typeInfo(T) == .int) {
                return bencodeWrapper(T){ .value = @intCast(num) };
            } else return error.unexpectedType;
        },
        .string => |str| {
            switch (@typeInfo(T)) {
                .pointer => |ptr| {
                    if (ptr.child == u8 and ptr.size == .slice) {
                        return bencodeWrapper(T){ .value = @constCast(str) };
                    } else return error.unexpectedType;
                },
                else => return error.unexpectedType,
            }
        },
        .list => |list| {
            if (list.len == 0) return bencodeWrapper(T){ .value = undefined };

            switch (@typeInfo(T)) {
                .pointer => |ptr| {
                    if (ptr.size != .slice) return error.unsupportedType;

                    var items = try allocator.alloc(ptr.child, list.len);
                    for (list, 0..) |*item, i| {
                        const val = try toStruct(allocator, ptr.child, item);
                        items[i] = val.value;
                    }
                    return bencodeWrapper(T){ .value = items };
                },
                else => return error.unexpectedType,
            }
        },
        .dict => |dict| {
            switch (@typeInfo(T)) {
                .@"struct" => |s| {
                    var result: T = undefined;

                    inline for (s.field_types, s.field_names) |field_type, field_name| {
                        var entry = dict.get(field_name) orelse return error.missingField;
                        const value = try toStruct(allocator, field_type, &entry);
                        @field(result, field_name) = value.value;
                    }

                    return bencodeWrapper(T){ .value = result };
                },
                else => return error.unexpectedType,
            }
        },
    }
}

pub fn toString(allocator: std.mem.Allocator, input: Expr) ![]u8 {
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
            var i = @as(usize, 0);
            var iter = dict.iterator();
            while (iter.next()) |entry| : (i += 1) {
                if (i == 0) {
                    try result.print(allocator, "\"{s}\": {s}", .{ entry.key_ptr.*, try toString(allocator, entry.value_ptr.*) });
                } else {
                    try result.print(allocator, ", \"{s}\": {s}", .{ entry.key_ptr.*, try toString(allocator, entry.value_ptr.*) });
                }
            }
            try result.print(allocator, " }}", .{});
        },
    }

    return result.toOwnedSlice(allocator);
}

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;
fn expectEqualExprs(left: Expr, right: Expr) !void {
    switch (left) {
        .int => |left_num| {
            switch (right) {
                .int => |right_num| try expectEqual(left_num, right_num),
                else => @panic("not same type"),
            }
        },
        .string => |left_str| {
            switch (right) {
                .string => |right_str| try expectEqualStrings(left_str, right_str),
                else => @panic("not same type"),
            }
        },
        .list => |left_list| {
            switch (right) {
                .list => |right_list| {
                    try expectEqual(left_list.len, right_list.len);
                    for (left_list, right_list) |left_item, right_item| {
                        try expectEqualExprs(left_item, right_item);
                    }
                },
                else => @panic("not same type"),
            }
        },
        .dict => |left_dict| {
            switch (right) {
                .dict => |right_dict| {
                    try expectEqual(left_dict.count(), right_dict.count());
                    var left_iter = left_dict.iterator();
                    var right_iter = right_dict.iterator();
                    while (left_iter.next()) |left_entry| {
                        const right_entry = right_iter.next().?;
                        try expectEqualStrings(left_entry.key_ptr.*, right_entry.key_ptr.*);
                        try expectEqualExprs(left_entry.value_ptr.*, right_entry.value_ptr.*);
                    }
                },
                else => @panic("not same type"),
            }
        },
    }
}

test "Parses root integers and strings" {
    const allocator = std.testing.allocator;
    var numInput = Tokenizer.init("i32e");
    const numExpr = try parse(allocator, &numInput);
    try expectEqualExprs(Expr{ .int = 32 }, numExpr);

    var strInput = Tokenizer.init("5:hello");
    const strExpr = try parse(allocator, &strInput);
    try expectEqualExprs(Expr{ .string = "hello" }, strExpr);

    var multipleNums = Tokenizer.init("i32ei32e");
    try expectError(ParseError.MultipleRootValues, parse(allocator, &multipleNums));

    var noTokens = Tokenizer.init("");
    try expectError(ParseError.NullRootValue, parse(allocator, &noTokens));
}

test "Parses lists" {
    const allocator = std.testing.allocator;
    var tokens = Tokenizer.init("li32e3:owoe");
    var expr = try parse(allocator, &tokens);
    defer expr.deinit(allocator);
    var temp = [_]Expr{ .{ .int = 32 }, .{ .string = "owo" } };
    try expectEqualExprs(expr, Expr{ .list = &temp });
    var embeddedListTokens = Tokenizer.init("lli32e2:hili27eeee");
    var embeddedListExpr = try parse(allocator, &embeddedListTokens);
    defer embeddedListExpr.deinit(allocator);
    var level3 = [_]Expr{.{ .int = 27 }};
    var level2 = [_]Expr{ .{ .int = 32 }, .{ .string = "hi" }, .{ .list = &level3 } };
    var level1 = [_]Expr{.{ .list = &level2 }};
    try expectEqualExprs(Expr{ .list = &level1 }, embeddedListExpr);
    var noEnd = Tokenizer.init("li32e2:hi");
    try expectError(ParseError.UnendedList, parse(allocator, &noEnd));
    var noEndEmbedded = Tokenizer.init("li32e2:hili21ee");
    try expectError(ParseError.UnendedList, parse(allocator, &noEndEmbedded));
}

fn hashMapWith(allocator: std.mem.Allocator, entries: anytype) !Map {
    var result = Map.init(allocator);
    inline for (entries) |entry| {
        const key, const value = entry;
        try result.put(key, value);
    }
    return result;
}

test "Parse dict" {
    const allocator = std.testing.allocator;
    var tokens = Tokenizer.init("d3:vali32ee");
    var expr = try parse(allocator, &tokens);
    defer expr.deinit(allocator);
    var entries = try hashMapWith(allocator, .{.{ "val", Expr{ .int = 32 } }});
    defer entries.deinit();
    try expectEqualExprs(Expr{ .dict = entries }, expr);
    var embeddedDict = Tokenizer.init("d4:dictd3:vali32eee");
    var embeddedEntries = try hashMapWith(allocator, .{.{ "dict", Expr{ .dict = entries } }});
    defer embeddedEntries.deinit();
    var embeddedExpr = try parse(allocator, &embeddedDict);
    defer embeddedExpr.deinit(allocator);
    try expectEqualExprs(Expr{ .dict = embeddedEntries }, embeddedExpr);
    var noEnd = Tokenizer.init("d4:word4:tell");
    try expectError(ParseError.UnendedDict, parse(allocator, &noEnd));
    var noEndEmbedded = Tokenizer.init("d4:dictd4:name3:bobe");
    try expectError(ParseError.UnendedDict, parse(allocator, &noEndEmbedded));
}

test "Embedded complex expressions" {
    const allocator = std.testing.allocator;
    var list = [_]Expr{ .{ .int = 32 }, .{ .string = "owo" } };
    var dictListExpr = try hashMapWith(allocator, .{.{ "list", Expr{ .list = &list } }});
    defer dictListExpr.deinit();
    var dictList = Tokenizer.init("d4:listli32e3:owoee");
    var expr = try parse(allocator, &dictList);
    defer expr.deinit(allocator);
    try expectEqualExprs(Expr{ .dict = dictListExpr }, expr);
    var listDictExpr = [_]Expr{.{ .dict = dictListExpr }};
    var listDict = Tokenizer.init("ld4:listli32e3:owoeee");
    var expr2 = try parse(allocator, &listDict);
    defer expr2.deinit(allocator);
    try expectEqualExprs(Expr{ .list = &listDictExpr }, expr2);
}
