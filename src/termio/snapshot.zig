//! Rich terminal snapshot for embedders (`ghostty_surface_read_snapshot`).
//!
//! The snapshot captures everything needed to reproduce the live terminal
//! state with a fresh VT parser: styled grids for both screens, styled
//! scrollback, cursor and saved cursor state, modes, charsets, colors and
//! title. It always reads the live (active) screen area, never the
//! scrolled viewport.
//!
//! The extern structs in this file are the C ABI declared in
//! `include/ghostty.h` and must be kept in sync with it.
const std = @import("std");
const build_options = @import("terminal_options");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const testing = std.testing;
const terminal = @import("../terminal/main.zig");
const Terminal = terminal.Terminal;
const Screen = terminal.Screen;
const Page = terminal.Page;
const Pin = terminal.Pin;
const Style = terminal.Style;

// ghostty_snapshot_color_tag_e
pub const ColorTag = enum(u8) {
    default = 0,
    palette = 1,
    rgb = 2,
};

// ghostty_snapshot_style_flags_e
pub const StyleFlag = struct {
    pub const bold: u16 = 1 << 0;
    pub const italic: u16 = 1 << 1;
    pub const faint: u16 = 1 << 2;
    pub const blink: u16 = 1 << 3;
    pub const inverse: u16 = 1 << 4;
    pub const invisible: u16 = 1 << 5;
    pub const strikethrough: u16 = 1 << 6;
    pub const overline: u16 = 1 << 7;
};

// ghostty_snapshot_wide_e
pub const Wide = enum(u8) {
    narrow = 0,
    wide = 1,
    spacer_tail = 2,
    spacer_head = 3,
};

// ghostty_snapshot_color_s
pub const Color = extern struct {
    tag: u8 = @intFromEnum(ColorTag.default),
    index: u8 = 0,
    _reserved: u16 = 0,
    rgb: u32 = 0,
};

// ghostty_snapshot_style_s
pub const StyleOut = extern struct {
    fg: Color = .{},
    bg: Color = .{},
    underline_color: Color = .{},
    flags: u16 = 0,
    underline: u8 = 0,
    _reserved: u8 = 0,
};

// ghostty_snapshot_cell_s
pub const Cell = extern struct {
    text_offset: u32 = 0,
    text_len: u32 = 0,
    style: StyleOut = .{},
    wide: u8 = @intFromEnum(Wide.narrow),
    _reserved: [3]u8 = .{ 0, 0, 0 },
};

// ghostty_snapshot_row_s
pub const Row = extern struct {
    wrap: bool = false,
    wrap_continuation: bool = false,
};

// ghostty_snapshot_grid_s
pub const Grid = extern struct {
    cells: ?[*]const Cell = null,
    row_info: ?[*]const Row = null,
    cols: u32 = 0,
    rows: u32 = 0,
};

// ghostty_snapshot_charsets_s
pub const Charsets = extern struct {
    g: [4]u8 = .{ 0, 0, 0, 0 },
    gl: u8 = 0,
    gr: u8 = 2,
    single_shift: i8 = -1,
    _reserved: u8 = 0,
};

// ghostty_snapshot_cursor_s
pub const Cursor = extern struct {
    x: u32 = 0,
    y: u32 = 0,
    pen: StyleOut = .{},
    pending_wrap: bool = false,
    is_protected: bool = false,
    style: u8 = 0,
    _reserved: u8 = 0,
};

// ghostty_snapshot_saved_cursor_s
pub const SavedCursor = extern struct {
    present: bool = false,
    pending_wrap: bool = false,
    origin: bool = false,
    is_protected: bool = false,
    x: u32 = 0,
    y: u32 = 0,
    pen: StyleOut = .{},
    charsets: Charsets = .{},
};

// ghostty_snapshot_image_format_e
pub const ImageFormat = enum(u8) {
    rgb = 0,
    rgba = 1,
    gray = 2,
    gray_alpha = 3,
};

// ghostty_snapshot_image_s
pub const ImageOut = extern struct {
    id: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    format: u8 = @intFromEnum(ImageFormat.rgba),
    _reserved: [3]u8 = .{ 0, 0, 0 },
    data: ?[*]const u8 = null,
    data_len: usize = 0,
};

// ghostty_snapshot_placement_s
pub const PlacementOut = extern struct {
    image_id: u32 = 0,
    placement_id: u32 = 0,
    columns: u32 = 0,
    rows: u32 = 0,
};

// ghostty_snapshot_screen_s
pub const ScreenOut = extern struct {
    present: bool = false,
    kitty_keyboard_flags: u8 = 0,
    _reserved: u16 = 0,
    grid: Grid = .{},
    cursor: Cursor = .{},
    saved_cursor: SavedCursor = .{},
    charsets: Charsets = .{},
    images: ?[*]const ImageOut = null,
    images_len: usize = 0,
    virtual_placements: ?[*]const PlacementOut = null,
    virtual_placements_len: usize = 0,
};

