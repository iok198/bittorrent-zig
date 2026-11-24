const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

pub fn main(init: std.process.Init) !void {
    var passed: usize = 0;
    var failed: usize = 0;
    var leaked: usize = 0;
    var stdout = std.Io.File.stdout().writer(init.io, &.{});

    for (builtin.test_functions) |t| {
        testing.allocator_instance = .init(std.heap.page_allocator, .{ .check_write_after_free = true });
        testing.io_instance = .init(testing.allocator, .{ .argv0 = .init(init.minimal.args), .environ = init.minimal.environ });
        defer testing.io_instance.deinit();

        t.func() catch |err| {
            try stdout.interface.print("{s} fail: {}\n", .{ t.name, err });
            failed += 1;
            continue;
        };

        if (testing.allocator_instance.deinit() != 0) {
            try stdout.interface.print("{s} leaked memory\n", .{t.name});
            leaked += 1;
        }

        try stdout.interface.print("{s} passed\n", .{t.name});
        passed += 1;
    }

    try stdout.interface.print("\nPASSED: {d}, FAILED: {d}, LEAKED: {d}\n", .{ passed, failed, leaked });
}
