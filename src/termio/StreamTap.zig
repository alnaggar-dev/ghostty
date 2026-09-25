//! StreamTap mirrors the PTY byte stream to an embedder and tracks the
//! cumulative number of PTY bytes fed to the terminal parser and the number
//! of grid resizes applied.
//!
//! All methods must be called with the renderer state mutex held. The
//! output and resize callbacks are therefore totally ordered with each
//! other and with any reader of `offset` that holds the same mutex.
const StreamTap = @This();

const std = @import("std");
const testing = std.testing;

pub const OutputFn = *const fn (
    ?*anyopaque,
    u64,
    [*]const u8,
    usize,
) callconv(.c) void;

pub const ResizeFn = *const fn (
    ?*anyopaque,
    u64,
    u64,
    u32,
    u32,
) callconv(.c) void;

pub const Callbacks = extern struct {
    userdata: ?*anyopaque = null,
    output: ?OutputFn = null,
    resize: ?ResizeFn = null,
};

callbacks: Callbacks = .{},

/// Cumulative count of PTY bytes handed to the parser. Every byte below
/// this offset has been fully parsed once the mutex is released.
offset: u64 = 0,

/// Number of grid resizes applied so far, counted whether or not callbacks
/// are installed. Resizes do not advance `offset`, so several resizes can
/// share one offset; this count orders them against any reader of it that
/// holds the mutex (for example a snapshot).
resize_seq: u64 = 0,

/// Report a chunk of PTY output that is about to be parsed and advance
/// the offset past it. The chunk must be parsed before the mutex is
/// released.
pub fn output(self: *StreamTap, buf: []const u8) void {
    const start = self.offset;
    self.offset += buf.len;
    const cb = self.callbacks.output orelse return;
    cb(self.callbacks.userdata, start, buf.ptr, buf.len);
}

/// Report that the terminal grid changed size at the current offset. The
/// callback receives the resize's sequence number: the Nth resize ever
/// applied reports N.
pub fn resized(self: *StreamTap, cols: u32, rows: u32) void {
    self.resize_seq += 1;
    const cb = self.callbacks.resize orelse return;
    cb(self.callbacks.userdata, self.offset, self.resize_seq, cols, rows);
}

const Recorder = struct {
    events: std.ArrayList(Event) = .empty,

    const Event = union(enum) {
        output: struct { offset: u64, len: usize },
        resize: struct { offset: u64, seq: u64, cols: u32, rows: u32 },
    };

    fn onOutput(ud: ?*anyopaque, offset: u64, _: [*]const u8, len: usize) callconv(.c) void {
        const self: *Recorder = @ptrCast(@alignCast(ud.?));
        self.events.append(testing.allocator, .{ .output = .{
            .offset = offset,
            .len = len,
        } }) catch unreachable;
    }

    fn onResize(ud: ?*anyopaque, offset: u64, seq: u64, cols: u32, rows: u32) callconv(.c) void {
        const self: *Recorder = @ptrCast(@alignCast(ud.?));
        self.events.append(testing.allocator, .{ .resize = .{
            .offset = offset,
            .seq = seq,
            .cols = cols,
            .rows = rows,
        } }) catch unreachable;
    }

    fn callbacks(self: *Recorder) Callbacks {
        return .{
            .userdata = self,
            .output = &onOutput,
            .resize = &onResize,
        };
    }
};

test "output reports the offset of the first byte of each chunk" {
    var rec: Recorder = .{};
    defer rec.events.deinit(testing.allocator);

    var tap: StreamTap = .{ .callbacks = rec.callbacks() };
    tap.output("hello");
    tap.output("");
    tap.output("world!");

    try testing.expectEqual(@as(u64, 11), tap.offset);
    try testing.expectEqualSlices(Recorder.Event, &.{
        .{ .output = .{ .offset = 0, .len = 5 } },
        .{ .output = .{ .offset = 5, .len = 0 } },
        .{ .output = .{ .offset = 5, .len = 6 } },
    }, rec.events.items);
}

test "offset and resize sequence advance while no callbacks are installed" {
    var rec: Recorder = .{};
    defer rec.events.deinit(testing.allocator);

    var tap: StreamTap = .{};
    tap.output("abc");
    tap.resized(80, 24);
    tap.callbacks = rec.callbacks();
    tap.output("de");
    tap.resized(90, 30);
    tap.callbacks = .{};
    tap.output("fgh");
    tap.resized(70, 20);

    try testing.expectEqual(@as(u64, 8), tap.offset);
    try testing.expectEqual(@as(u64, 3), tap.resize_seq);
    try testing.expectEqualSlices(Recorder.Event, &.{
        .{ .output = .{ .offset = 3, .len = 2 } },
        .{ .resize = .{ .offset = 5, .seq = 2, .cols = 90, .rows = 30 } },
    }, rec.events.items);
}

test "resizes at one offset carry the offset and increasing sequence numbers" {
    var rec: Recorder = .{};
    defer rec.events.deinit(testing.allocator);

    var tap: StreamTap = .{ .callbacks = rec.callbacks() };
    tap.output("0123");
    tap.resized(120, 40);
    tap.resized(100, 30);
    tap.output("45");

    try testing.expectEqualSlices(Recorder.Event, &.{
        .{ .output = .{ .offset = 0, .len = 4 } },
        .{ .resize = .{ .offset = 4, .seq = 1, .cols = 120, .rows = 40 } },
        .{ .resize = .{ .offset = 4, .seq = 2, .cols = 100, .rows = 30 } },
        .{ .output = .{ .offset = 4, .len = 2 } },
    }, rec.events.items);
}