// ghostty_snapshot_modes_s
pub const Modes = extern struct {
    wraparound: bool = true,
    origin: bool = false,
    insert: bool = false,
    cursor_keys: bool = false,
    keypad: bool = false,
    bracketed_paste: bool = false,
    focus_event: bool = false,
    cursor_visible: bool = true,
    cursor_blinking: bool = false,
    reverse_colors: bool = false,
    linefeed: bool = false,
    left_right_margin: bool = false,
    mouse_event: u16 = 0,
    mouse_format: u16 = 0,
};

// ghostty_snapshot_scroll_region_s
pub const ScrollRegion = extern struct {
    top: u32 = 0,
    bottom: u32 = 0,
    left: u32 = 0,
    right: u32 = 0,
};

// ghostty_snapshot_dynamic_color_s
pub const DynamicColor = extern struct {
    set: bool = false,
    overridden: bool = false,
    _reserved: u16 = 0,
    rgb: u32 = 0,
};

// ghostty_snapshot_colors_s
pub const Colors = extern struct {
    palette: [256]u32 = @splat(0),
    palette_overridden: [32]u8 = @splat(0),
    foreground: DynamicColor = .{},
    background: DynamicColor = .{},
    cursor: DynamicColor = .{},
};

// ghostty_surface_snapshot_s
pub const Snapshot = extern struct {
    parsed_offset: u64 = 0,
    resize_seq: u64 = 0,
    parser_ground: bool = false,
    alt_screen_active: bool = false,
    alt_screen_mode: u16 = 0,
    cols: u32 = 0,
    rows: u32 = 0,
    primary: ScreenOut = .{},
    alternate: ScreenOut = .{},
    scrollback: Grid = .{},
    modes: Modes = .{},
    scroll_region: ScrollRegion = .{},
    colors: Colors = .{},
    title: ?[*:0]const u8 = null,
    title_len: usize = 0,
    text: ?[*]const u8 = null,
    text_len: usize = 0,
    _internal: ?*anyopaque = null,
};

pub const Options = struct {
    max_scrollback_rows: u32,
    parsed_offset: u64,
    resize_seq: u64,
    parser_ground: bool,
};

/// Build a snapshot of the terminal into `out`. The caller must hold the
/// terminal lock for the duration of the call. On success `out` owns its
/// memory and must be released with `free` using the same allocator. On
/// failure every byte of `out` is zero and nothing is left allocated.
pub fn read(
    gpa: Allocator,
    t: *const Terminal,
    opts: Options,
    out: *Snapshot,
) Allocator.Error!void {
    errdefer out.* = zeroed;
    out.* = try build(gpa, t, opts);
}

/// Release a snapshot filled by `read`, leaving it zeroed. Safe to call
/// twice.
pub fn free(gpa: Allocator, s: *Snapshot) void {
    const ptr = s._internal orelse return;
    const arena: *ArenaAllocator = @ptrCast(@alignCast(ptr));
    arena.deinit();
    gpa.destroy(arena);
    s.* = zeroed;
}

const zeroed = std.mem.zeroes(Snapshot);

fn build(gpa: Allocator, t: *const Terminal, opts: Options) Allocator.Error!Snapshot {
    const arena = try gpa.create(ArenaAllocator);
    arena.* = .init(gpa);
    errdefer {
        arena.deinit();
        gpa.destroy(arena);
    }

    var b: Builder = .{ .alloc = arena.allocator() };
    var out: Snapshot = .{
        .parsed_offset = opts.parsed_offset,
        .resize_seq = opts.resize_seq,
        .parser_ground = opts.parser_ground,
        .alt_screen_active = t.screens.active_key == .alternate,
        .alt_screen_mode = altScreenMode(t),
        .cols = t.cols,
        .rows = t.rows,
        .modes = modes(t),
        .scroll_region = .{
            .top = t.scrolling_region.top,
            .bottom = t.scrolling_region.bottom,
            .left = t.scrolling_region.left,
            .right = t.scrolling_region.right,
        },
        .colors = colors(t),
        ._internal = arena,
    };

    if (t.screens.get(.primary)) |s| {
        out.primary = try b.screen(s);
        out.scrollback = try b.scrollback(s, opts.max_scrollback_rows);
    }
    if (t.screens.get(.alternate)) |s| out.alternate = try b.screen(s);

    if (t.getTitle()) |title| {
        const copy = try b.alloc.dupeZ(u8, title);
        out.title = copy.ptr;
        out.title_len = copy.len;
    }

    if (b.text.items.len > 0) {
        out.text = b.text.items.ptr;
        out.text_len = b.text.items.len;
    }

    return out;
}

