const std = @import("std");
const Bencode = @import("bencode.zig");

const File = struct {
    /// A list of UTF-8 encoded strings corresponding to subdirectory names,
    /// the last of which is the actual file name (a zero length list is an
    /// error case).
    path: [][]u8,
    /// The length of the file, in bytes
    length: u32,
};

pub const BitTorrent = struct {
    const Self = @This();

    /// The URL of the tracker.
    announce: []const u8,
    info: BitInfo,
    // optional
    comment: ?[]const u8,
    @"created by": ?[]const u8,
    @"creation date": ?i32,
    encoding: ?[]const u8,
    @"announce-list": ?[][][]u8,

    pub fn from(allocator: std.mem.Allocator, bencode: []const u8) !Self {
        const torrent = try Bencode.decode(allocator, BitTorrentSerialized, bencode);
        const contents: BitInfoContents = i: {
            if (torrent.info.length) |length| {
                if (torrent.info.files) |_| return error.InvalidStructure;
                const path = p: {
                    if (torrent.info.path) |path| {
                        break :p path[0];
                    } else {
                        const wa: [][]u8 = @constCast(&[_][]u8{@constCast(torrent.info.name)});
                        break :p wa;
                    }
                };
                break :i .{ .single_file = .{ .length = length, .path = path } };
            }

            if (torrent.info.files) |files| {
                if (torrent.info.length) |_| return error.InvalidStructure;
                break :i .{ .directory = files };
            }

            return error.InvalidStructure;
        };

        const pieces = p: {
            const pieces = torrent.info.pieces;
            if (pieces.len % 20 != 0) return error.InvalidHashes;
            const buffer: [][20]u8 = @ptrCast(pieces);
            break :p buffer;
        };

        return .{ .announce = torrent.announce, .info = .{ .pieces = pieces, .contents = contents, .@"piece length" = torrent.info.@"piece length", .path = torrent.info.path }, .comment = torrent.comment, .@"created by" = torrent.@"created by", .@"creation date" = torrent.@"creation date", .encoding = torrent.encoding, .@"announce-list" = torrent.@"announce-list" };
    }
};

const BitTorrentSerialized = struct {
    /// The URL of the tracker.
    announce: []const u8,
    info: BitInfoSerialized,
    // optional
    comment: ?[]const u8,
    @"created by": ?[]const u8,
    @"creation date": ?i32,
    encoding: ?[]const u8,
    @"announce-list": ?[][][]u8,
};

const BitInfoContents = union(enum) { single_file: File, directory: []File };
const BitInfo = struct {
    contents: BitInfoContents,
    /// A string whose length is a multiple of 20. It is to be subdivided into
    /// strings of length 20, each of which is the SHA1 hash of the piece at
    /// the corresponding index.
    pieces: [][20]u8,
    /// The number of bytes in each piece the file is split into. For the
    /// purposes of transfer, files are split into fixed-size pieces which are
    /// all the same length except for possibly the last one which may be
    /// truncated
    @"piece length": u32,
    /// A list of UTF-8 encoded strings corresponding to subdirectory names,
    /// the last of which is the actual file name (a zero length list is an
    /// error case).
    path: ?[][][]u8,
};

const BitInfoSerialized = struct {
    length: ?u32,
    name: []const u8,
    @"piece length": u32,
    pieces: []u8,
    path: ?[][][]u8,
    files: ?[]File,
};

const Tracker = struct {
    /// The 20 byte sha1 hash of the bencoded form of the info value from the
    /// metainfo file. This value will almost certainly have to be escaped.
    info_hash: [20]u8,
    /// A string of length 20 which this downloader uses as its id. Each
    /// downloader generates its own id at random at the start of a new
    /// download. This value will also almost certainly have to be escaped.
    peer_id: [20]u8,
    /// An optional parameter giving the IP (or dns name) which this peer is
    /// at. Generally used for the origin if it's on the same machine as the
    /// tracker.
    ip: ?[]const u8,
    /// The port number this peer is listening on. Common behavior is for a
    /// downloader to try to listen on port 6881 and if that port is taken try
    /// 6882, then 6883, etc. and give up after 6889.
    port: u16,
    /// The total amount uploaded so far, encoded in base ten ascii
    uploaded: u32,
    /// The total amount downloaded so far, encoded in base ten ascii.
    downloaded: u32,
    /// The number of bytes this peer still has to download, encoded in base
    /// ten ascii
    left: u32,
    /// This is an optional key which maps to started, completed, or stopped
    /// (or empty, which is the same as not being present). If not present,
    /// this is one of the announcements done at regular intervals.
    event: ?[]const u8,
};

const PeerMessage = union(enum) {
    choke,
    unchoke,
    interested,
    not_interested,
    /// the index which that downloader just completed and checked the hash of.
    have: u32,
    /// a bitfield with each index that downloader has sent set to one and the
    /// rest set to zero.
    bitfield: u16,
    request: struct { index: u14, begin: u14, length: u14 },
    piece,
    cancel,
};
