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

pub fn handshake(reader: *Io.Reader, writer: *Io.Writer, hash: [20]u8) !struct { hash: [20]u8, peer_id: [20]u8, bitfield: ?[]u8 } {
    try writer.print("{u}BitTorrent protocol{s}{s}{s}", .{ 19, @as([8]u8, @splat(0)), hash, "01234567890123456789" });
    try writer.flush();
    const bytes = try reader.take(68);

    if (bytes[0] != 19) return error.BadResponse;
    if (!std.mem.eql(u8, "BitTorrent protocol", bytes[1..][0..19])) return error.BadResponse;
    if (!std.mem.eql(u8, &hash, bytes[28..][0..20])) return error.BadResponse;

    const msg = m: {
        const len = reader.takeInt(u32, .big) catch break :m null;
        const tag = reader.takeEnum(MessageTag, .big) catch break :m null;
        const rest = reader.take(len - 1) catch break :m null;

        switch (tag) {
            .bitfield => break :m rest,
            else => break :m null,
        }
    };

    return .{ .hash = bytes[28..][0..20].*, .peer_id = bytes[48..][0..20].*, .bitfield = msg };
}

pub fn receiveMessage(reader: *Io.Reader, comptime tag: MessageTag) !@FieldType(Message, @tagName(tag)) {
    const len = try reader.takeInt(u32, .big);
    const received_tag = try reader.takeEnum(MessageTag, .big);
    if (received_tag != tag) {
        std.debug.print("Unexpected tag: {t}\n", .{received_tag});
        return error.UnexpectedMessage;
    }
    const rest = try reader.take(len - 1);

    const result: Message = r: switch (received_tag) {
        .bitfield => break :r .{ .bitfield = rest },
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
    try writer.writeInt(u32, 0, .big);
    try writer.writeByte(@backingInt(msg));
    try writer.flush();
}