const Builder = struct {
    alloc: Allocator,
    text: std.ArrayList(u8) = .empty,

    fn screen(self: *Builder, s: *const Screen) Allocator.Error!ScreenOut {
        const pages = &s.pages;
        var out: ScreenOut = .{
            .present = true,
            .kitty_keyboard_flags = s.kitty_keyboard.current().int(),
            .grid = try self.grid(pages.getTopLeft(.active), pages.cols, pages.rows),
            .cursor = .{
                .x = s.cursor.x,
                .y = s.cursor.y,
                .pen = styleOut(s.cursor.style),
                .pending_wrap = s.cursor.pending_wrap,
                .is_protected = s.cursor.protected,
                .style = @intFromEnum(s.cursor.cursor_style),
            },
            .saved_cursor = if (s.saved_cursor) |sc| .{
                .present = true,
                .pending_wrap = sc.pending_wrap,
                .origin = sc.origin,
                .is_protected = sc.protected,
                .x = sc.x,
                .y = sc.y,
                .pen = styleOut(sc.style),
                .charsets = charsets(sc.charset),
            } else .{},
            .charsets = charsets(s.charset),
        };
        if (comptime build_options.kitty_graphics) try self.kittyImages(s, &out);
        return out;
    }

    fn kittyImages(self: *Builder, s: *const Screen, out: *ScreenOut) Allocator.Error!void {
        const storage = &s.kitty_images;

        const sources = try self.alloc.alloc(terminal.kitty.graphics.Image, storage.images.count());
        var it = storage.images.valueIterator();
        var i: usize = 0;
        while (it.next()) |img| : (i += 1) sources[i] = img.*;
        std.mem.sortUnstable(terminal.kitty.graphics.Image, sources, {}, struct {
            fn lessThan(_: void, a: terminal.kitty.graphics.Image, b: terminal.kitty.graphics.Image) bool {
                return a.generation < b.generation;
            }
        }.lessThan);

        const images = try self.alloc.alloc(ImageOut, sources.len);
        var images_len: usize = 0;
        for (sources) |img| {
            const format: ImageFormat = switch (img.format) {
                .rgb => .rgb,
                .rgba => .rgba,
                .gray => .gray,
                .gray_alpha => .gray_alpha,
                .png => continue,
            };
            const data = try self.alloc.dupe(u8, img.data);
            images[images_len] = .{
                .id = img.id,
                .width = img.width,
                .height = img.height,
                .format = @intFromEnum(format),
                .data = data.ptr,
                .data_len = data.len,
            };
            images_len += 1;
        }
        if (images_len > 0) {
            out.images = images.ptr;
            out.images_len = images_len;
        }

        const placements = try self.alloc.alloc(PlacementOut, storage.placements.count());
        var placements_len: usize = 0;
        var pit = storage.placements.iterator();
        while (pit.next()) |entry| {
            if (entry.value_ptr.location != .virtual) continue;
            const key = entry.key_ptr.*;
            placements[placements_len] = .{
                .image_id = key.image_id,
                .placement_id = switch (key.placement_id.tag) {
                    .external => key.placement_id.id,
                    .internal => 0,
                },
                .columns = entry.value_ptr.columns,
                .rows = entry.value_ptr.rows,
            };
            placements_len += 1;
        }
        if (placements_len > 0) {
            out.virtual_placements = placements.ptr;
            out.virtual_placements_len = placements_len;
        }
    }

    fn scrollback(self: *Builder, s: *const Screen, max: u32) Allocator.Error!Grid {
        const pages = &s.pages;
        const history = pages.total_rows - pages.rows;
        const count = @min(history, max);
        if (count == 0) return .{ .cols = pages.cols };
        const start = pages.getTopLeft(.active).up(count).?;
        return try self.grid(start, pages.cols, count);
    }

    fn grid(self: *Builder, start: Pin, cols: usize, rows: usize) Allocator.Error!Grid {
        const cells = try self.alloc.alloc(Cell, cols * rows);
        const row_info = try self.alloc.alloc(Row, rows);
        @memset(cells, .{});

        var pin = start;
        for (0..rows) |y| {
            if (y > 0) pin = pin.down(1).?;
            const page = pin.node.page();
            const rac = pin.rowAndCell();
            row_info[y] = .{
                .wrap = rac.row.wrap,
                .wrap_continuation = rac.row.wrap_continuation,
            };
            const src = page.getCells(rac.row);
            const dst = cells[y * cols ..][0..cols];
            for (src[0..@min(src.len, cols)], 0..) |*c, x| {
                dst[x] = try self.cell(page, c);
            }
        }

        return .{
            .cells = cells.ptr,
            .row_info = row_info.ptr,
            .cols = @intCast(cols),
            .rows = @intCast(rows),
        };
    }

    fn cell(self: *Builder, page: *const Page, c: *const terminal.Cell) Allocator.Error!Cell {
        var out: Cell = .{
            .wide = @intFromEnum(switch (c.wide) {
                .narrow => Wide.narrow,
                .wide => Wide.wide,
                .spacer_tail => Wide.spacer_tail,
                .spacer_head => Wide.spacer_head,
            }),
        };
        if (c.hasStyling()) {
            out.style = styleOut(page.styles.get(page.memory, c.style_id).*);
        }

        switch (c.content_tag) {
            .bg_color_palette => out.style.bg = .{
                .tag = @intFromEnum(ColorTag.palette),
                .index = c.content.color_palette,
            },
            .bg_color_rgb => out.style.bg = .{
                .tag = @intFromEnum(ColorTag.rgb),
                .rgb = rgbPack(c.content.color_rgb.r, c.content.color_rgb.g, c.content.color_rgb.b),
            },
            .codepoint, .codepoint_grapheme => {
                if (!c.hasText()) return out;
                const start = self.text.items.len;
                try self.appendCodepoint(c.codepoint());
                if (c.hasGrapheme()) {
                    if (page.lookupGrapheme(c)) |cps| {
                        for (cps) |cp| try self.appendCodepoint(cp);
                    }
                }
                out.text_offset = @intCast(start);
                out.text_len = @intCast(self.text.items.len - start);
            },
        }
        return out;
    }

    fn appendCodepoint(self: *Builder, cp: u21) Allocator.Error!void {
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &buf) catch
            std.unicode.utf8Encode(std.unicode.replacement_character, &buf) catch unreachable;
        try self.text.appendSlice(self.alloc, buf[0..len]);
    }
};

