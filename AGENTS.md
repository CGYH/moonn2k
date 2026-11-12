# moonn2k agent guide

## Scope
Pure MoonBit NMEA 2000 toolkit. P0 is COMPLETE: 29-bit CAN ID, PGN, single
frame, Fast Packet, 10 PGNs, simulator, CLI and tests. No hardware, no full
J1939 TP, no Web UI, no repeating field groups.

## Commands
- moon fmt --check
- moon check --target all --deny-warn
- moon test --target all
- moon run cmd/n2k --target native -- selftest

## Layout
src/protocol (errors) < src/identifier < src/frame < src/bits (sibling),
src/message, src/fast_packet, src/codec + src/registry, src/pgn,
src/simulator, src/cli, cmd/n2k. Fixtures in fixtures/, docs in docs/.

## Rules
- Core packages depend only on moonbitlang/core and each other (no I/O,
  no wall clock, no hardware access; time is always an injected parameter).
- Do not modify fixtures to hide a bug; do not delete or skip failing tests.
- Field layouts must stay pinned to canboat@6ce848c6 (see THIRD_PARTY.md);
  any new PGN needs a verified layout, reference vector and the six test
  classes (normal, bounds, NA, truncation, round-trip, reference).
- Unknown PGNs pass through; known-PGN errors carry pgn+field context.
- JSON envelope keys and exit codes (0/2/3/4/6) are a contract: changes
  require a CHANGELOG entry and a version bump.
- One task package per change; run all three gates before committing.
