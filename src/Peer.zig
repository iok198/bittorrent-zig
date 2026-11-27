const std = @import("std");
const Io = std.Io;
const Self = @This();

stream: Io.net.Stream,
r_buffer: [1024]u8 = undefined,
w_buffer: [1024]u8 = undefined,

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

pub fn close(self: *Self, io: Io) void {
    self.stream.close(io);
}

pub fn getPiece(self: *Self, io: Io, info_hash: [20]u8) Io.Cancelable!void {
    const Canceled = Io.Cancelable.Canceled;
    const hs = self.handshake(io, info_hash) catch |err| {
        std.debug.print("handshake failed: {any}\n", .{err});
        return Canceled;
    };
    std.debug.print("Peer ID: {x}\n", .{hs.peer_id});
    const bf = if (hs.msg) |msg| b: {
        break :b msg;
    } else b: {
        break :b self.receiveMessage(io, .bitfield) catch |err| {
            std.debug.print("Received error receiving bitfield: {t}\n", .{err});
            return Canceled;
        };
    };
    std.debug.print("Bitfield: {any}\n", .{bf});

    self.sendMessage(io, .interested) catch |err| {
        std.debug.print("Error sending interested: {any}\n", .{err});
        return Canceled;
    };
    std.debug.print("Sent interested\n", .{});

    _ = self.receiveMessage(io, MessageTag.unchoke) catch |err| {
        std.debug.print("Error receiving interested: {}\n", .{err});
        return Canceled;
    };
    std.debug.print("Received unchoke\n", .{});
}

pub fn handshake(self: *Self, io: Io, hash: [20]u8) !struct { hash: [20]u8, peer_id: [20]u8, msg: ?[]u8 } {
    var reader = self.stream.reader(io, self.r_buffer[0..]);
    var writer = self.stream.writer(io, self.w_buffer[0..]);

    try writer.interface.print("{u}BitTorrent protocol{s}{s}{s}", .{ 19, @as([8]u8, @splat(0)), hash, "01234567890123456789" });
    try writer.interface.flush();
    const bytes = try reader.interface.take(68);

    if (bytes[0] != 19) return error.BadResponse;
    if (!std.mem.eql(u8, "BitTorrent protocol", bytes[1..][0..19])) return error.BadResponse;
    if (!std.mem.eql(u8, &hash, bytes[28..][0..20])) return error.BadResponse;

    const msg = bitfield(&reader.interface);

    return .{ .hash = bytes[28..][0..20].*, .peer_id = bytes[48..][0..20].*, .msg = msg };
}

fn bitfield(reader: *Io.Reader) ?[]u8 {
    const len = reader.takeInt(u32, .big) catch return null;
    const tag = reader.takeEnum(MessageTag, .big) catch return null;
    const rest = reader.take(len - 1) catch return null;

    switch (tag) {
        .bitfield => return rest,
        else => return null,
    }
}

pub fn receiveMessage(self: *Self, io: Io, comptime tag: MessageTag) !@FieldType(Message, @tagName(tag)) {
    const time: Io.Timeout = .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } };
    const resp = try self.stream.socket.receiveTimeout(io, self.r_buffer[0..], time);
    var reader = Io.Reader.fixed(resp.data[0..]);
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

pub fn sendMessage(self: *Self, io: Io, msg: Message) !void {
    var writer = self.stream.writer(io, self.w_buffer[0..]);
    try writer.interface.writeInt(u32, 0, .big);
    try writer.interface.writeByte(@backingInt(msg));
    try writer.interface.flush();
}