fn styleOut(s: Style) StyleOut {
    var flags: u16 = 0;
    if (s.flags.bold) flags |= StyleFlag.bold;
    if (s.flags.italic) flags |= StyleFlag.italic;
    if (s.flags.faint) flags |= StyleFlag.faint;
    if (s.flags.blink) flags |= StyleFlag.blink;
    if (s.flags.inverse) flags |= StyleFlag.inverse;
    if (s.flags.invisible) flags |= StyleFlag.invisible;
    if (s.flags.strikethrough) flags |= StyleFlag.strikethrough;
    if (s.flags.overline) flags |= StyleFlag.overline;
    return .{
        .fg = colorOut(s.fg_color),
        .bg = colorOut(s.bg_color),
        .underline_color = colorOut(s.underline_color),
        .flags = flags,
        .underline = @intFromEnum(s.flags.underline),
    };
}

fn colorOut(c: Style.Color) Color {
    return switch (c) {
        .none => .{},
        .palette => |idx| .{ .tag = @intFromEnum(ColorTag.palette), .index = idx },
        .rgb => |rgb| .{ .tag = @intFromEnum(ColorTag.rgb), .rgb = rgbPack(rgb.r, rgb.g, rgb.b) },
    };
}

fn charsets(cs: Screen.CharsetState) Charsets {
    return .{
        .g = .{
            @intFromEnum(cs.charsets.g0),
            @intFromEnum(cs.charsets.g1),
            @intFromEnum(cs.charsets.g2),
            @intFromEnum(cs.charsets.g3),
        },
        .gl = @intFromEnum(cs.gl),
        .gr = @intFromEnum(cs.gr),
        .single_shift = if (cs.single_shift) |slot| @intCast(@intFromEnum(slot)) else -1,
    };
}

fn altScreenMode(t: *const Terminal) u16 {
    if (t.screens.active_key != .alternate) return 0;
    if (t.modes.get(.alt_screen_save_cursor_clear_enter)) return 1049;
    if (t.modes.get(.alt_screen)) return 1047;
    if (t.modes.get(.alt_screen_legacy)) return 47;
    return 0;
}

fn modes(t: *const Terminal) Modes {
    return .{
        .wraparound = t.modes.get(.wraparound),
        .origin = t.modes.get(.origin),
        .insert = t.modes.get(.insert),
        .cursor_keys = t.modes.get(.cursor_keys),
        .keypad = t.modes.get(.keypad_keys),
        .bracketed_paste = t.modes.get(.bracketed_paste),
        .focus_event = t.modes.get(.focus_event),
        .cursor_visible = t.modes.get(.cursor_visible),
        .cursor_blinking = t.modes.get(.cursor_blinking),
        .reverse_colors = t.modes.get(.reverse_colors),
        .linefeed = t.modes.get(.linefeed),
        .left_right_margin = t.modes.get(.enable_left_and_right_margin),
        .mouse_event = switch (t.flags.mouse_event) {
            .none => 0,
            .x10 => 9,
            .normal => 1000,
            .button => 1002,
            .any => 1003,
        },
        .mouse_format = switch (t.flags.mouse_format) {
            .x10 => 0,
            .utf8 => 1005,
            .sgr => 1006,
            .urxvt => 1015,
            .sgr_pixels => 1016,
        },
    };
}

