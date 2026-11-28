const std = @import("std");
const Io = std.Io;
const Self = @This();

pub const MessageTag = enum(u8) {
    choke,
    unchoke,
    interested,
    not_interested,
    have,
    bitfield,
    request,
    piece,
    cancel,
};

pub const Message = union(MessageTag) {
    choke,
    unchoke,
    interested,
    not_interested,
    have,
    bitfield: []u8,
    request,
    piece,
    cancel,
};

pub fn sendHandshake(writer: *Io.Writer, hash: [20]u8) !void {
    try writer.writeByte(19);
    try writer.print("BitTorrent protocol", .{});
    try writer.splatByteAll(0, 8);
    try writer.writeAll(&hash);
    try writer.print("01234567890123456789", .{});
    try writer.flush();
}

pub fn receiveHandshake(reader: *Io.Reader, info_hash: [20]u8) ![20]u8 {
    if (try reader.takeByte() != 19) return error.BadResponse;
    if (!std.mem.eql(u8, "BitTorrent protocol", try reader.take(19))) return error.BadResponse;
    _ = try reader.take(8);
    if (!std.mem.eql(u8, &info_hash, try reader.take(20))) return error.BadResponse;

    const peer_id = try reader.takeArray(20);
    return peer_id.*;
}

pub fn receiveMessage(reader: *Io.Reader, comptime tag: MessageTag) !@FieldType(Message, @tagName(tag)) {
    const len = try reader.takeInt(u32, .big) - 1;
    const received_tag = try reader.takeEnum(MessageTag, .big);
    if (received_tag != tag) {
        std.debug.print("Unexpected tag: {t}\n", .{received_tag});
        return error.UnexpectedMessage;
    }

    const result: Message = r: switch (received_tag) {
        .bitfield => break :r .{ .bitfield = try reader.take(len) },
        .unchoke => break :r .unchoke,
        .choke => break :r .choke,
        .interested => break :r .interested,
        .not_interested => break :r .not_interested,
        .have => break :r .have,
        .request => break :r .request,
        .piece => break :r .piece,
        .cancel => break :r .cancel,
    };

    return @field(result, @tagName(tag));
}

pub fn sendMessage(writer: *Io.Writer, msg: Message) !void {
    switch (msg) {
        .interested => {
            try writer.writeInt(u32, 1, .big);
            try writer.splatByteAll(@backingInt(msg), 2);
        },
        else => {
            try writer.writeInt(u32, 0, .big);
            try writer.writeByte(@backingInt(msg));
        },
    }
    try writer.flush();
}
