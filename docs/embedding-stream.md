# Embedding API: PTY stream, resize events and snapshots

These exports in `include/ghostty.h` let an embedder mirror a surface to a
remote terminal emulator (for example xterm.js on a phone) without gaps:
take a snapshot, then continue with the exact PTY bytes that follow it.

## Offset space

Every surface counts the PTY bytes it feeds to its VT parser, starting at 0
when the surface is created. All offsets below are in this single cumulative
space. Output chunks are reported and parsed while the terminal lock is held,
so "bytes below offset N" always means "bytes fully applied to the terminal
state".

## `ghostty_surface_set_stream_callbacks`

```c
typedef void (*ghostty_surface_output_cb)(void* userdata, uint64_t offset,
                                          const uint8_t* bytes, uintptr_t len);
typedef void (*ghostty_surface_resize_cb)(void* userdata, uint64_t offset,
                                          uint64_t seq, uint32_t cols,
                                          uint32_t rows);
typedef struct {
  void* userdata;
  ghostty_surface_output_cb output;
  ghostty_surface_resize_cb resize;
} ghostty_surface_stream_callbacks_s;

void ghostty_surface_set_stream_callbacks(ghostty_surface_t,
                                          const ghostty_surface_stream_callbacks_s*);
```

- `output` receives each PTY chunk with the offset of its first byte,
  immediately before the chunk is parsed. Consecutive calls are contiguous:
  the next call starts at `offset + len`.
- `resize` fires when the terminal grid size changes because the surface was
  resized. `offset` is the position in the byte stream where the new size took
  effect: bytes below it were parsed at the old size, bytes at or above it at
  the new size. It is not called when a resize leaves the grid size unchanged.
  `seq` is the resize's sequence number: the surface counts every grid resize
  from 1, whether or not callbacks are installed. Resizes do not advance the
  byte offset, so several can share one `offset`; `seq` orders them.
- Both callbacks run on termio threads (the PTY read thread for output, the
  termio thread for resize) while the terminal lock is held. They are totally
  ordered with each other and with `ghostty_surface_read_snapshot`.
- Installing or clearing (pass `NULL`) takes the terminal lock. When the call
  returns, the previous callbacks are not running and will not run again.
- Callbacks must not call into libghostty; copy the bytes and return.
- Grid changes made by the byte stream itself (DECCOLM with mode 40) are not
  reported; the remote emulator sees those sequences in the stream.

## `ghostty_surface_read_snapshot` / `ghostty_surface_free_snapshot`

```c
bool ghostty_surface_read_snapshot(ghostty_surface_t, uint32_t max_scrollback_rows,
                                   ghostty_surface_snapshot_s*);
void ghostty_surface_free_snapshot(ghostty_surface_t, ghostty_surface_snapshot_s*);
```

Reads the **live screen** (the active area), never the scrolled viewport, so
the result does not depend on where the local user has scrolled. The snapshot
is taken atomically under the terminal lock and contains:

- `parsed_offset`: offset of the first byte not yet parsed (the checkpoint).
- `resize_seq`: number of grid resizes applied so far. A resize callback with
  `seq <= resize_seq` is already reflected in the snapshot; one with
  `seq > resize_seq` happened after it.
- `parser_ground`: true if the parser holds no partial escape sequence or
  partial UTF-8 sequence at the checkpoint. When false, the state of the
  in-flight sequence is not part of the snapshot; a fresh parser that starts
  at `parsed_offset` would see the tail of a sequence.
- `primary` and `alternate` screens (`present` is false for a screen that was
  never created). Each has a styled grid of its active area, cursor (position,
  SGR pen, pending-wrap, DECSCUSR shape, protection), saved cursor (DECSC /
  1049), charsets (G0..G3, GL, GR, single shift) and kitty keyboard flags.
  Each screen also carries its Kitty graphics images (`images`, ordered
  oldest transmission first: id, pixel size, format RGB/RGBA/gray/gray+alpha
  and a copy of the decoded pixels; PNG and zlib payloads are already
  decoded) and its virtual placements (`virtual_placements`, `U=1`: image
  id, placement id or 0, columns and rows, 0 when unspecified). Placements
  pinned to cells are not exported.
- `alt_screen_active` and `alt_screen_mode` (47, 1047 or 1049).
- `scrollback`: at most `max_scrollback_rows` history rows directly above the
  primary active area, oldest first; the visible screen is not included.
- `modes`: DECAWM, DECOM, IRM, DECCKM, keypad (DECKPAM/DECNKM), bracketed
  paste, focus events, DECTCEM, cursor blink, DECSCNM, LNM, DECLRMM, mouse
  tracking (0/9/1000/1002/1003) and mouse format (0/1005/1006/1015/1016).
- `scroll_region`: 0-based inclusive top/bottom/left/right margins.
- `colors`: the effective 256-colour palette with a bitmask of OSC 4
  overrides, and the foreground/background/cursor colours with whether they
  were overridden by OSC 10/11/12.
- `title`: the OSC 0/2 title, NUL-terminated, or NULL.

Each cell has its full grapheme cluster as UTF-8 (`text + text_offset`,
`text_len` bytes; 0 for empty and spacer cells), a style with fg/bg/underline
colour as default, palette index or RGB, underline style and bold, italic,
faint, blink, inverse, invisible, strikethrough and overline flags, and a
width class (narrow, wide, spacer tail, spacer head). Background-only cells
produced by erasing with a background colour have no text and a non-default
`bg`. Each row reports `wrap` (soft-wrapped onto the next row) and
`wrap_continuation`.

All pointers in the snapshot stay valid until `ghostty_surface_free_snapshot`,
which is safe to call more than once. A failed read returns false and leaves a
zeroed snapshot.

## Gapless handoff

1. Install stream callbacks and start buffering output chunks.
2. Read a snapshot. Its `parsed_offset` is `C` and its `resize_seq` is `R`.
3. Send the snapshot, then every buffered or future byte at offset `>= C`,
   dropping bytes below `C`. Because output is reported and parsed under the
   same lock as the snapshot, every byte at or above `C` is delivered to the
   callback after it was installed, so there is no gap and no overlap.
4. Forward resize events with `seq > R` in stream order and drop the rest;
   apply the new size before parsing bytes at or above the event offset. Do
   not filter resizes by offset: a resize applied just before the snapshot and
   one applied just after it can both report `offset == C`.

## `ghostty_surface_read_cells` (viewport)

`ghostty_surface_read_cells` reads the **scrolled viewport**: while the local
user is scrolled up it returns scrollback rows, not the live screen. Colours
are resolved to RGB against the current palette and reverse-video mode, and
each cell has only its first codepoint. The cursor position is relative to the
active area. It is meant for local previews; use
`ghostty_surface_read_snapshot` for mirroring.

## `ghostty_surface_set_data_callback` and `ghostty_surface_send_input_raw`

`ghostty_surface_set_data_callback` is the earlier tee: raw PTY chunks with no
offset, invoked on the read thread before parsing and outside the terminal
lock, so it cannot be ordered against a snapshot.
`ghostty_surface_send_input_raw` writes already-encoded bytes straight to the
PTY, bypassing key encoding, bracketed paste and newline handling.