fn colors(t: *const Terminal) Colors {
    var out: Colors = .{
        .foreground = dynamicColor(t.colors.foreground),
        .background = dynamicColor(t.colors.background),
        .cursor = dynamicColor(t.colors.cursor),
    };
    const palette = &t.colors.palette;
    for (palette.current, 0..) |rgb, i| {
        out.palette[i] = rgbPack(rgb.r, rgb.g, rgb.b);
        if (palette.mask.isSet(i)) out.palette_overridden[i / 8] |= @as(u8, 1) << @intCast(i % 8);
    }
    return out;
}

fn dynamicColor(c: terminal.color.DynamicRGB) DynamicColor {
    const rgb = c.override orelse c.default orelse return .{};
    return .{
        .set = true,
        .overridden = c.override != null,
        .rgb = rgbPack(rgb.r, rgb.g, rgb.b),
    };
}

inline fn rgbPack(r: u8, g: u8, b: u8) u32 {
    return (@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b);
}

fn cellText(s: *const Snapshot, c: Cell) []const u8 {
    if (c.text_len == 0) return "";
    return s.text.?[c.text_offset..][0..c.text_len];
}

fn gridCell(g: Grid, x: usize, y: usize) Cell {
    return g.cells.?[y * g.cols + x];
}

fn rowText(alloc: Allocator, s: *const Snapshot, g: Grid, y: usize) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(alloc);
    for (0..g.cols) |x| try buf.appendSlice(alloc, cellText(s, gridCell(g, x, y)));
    return buf.toOwnedSlice(alloc);
}

fn expectRow(s: *const Snapshot, g: Grid, y: usize, expected: []const u8) !void {
    const actual = try rowText(testing.allocator, s, g, y);
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(expected, actual);
}

const TestTerm = struct {
    t: Terminal,
    stream: terminal.TerminalStream,

    fn init(cols: u16, rows: u16) !*TestTerm {
        const self = try testing.allocator.create(TestTerm);
        errdefer testing.allocator.destroy(self);
        self.t = try .init(testing.allocator, .{ .cols = cols, .rows = rows });
        self.stream = self.t.vtStream();
        return self;
    }

    fn deinit(self: *TestTerm) void {
        self.stream.deinit();
        self.t.deinit(testing.allocator);
        testing.allocator.destroy(self);
    }

    fn feed(self: *TestTerm, bytes: []const u8) void {
        self.stream.nextSlice(bytes);
    }

    fn snapshot(self: *TestTerm, max_scrollback_rows: u32) !Snapshot {
        var out: Snapshot = undefined;
        try read(testing.allocator, &self.t, .{
            .max_scrollback_rows = max_scrollback_rows,
            .parsed_offset = 0,
            .resize_seq = 0,
            .parser_ground = self.stream.isGround(),
        }, &out);
        return out;
    }
};

test "snapshot cells carry grapheme text, colors, attributes and width" {
    const tt = try TestTerm.init(10, 3);
    defer tt.deinit();
    tt.feed("\x1b[1;31mA\x1b[0m");
    tt.feed("e\u{301}");
    tt.feed("\u{4E2D}");
    tt.feed("\x1b[3;38;2;1;2;3;48;5;200;4:3;58;5;7mZ\x1b[0m");

    var s = try tt.snapshot(0);
    defer free(testing.allocator, &s);
    const g = s.primary.grid;

    const a = gridCell(g, 0, 0);
    try testing.expectEqualStrings("A", cellText(&s, a));
    try testing.expectEqual(StyleFlag.bold, a.style.flags);
    try testing.expectEqual(@intFromEnum(ColorTag.palette), a.style.fg.tag);
    try testing.expectEqual(@as(u8, 1), a.style.fg.index);
    try testing.expectEqual(@intFromEnum(ColorTag.default), a.style.bg.tag);

    const e = gridCell(g, 1, 0);
    try testing.expectEqualStrings("e\u{301}", cellText(&s, e));
    try testing.expectEqual(@as(u16, 0), e.style.flags);

    const wide = gridCell(g, 2, 0);
    try testing.expectEqualStrings("\u{4E2D}", cellText(&s, wide));
    try testing.expectEqual(@intFromEnum(Wide.wide), wide.wide);
    const tail = gridCell(g, 3, 0);
    try testing.expectEqualStrings("", cellText(&s, tail));
    try testing.expectEqual(@intFromEnum(Wide.spacer_tail), tail.wide);

    const z = gridCell(g, 4, 0);
    try testing.expectEqualStrings("Z", cellText(&s, z));
    try testing.expectEqual(StyleFlag.italic, z.style.flags);
    try testing.expectEqual(@intFromEnum(ColorTag.rgb), z.style.fg.tag);
    try testing.expectEqual(@as(u32, 0x010203), z.style.fg.rgb);
    try testing.expectEqual(@intFromEnum(ColorTag.palette), z.style.bg.tag);
    try testing.expectEqual(@as(u8, 200), z.style.bg.index);
    try testing.expectEqual(@as(u8, 3), z.style.underline);
    try testing.expectEqual(@intFromEnum(ColorTag.palette), z.style.underline_color.tag);
    try testing.expectEqual(@as(u8, 7), z.style.underline_color.index);

    const empty = gridCell(g, 5, 0);
    try testing.expectEqual(@as(u32, 0), empty.text_len);
    try testing.expectEqual(@intFromEnum(ColorTag.default), empty.style.fg.tag);
}

