# Architecture

## Layering

```text
  cmd/n2k (native glue: argv -> Output -> stdout/stderr/exit)
     │
  src/cli      command logic, JSON envelopes      ┐ adaptation layer
  src/simulator deterministic virtual devices      ┘
     │
  src/pgn       10 P0 PGN layouts, typed helpers
  src/registry  PGN metadata, router, generic encode/decode
  src/codec     FieldValue model
     │
  src/message        Message / Transport
  src/fast_packet    sender segmentation, reassembler state machine
  src/frame          CAN frame, hex codec
  src/identifier     29-bit CAN ID, PGN
  src/bits           bounded BitReader / BitWriter
  src/protocol       ProtocolError, Diagnostic
```

## Why core and CLI are separated

The core (`src/**` except `src/cli`, `cmd/**`) compiles to wasm-gc, JS and
native with zero platform surface: no files, no sockets, no wall clock. The
CLI is a native-only adapter. This keeps every protocol decision testable
on all three targets and makes the library consumable from a browser or an
embedded wasm host without dragging command-line concerns along.

## Why Fast Packet uses explicit session state

Fast Packet transfers are multi-frame conversations: frames arrive out of
order, duplicated, conflicting, or interleaved across senders. A pure
function cannot express "which frames have we already seen". The reassembler
therefore keeps an explicit, bounded session table keyed by
`(pgn, source, destination, sequence_id)`, with two states per session:
`AwaitingFirstFrame` (bounded staging of later frames) and `Active`
(declared length known, payload buffer allocated). All policies — idempotent
duplicates, conflicting duplicates, restarts, session caps, tombstones — are
fixed, documented and individually tested (FPR-001..026).

## Why the clock is injected

Timeouts decide when sessions die, but the canboat documentation does not
define a standard timeout value (plan 3.4). moonn2k therefore treats
`timeout_ms` as configuration and time as a parameter: `ingest(frame,
now_ms)` and `expire(now_ms)` take virtual time explicitly. Tests advance
time deterministically and verify behaviour at `timeout - 1`, exactly at
`timeout`, and after. The default (1000 ms) is documented as a project
choice, never as a standard constant.

## Error model

Every failure mode is a typed `ProtocolError` variant carrying structured
context (raw value, PGN, field name, offsets, limits). Unknown PGNs are not
errors: the router passes them through as data. Lenient parsing attaches
non-fatal `Diagnostic` findings instead of failing. Errors never embed
machine paths, usernames or wall-clock stamps, so output stays reproducible.

## Bit order

NMEA 2000 uses LSB-first bit numbering. `BitReader`/`BitWriter` assemble
values so bit `i` of the result equals bit `offset+i` of the buffer;
byte-aligned reads then behave as little-endian integers. All PGN codecs go
through this one pair of primitives — no PGN does its own offset arithmetic.
