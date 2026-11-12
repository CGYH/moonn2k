# Changelog

All notable changes to moonn2k are documented here.
Format based on Keep a Changelog; versioning is SemVer-ish (0.x during development).

## [0.1.0] - 2026-11-12

P0 complete (hackathon scope). Everything below is covered by 117 tests
running green on wasm-gc, JS and native.

### Added
- Identifier layer: 29-bit CAN ID parse/construct, PDU1/PDU2 split,
  PGN derivation, strict/lenient reserved-bit modes (ID-001..014).
- Frame layer: classic CAN frame with 0..8 byte invariant, canonical hex
  codec (HEX-001..008).
- Bits layer: bounded LSB-first BitReader/BitWriter, 1..64-bit windows,
  signed/unsigned, structured bounds errors (BIT-001..010).
- Fast Packet sender: 9..223 bytes, declared-length headers, 0xFF final
  padding, all-length round-trip (FPS-001..010).
- Fast Packet reassembler: session state machine with bounded staging,
  idempotent duplicates, conflict rejection, restarts, injected clock,
  expiring tombstones, session caps, at-most-once completion
  (FPR-001..026).
- Codec/registry: FieldValue model (raw + physical), instance-scoped PGN
  registry, unknown-PGN passthrough, field-context errors.
- Typed codecs for 59904, 60928, 126992, 126993, 126996, 127250, 128267,
  129025, 129026, 130306 with layouts pinned to canboat@6ce848c6 and
  reference vectors in fixtures (PGN tests incl. Fast Packet end-to-end).
- Deterministic simulator: "basic" scenario, virtual time steps
  (SIM-001..006).
- CLI: id / decode / decode-frame / fast-send / simulate / selftest with
  plan-25 JSON envelopes and exit codes 0/2/3/4/6 (CLI-001..010).
- CI: fmt/check/test gates on wasm-gc, js and native.
- Docs: architecture, protocol scope, testing, PGN support matrix,
  acceptance evidence, development log, AI usage, THIRD_PARTY pinning.

### Notes
- Toolchain pinned at 0.1.20261104 via .moonbit-version.
- NA patterns and final-frame padding are documented engineering choices,
  not standard constants.