test "snapshot keeps background-only cells from colored erase" {
    const tt = try TestTerm.init(4, 2);
    defer tt.deinit();
    tt.feed("\x1b[44m\x1b[2K\x1b[0m");

    var s = try tt.snapshot(0);
    defer free(testing.allocator, &s);
    const c = gridCell(s.primary.grid, 3, 0);
    try testing.expectEqual(@as(u32, 0), c.text_len);
    try testing.expectEqual(@intFromEnum(ColorTag.palette), c.style.bg.tag);
    try testing.expectEqual(@as(u8, 4), c.style.bg.index);
}

test "snapshot marks soft-wrapped rows but not hard line breaks" {
    const tt = try TestTerm.init(5, 4);
    defer tt.deinit();
    tt.feed("abcdefg\r\nxy");

    var s = try tt.snapshot(0);
    defer free(testing.allocator, &s);
    const rows = s.primary.grid.row_info.?;
    try testing.expect(rows[0].wrap);
    try testing.expect(!rows[0].wrap_continuation);
    try testing.expect(!rows[1].wrap);
    try testing.expect(rows[1].wrap_continuation);
    try testing.expect(!rows[2].wrap);
    try testing.expect(!rows[2].wrap_continuation);
    try expectRow(&s, s.primary.grid, 0, "abcde");
    try expectRow(&s, s.primary.grid, 1, "fg");
    try expectRow(&s, s.primary.grid, 2, "xy");
}

test "snapshot reads the live screen and bounded scrollback, not the viewport" {
    const tt = try TestTerm.init(4, 2);
    defer tt.deinit();
    tt.feed("l0\r\nl1\r\nl2\r\nl3\r\nl4\r\nl5");
    tt.t.scrollViewport(.{ .delta = -3 });

    var s = try tt.snapshot(3);
    defer free(testing.allocator, &s);
    try testing.expectEqual(@as(u32, 2), s.primary.grid.rows);
    try expectRow(&s, s.primary.grid, 0, "l4");
    try expectRow(&s, s.primary.grid, 1, "l5");
    try testing.expectEqual(@as(u32, 1), s.primary.cursor.y);
    try testing.expectEqual(@as(u32, 2), s.primary.cursor.x);

    try testing.expectEqual(@as(u32, 3), s.scrollback.rows);
    try testing.expectEqual(@as(u32, 4), s.scrollback.cols);
    try expectRow(&s, s.scrollback, 0, "l1");
    try expectRow(&s, s.scrollback, 1, "l2");
    try expectRow(&s, s.scrollback, 2, "l3");

    var all = try tt.snapshot(100);
    defer free(testing.allocator, &all);
    try testing.expectEqual(@as(u32, 4), all.scrollback.rows);
    try expectRow(&all, all.scrollback, 0, "l0");

    var none = try tt.snapshot(0);
    defer free(testing.allocator, &none);
    try testing.expectEqual(@as(u32, 0), none.scrollback.rows);
    try testing.expect(none.scrollback.cells == null);
}

test "snapshot captures both grids while the alternate screen is active" {
    const tt = try TestTerm.init(8, 3);
    defer tt.deinit();

    var before = try tt.snapshot(10);
    defer free(testing.allocator, &before);
    try testing.expect(!before.alt_screen_active);
    try testing.expectEqual(@as(u16, 0), before.alt_screen_mode);
    try testing.expect(before.primary.present);

    tt.feed("prompt\r\n$ ");
    tt.feed("\x1b[?1049h");
    tt.feed("\x1b[2;3Hvim");

    var s = try tt.snapshot(10);
    defer free(testing.allocator, &s);
    try testing.expect(s.alt_screen_active);
    try testing.expectEqual(@as(u16, 1049), s.alt_screen_mode);
    try testing.expect(s.alternate.present);
    try expectRow(&s, s.primary.grid, 0, "prompt");
    try expectRow(&s, s.primary.grid, 1, "$ ");
    try expectRow(&s, s.alternate.grid, 0, "");
    try expectRow(&s, s.alternate.grid, 1, "vim");
    try testing.expectEqual(@as(u32, 5), s.alternate.cursor.x);
    try testing.expectEqual(@as(u32, 1), s.alternate.cursor.y);
    try testing.expectEqual(@as(u32, 2), s.primary.cursor.x);
    try testing.expectEqual(@as(u32, 1), s.primary.cursor.y);
    try testing.expect(s.primary.saved_cursor.present);
    try testing.expectEqual(@as(u32, 2), s.primary.saved_cursor.x);
    try testing.expectEqual(@as(u32, 1), s.primary.saved_cursor.y);
    try testing.expectEqual(@as(u32, 0), s.scrollback.rows);

    tt.feed("\x1b[?1049l");
    var after = try tt.snapshot(10);
    defer free(testing.allocator, &after);
    try testing.expect(!after.alt_screen_active);
    try testing.expectEqual(@as(u16, 0), after.alt_screen_mode);
}

