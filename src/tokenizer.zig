const std = @import("std");
const ArrayList = std.ArrayList;

pub const Token = union(enum) { string: []const u8, int: i32, list_begin, dict_begin, end };

const TokenizerError = error{ invalidType, zeroPrefixed, negativeZero, missingColonAfterStringLength, unexpectedEOF, unendedInt } || std.mem.Allocator.Error;

const print = std.debug.print;
pub fn tokenize(allocator: std.mem.Allocator, comptime input: []const u8) TokenizerError!ArrayList(Token) {
    var index = @as(usize, 0);
    var tokens: ArrayList(Token) = .empty;

    while (index < input.len) : (index += 1) {
        switch (input[index]) {
            'd' => try tokens.append(allocator, .dict_begin),
            'l' => try tokens.append(allocator, .list_begin),
            'e' => try tokens.append(allocator, .end),
            'i' => {
                var buf_len = @as(usize, 0);
                var sign = @as(i32, 1);
                var num = @as(i32, 0);
                index += 1;

                while (index + buf_len < input.len and input[index + buf_len] != 'e') : (buf_len += 1) {
                    const current = input[index + buf_len];

                    if (buf_len == 0 and current == '-') {
                        sign = -1;
                        continue;
                    }

                    if (buf_len > 0 and input[index] == '0') {
                        return TokenizerError.zeroPrefixed;
                    }

                    if (current >= '0' and current <= '9') {
                        num = (num * 10) + (current - '0');
                        continue;
                    }

                    return TokenizerError.invalidType;
                }

                if (index + buf_len >= input.len) return TokenizerError.unendedInt;
                if (num == 0 and sign == -1) return TokenizerError.negativeZero;

                try tokens.append(allocator, .{ .int = num * sign });
                index += buf_len;
            },
            '0'...'9' => {
                var buf_len = @as(usize, 0);
                var str_len = input[index] - '0';
                index += 1;

                while (index + buf_len < input.len and input[index + buf_len] != ':') : (buf_len += 1) {
                    const current = input[index + buf_len];

                    if (current >= '0' and current <= '9') {
                        str_len = (str_len * 10) + (current - '0');
                        continue;
                    }

                    return TokenizerError.invalidType;
                }

                if (input[index + buf_len] != ':') return TokenizerError.missingColonAfterStringLength;
                index += buf_len + 1;

                if (index + str_len > input.len) return TokenizerError.unexpectedEOF;

                try tokens.append(allocator, .{ .string = input[index .. index + str_len] });
                index += if (str_len == 0) 0 else str_len - 1;
            },
            else => return TokenizerError.invalidType,
        }
    }

    return tokens;
}

pub fn printTokens(tokens: []const Token) void {
    for (tokens) |token| {
        switch (token) {
            .dict_begin => print("DICT_BEGIN\n", .{}),
            .list_begin => print("LIST_BEGIN\n", .{}),
            .end => print("END\n", .{}),
            .int => |num| print("INT: {d}\n", .{num}),
            .string => |str| print("STRING: {s}\n", .{str}),
        }
    }
}

fn expectTokenOutput(comptime input: []const u8, output: []const Token) !void {
    const allocator = std.testing.allocator;
    var tokens = try tokenize(allocator, input);
    defer tokens.deinit(allocator);

    for (output, tokens.items) |expected, actual| {
        if (expected == .string and actual == .string) {
            try std.testing.expectEqualStrings(expected.string, actual.string);
        } else {
            try std.testing.expectEqual(expected, actual);
        }
    }
    // try std.testing.expectEqualSlices(Token, output, tokens.items);
}

fn expectError(comptime input: []const u8, output: TokenizerError) !void {
    const allocator = std.testing.allocator;
    try std.testing.expectError(output, tokenize(allocator, input));
}

fn expectStringToken(comptime input: []const u8, token: Token) !void {
    const str = switch (token) {
        .string => |str| str,
        else => @panic("String not returned"),
    };
    try std.testing.expectEqualStrings(input, str);
}

fn getTokens(allocator: std.mem.Allocator, comptime input: []const u8) !ArrayList(Token) {
    return try tokenize(allocator, input);
}

test "Tokenizes single character tokens and empty input" {
    try expectTokenOutput("lde", &[_]Token{ .list_begin, .dict_begin, .end });
    try expectTokenOutput("", &[_]Token{});
}

test "Errors on invalid characters" {
    try expectError("y", TokenizerError.invalidType);
}

test "Tokenizes numbers" {
    try expectTokenOutput("i32e", &[_]Token{.{ .int = 32 }});
    try expectTokenOutput("i-32e", &[_]Token{.{ .int = -32 }});
    try expectTokenOutput("i32ele", &[_]Token{ .{ .int = 32 }, .list_begin, .end });
    try expectTokenOutput("i-32ele", &[_]Token{ .{ .int = -32 }, .list_begin, .end });
    try expectTokenOutput("i0e", &[_]Token{.{ .int = 0 }});
    try expectError("i03e", TokenizerError.zeroPrefixed);
    try expectError("i-0e", TokenizerError.negativeZero);
    try expectError("i320", TokenizerError.unendedInt);
}

test "Tokenizes strings" {
    try expectTokenOutput("3:owo", &[_]Token{.{ .string = "owo" }});
    try expectTokenOutput("3:owoi32e", &[_]Token{ .{ .string = "owo" }, .{ .int = 32 } });
    try expectTokenOutput("2:he3:shede", &[_]Token{ .{ .string = "he" }, .{ .string = "she" }, .dict_begin, .end });
    try expectError("5:owo", TokenizerError.unexpectedEOF);
}
