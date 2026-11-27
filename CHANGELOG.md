# Changelog

All notable changes to moonn2k are documented here.
Format based on Keep a Changelog; versioning is SemVer-ish (0.x during development).

## [0.1.1] - 2026-11-27

Toolchain and CI correctness release. **No behavioural change**: no payload
layout, JSON envelope key or exit code was touched.

### Changed
- Toolchain moved from release `0.1.20261104` (moonc v0.10.20) to
  `0.1.20261126` (moonc v1.0.0-rc1), which is the version the project now
  targets and the minimum the CI enforces (`.moonc-minimum`).
- Published to mooncakes.io as `CGYH/moonn2k` 0.1.1 (Apache-2.0). Consumers
  install it with `moon add CGYH/moonn2k`; the package page and generated API
  docs are at <https://mooncakes.io/docs/CGYH/moonn2k>. This version is
  immutable: corrections ship as 0.1.2.
- `moon fmt` output for multi-line enum constructor payloads now carries a
  trailing comma on the last field; four declarations in
  `src/protocol/error.mbt` and `src/registry/decode.mbt` were reordered by
  the new formatter. Formatting only.

### Fixed
- CI never reached its `check` and `test` steps: the toolchain step was named
  "pinned by .moonbit-version" but only ran the unpinned installer, so the
  runner silently used a newer formatter than the local pin and
  `moon fmt --check` aborted the job at step 4. The step is now honest about
  what is possible: the MoonBit CDN serves only the `latest` archive (every
  versioned path answers `403 Forbidden`), so the release cannot be pinned at
  download time. CI therefore installs `latest` and asserts the compiler floor
  from `.moonc-minimum`, failing the job if `moonc` is older — including on a
  cache hit. `.moonbit-version` now documents the release verified locally and
  a mismatch produces a warning instead of a false reproducibility claim.
- CI now also runs `moon build` and a CLI/examples smoke job, so the
  check / build / test triple is covered on all three targets.

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