test "snapshot captures cursor pen, pending wrap, saved cursor and charsets" {
    const tt = try TestTerm.init(5, 3);
    defer tt.deinit();
    tt.feed("\x1b[2;2H\x1b[4m\x1b7");
    tt.feed("\x1b[0;3;38;5;9m\x1b[1;1Habcde");
    tt.feed("\x1b(0\x1b*A\x0e");

    var s = try tt.snapshot(0);
    defer free(testing.allocator, &s);
    const c = s.primary.cursor;
    try testing.expectEqual(@as(u32, 4), c.x);
    try testing.expectEqual(@as(u32, 0), c.y);
    try testing.expect(c.pending_wrap);
    try testing.expectEqual(StyleFlag.italic, c.pen.flags);
    try testing.expectEqual(@intFromEnum(ColorTag.palette), c.pen.fg.tag);
    try testing.expectEqual(@as(u8, 9), c.pen.fg.index);

    const sc = s.primary.saved_cursor;
    try testing.expect(sc.present);
    try testing.expectEqual(@as(u32, 1), sc.x);
    try testing.expectEqual(@as(u32, 1), sc.y);
    try testing.expectEqual(@as(u8, 1), sc.pen.underline);
    try testing.expect(!sc.pending_wrap);

    const cs = s.primary.charsets;
    try testing.expectEqual(@intFromEnum(terminal.Charset.dec_special), cs.g[0]);
    try testing.expectEqual(@intFromEnum(terminal.Charset.british), cs.g[2]);
    try testing.expectEqual(@intFromEnum(terminal.CharsetSlot.G1), cs.gl);
    try testing.expectEqual(@as(i8, -1), cs.single_shift);
    try testing.expectEqual(@intFromEnum(terminal.Charset.utf8), sc.charsets.g[0]);
}

test "snapshot captures modes, scroll region, palette and title" {
    const tt = try TestTerm.init(10, 6);
    defer tt.deinit();

    var fresh = try tt.snapshot(0);
    defer free(testing.allocator, &fresh);
    try testing.expect(fresh.modes.wraparound);
    try testing.expect(fresh.modes.cursor_visible);
    try testing.expectEqual(@as(u16, 0), fresh.modes.mouse_event);
    try testing.expectEqual(@as(u32, 0), fresh.scroll_region.top);
    try testing.expectEqual(@as(u32, 5), fresh.scroll_region.bottom);
    try testing.expect(fresh.title == null);

    tt.feed("\x1b[?7l\x1b[?6h\x1b[4h\x1b[?1h\x1b=\x1b[?2004h\x1b[?1004h\x1b[?25l");
    tt.feed("\x1b[?1002h\x1b[?1006h\x1b[>5u\x1b[2;4r");
    tt.feed("\x1b]4;1;rgb:10/20/30\x1b\\\x1b]2;hello\x07");

    var s = try tt.snapshot(0);
    defer free(testing.allocator, &s);
    const m = s.modes;
    try testing.expect(!m.wraparound);
    try testing.expect(m.origin);
    try testing.expect(m.insert);
    try testing.expect(m.cursor_keys);
    try testing.expect(m.keypad);
    try testing.expect(m.bracketed_paste);
    try testing.expect(m.focus_event);
    try testing.expect(!m.cursor_visible);
    try testing.expectEqual(@as(u16, 1002), m.mouse_event);
    try testing.expectEqual(@as(u16, 1006), m.mouse_format);
    try testing.expectEqual(@as(u8, 5), s.primary.kitty_keyboard_flags);
    try testing.expectEqual(@as(u32, 1), s.scroll_region.top);
    try testing.expectEqual(@as(u32, 3), s.scroll_region.bottom);
    try testing.expectEqual(@as(u32, 0), s.scroll_region.left);
    try testing.expectEqual(@as(u32, 9), s.scroll_region.right);
    try testing.expectEqual(@as(u32, 0x102030), s.colors.palette[1]);
    try testing.expectEqual(@as(u8, 0b10), s.colors.palette_overridden[0]);
    try testing.expectEqual(@as(u8, 0), s.colors.palette_overridden[31]);
    try testing.expectEqualStrings("hello", s.title.?[0..s.title_len]);
    try testing.expectEqual(@as(u8, 0), s.title.?[s.title_len]);
}

