# Testing

## Gates

Every commit must pass:

```bash
moon fmt --check
moon check --target all --deny-warn
moon test --target all
```

CI (`.github/workflows/ci.yml`) runs the same three gates on wasm-gc, JS
and native.

## Test inventory

| Suite | Prefix | Count | What it covers |
|---|---|---:|---|
| identifier | ID- | 16 | 29-bit parse/construct, PDU1/PDU2, strict/lenient reserved bit, reference vectors |
| hex/frame | HEX- | 6 | empty/8/9 bytes, odd length, bad chars, separators, canonical output |
| bits | BIT- | 5 | 1/8/16/32/64-bit reads, unaligned, signed, bounds, write isolation, random round-trip |
| protocol errors | — | 3 | every error variant constructed, pattern matching, diagnostics |
| fast packet send | FPS- | 10 | length bounds 8/9/13/14/223/224, headers, padding, full-length round-trip |
| fast packet recv | FPR- | 26 | order, duplicates, conflicts, staging, restarts, timeouts, caps, tombstones |
| registry/codec | — | 7 | instance isolation, matrix order, scaling, lookup, NA, passthrough, truncation context |
| PGN | PGN- | 12 | per-PGN normal/NA/bounds/truncation/round-trip/reference vectors, e2e |
| simulator | SIM- | 6 | determinism, time steps, transports, stack pass-through, field equality |
| CLI | CLI- | 12 | six commands, exit codes 0/2/3/4, stream separation, envelope shape |

Property-style checks are embedded where they matter most: FPS-010
segment/reassemble for **every** legal payload length 9..223, BIT-010
fixed-seed pseudo-random write/read round-trips, SIM-001 byte-identical
scenario runs.

## Reference vectors

`fixtures/` carries the pinned inputs:

- `identifier.json` — hand-derived CAN ID vectors (ISO Request 0x18EAFFFE,
  Position Rapid Update 0x19F80196, reserved-bit cases), with a note where
  the execution plan's own example contradicted its formula.
- `fast_packet.json` — segmentation vectors for 9/13/14/223-byte payloads.
- `pgn-vectors.json` — per-PGN payload vectors derived from the pinned
  canboat layouts, including NA variants and a 134-byte Product Information
  payload.

Round-trip tests prove internal consistency only; wire compatibility rests
on the pinned canboat layouts (THIRD_PARTY.md).

## What is deliberately not tested

- Timing beyond the injected clock (no sleeps anywhere).
- Real CAN hardware or socket I/O (out of scope by design).
- Snapshot equality across MoonBit versions (toolchain is pinned instead).
