const std = @import("std");
const ArrayList = std.ArrayList;

pub const Token = union(enum) { string: []const u8, int: i32, list_begin, dict_begin, end, eof };

const TokenizerError = error{ invalidType, zeroPrefixed, negativeZero, missingColonAfterStringLength, unexpectedEOF, unendedInt } || std.mem.Allocator.Error;

const print = std.debug.print;
const Tokenizer = struct {
    const Self = @This();
    input: []const u8,
    index: usize,

    fn init(input: []const u8) Self {
        return .{ .input = input, .index = 0 };
    }

    fn next(self: *Self) TokenizerError!Token {
        while (self.index < self.input.len) {
            defer self.index += 1;
            switch (self.input[self.index]) {
                'd' => return .dict_begin,
                'l' => return .list_begin,
                'e' => return .end,
                'i' => {
                    var buf_len = @as(usize, 0);
                    var sign = @as(i32, 1);
                    var num = @as(i32, 0);
                    self.index += 1;

                    while (self.index + buf_len < self.input.len and self.input[self.index + buf_len] != 'e') : (buf_len += 1) {
                        const current = self.input[self.index + buf_len];

                        if (buf_len == 0 and current == '-') {
                            sign = -1;
                            continue;
                        }

                        if (buf_len > 0 and self.input[self.index] == '0') {
                            return TokenizerError.zeroPrefixed;
                        }

                        if (current >= '0' and current <= '9') {
                            num = (num * 10) + (current - '0');
                            continue;
                        }

                        return TokenizerError.invalidType;
                    }

                    if (self.index + buf_len >= self.input.len) return TokenizerError.unendedInt;
                    if (num == 0 and sign == -1) return TokenizerError.negativeZero;

                    self.index += buf_len;
                    return .{ .int = num * sign };
                },
                '0'...'9' => {
                    var buf_len = @as(usize, 0);
                    var str_len = self.input[self.index] - '0';
                    self.index += 1;

                    while (self.index + buf_len < self.input.len and self.input[self.index + buf_len] != ':') : (buf_len += 1) {
                        const current = self.input[self.index + buf_len];

                        if (current >= '0' and current <= '9') {
                            str_len = (str_len * 10) + (current - '0');
                            continue;
                        }

                        return TokenizerError.invalidType;
                    }

                    if (self.input[self.index + buf_len] != ':') return TokenizerError.missingColonAfterStringLength;
                    self.index += buf_len + 1;

                    if (self.index + str_len > self.input.len) return TokenizerError.unexpectedEOF;

                    defer self.index += if (str_len == 0) 0 else str_len - 1;
                    return .{ .string = self.input[self.index..][0..str_len] };
                },
                else => return TokenizerError.invalidType,
            }
        }

        return .eof;
    }
};

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
    var tokenizer: Tokenizer = .init(input);
    var index = @as(usize, 0);
    while (index < output.len) : (index += 1) {
        const expected = output[index];
        const actual = try tokenizer.next();
        if (expected == .string and actual == .string) {
            try std.testing.expectEqualStrings(expected.string, actual.string);
        } else {
            try std.testing.expectEqual(expected, actual);
        }
    }
}

fn expectError(comptime input: []const u8, output: TokenizerError) !void {
    var tokenizer: Tokenizer = .init(input);
    try std.testing.expectError(output, tokenizer.next());
}

fn expectStringToken(comptime input: []const u8, token: Token) !void {
    const str = switch (token) {
        .string => |str| str,
        else => @panic("String not returned"),
    };
    try std.testing.expectEqualStrings(input, str);
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