test "snapshot exports kitty images and virtual placements per screen" {
    if (comptime !build_options.kitty_graphics) return error.SkipZigTest;
    const tt = try TestTerm.init(10, 4);
    defer tt.deinit();
    tt.feed("\x1b_Ga=t,f=24,s=2,v=1,i=7,q=2;AQIDBAUG\x1b\\");
    tt.feed("\x1b_Ga=p,U=1,i=7,p=3,c=4,r=2,q=2\x1b\\");
    tt.feed("\x1b_Ga=t,f=32,s=1,v=1,i=9,q=2;CgsMDQ==\x1b\\");
    tt.feed("\x1b_Ga=p,i=9,q=2\x1b\\");
    tt.feed("\x1b[?1049h");
    tt.feed("\x1b_Ga=t,f=32,s=1,v=1,i=11,q=2;AAAAAA==\x1b\\");
    tt.feed("\x1b_Ga=p,U=1,i=11,c=1,r=1,q=2\x1b\\");

    var s = try tt.snapshot(0);
    defer free(testing.allocator, &s);

    const p = s.primary;
    try testing.expectEqual(@as(usize, 2), p.images_len);
    const first = p.images.?[0];
    try testing.expectEqual(@as(u32, 7), first.id);
    try testing.expectEqual(@as(u32, 2), first.width);
    try testing.expectEqual(@as(u32, 1), first.height);
    try testing.expectEqual(@intFromEnum(ImageFormat.rgb), first.format);
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 6 }, first.data.?[0..first.data_len]);
    const second = p.images.?[1];
    try testing.expectEqual(@as(u32, 9), second.id);
    try testing.expectEqual(@intFromEnum(ImageFormat.rgba), second.format);
    try testing.expectEqualSlices(u8, &.{ 10, 11, 12, 13 }, second.data.?[0..second.data_len]);

    try testing.expectEqual(@as(usize, 1), p.virtual_placements_len);
    try testing.expectEqual(PlacementOut{ .image_id = 7, .placement_id = 3, .columns = 4, .rows = 2 }, p.virtual_placements.?[0]);

    const a = s.alternate;
    try testing.expectEqual(@as(usize, 1), a.images_len);
    try testing.expectEqual(@as(u32, 11), a.images.?[0].id);
    try testing.expectEqual(@as(usize, 1), a.virtual_placements_len);
    try testing.expectEqual(PlacementOut{ .image_id = 11, .placement_id = 0, .columns = 1, .rows = 1 }, a.virtual_placements.?[0]);

    tt.feed("\x1b_Ga=d,d=I,i=11,q=2\x1b\\");
    var cleared = try tt.snapshot(0);
    defer free(testing.allocator, &cleared);
    try testing.expectEqual(@as(usize, 0), cleared.alternate.images_len);
    try testing.expect(cleared.alternate.images == null);
    try testing.expect(cleared.alternate.virtual_placements == null);
    try testing.expectEqual(@as(usize, 2), cleared.primary.images_len);
}

test "snapshot free releases memory once and zeroes the snapshot" {
    const tt = try TestTerm.init(4, 2);
    defer tt.deinit();
    tt.feed("ab");

    var s = try tt.snapshot(0);
    free(testing.allocator, &s);
    try testing.expectEqual(zeroed, s);
    free(testing.allocator, &s);
    try testing.expectEqual(zeroed, s);
}

test "snapshot read failure at any allocation zeroes the output and leaks nothing" {
    const tt = try TestTerm.init(6, 3);
    defer tt.deinit();
    tt.feed("l0\r\nl1\r\nl2\r\n\x1b]2;t\x07e\u{301}");
    tt.feed("\x1b_Ga=t,f=24,s=1,v=1,i=5,q=2;AQID\x1b\\\x1b_Ga=p,U=1,i=5,c=1,r=1,q=2\x1b\\");
    tt.feed("\x1b[?1049hx");

    const opts: Options = .{
        .max_scrollback_rows = 10,
        .parsed_offset = 7,
        .resize_seq = 3,
        .parser_ground = true,
    };
    var fail_index: usize = 0;
    while (true) : (fail_index += 1) {
        var failing: testing.FailingAllocator = .init(testing.allocator, .{
            .fail_index = fail_index,
        });
        const gpa = failing.allocator();
        var out: Snapshot = .{};
        read(gpa, &tt.t, opts, &out) catch |err| {
            try testing.expectEqual(error.OutOfMemory, err);
            try testing.expectEqual(zeroed, out);
            continue;
        };
        defer free(gpa, &out);
        try testing.expect(fail_index > 0);
        try testing.expectEqual(@as(u64, 7), out.parsed_offset);
        try testing.expectEqual(@as(u64, 3), out.resize_seq);
        try testing.expect(out.modes.wraparound);
        break;
    }
}
