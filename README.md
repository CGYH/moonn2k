# moonn2k

**moonn2k** is a pure-MoonBit, offline-verifiable NMEA 2000 protocol toolkit:
extended 29-bit CAN ID / PGN parsing, single-frame and Fast Packet codecs,
typed field codecs for 10 selected PGNs, deterministic virtual devices and a
native CLI — all testable without any marine hardware or network access.

It is **not** a hardware driver, not a full J1939 stack, and not a general
CAN toolbox. Scope is deliberately small and honest; see
[docs/protocol-scope.md](docs/protocol-scope.md).

## Why this project

NMEA 2000 is more than "parse 8 bytes": a message must first be routed
through a 29-bit CAN ID (PDU1 vs PDU2), possibly reassembled across up to 32
Fast Packet frames with out-of-order, duplicate and conflicting inputs, and
then decoded bit-by-bit with per-field scaling, lookups and Not-Available
values. moonn2k models each of those layers explicitly in MoonBit, with an
injected clock and structured errors, so every behaviour is reproducible in
tests on wasm-gc, JS and native.

Unlike CAN/J1939 toolkits, moonn2k:

- targets the marine application layer (NMEA 2000 PGNs) end to end;
- keeps the core free of I/O, wall-clock time and hardware access;
- treats unknown PGNs as data (passthrough), never as failures;
- pins every external field-layout reference to a fixed upstream commit.

## Support matrix (P0)

| PGN | Name | Transport | Notes |
|---:|---|---|---|
| 59904 | ISO Request | single frame | 24-bit PGN field |
| 60928 | ISO Address Claim | single frame | 64-bit NAME bit field |
| 126992 | System Time | single frame | date + 0.0001 s time |
| 126993 | Heartbeat | single frame | transmit offset + status bits |
| 126996 | Product Information | Fast Packet | 4 x 32-byte text fields |
| 127250 | Vessel Heading | single frame | signed deviation/variation, lookup |
| 128267 | Water Depth | single frame | 32-bit depth, signed offset |
| 129025 | Position, Rapid Update | single frame | signed 1e-7 degrees |
| 129026 | COG & SOG, Rapid Update | single frame | reference lookup |
| 130306 | Wind Data | single frame | 3-bit reference lookup |

Field layouts are verified against the canboat project's `docs/canboat.json`
pinned at `canboat/canboat@6ce848c6048ae81414c90dd3cee57699f98c6738`
(SchemaVersion 2.8.0). See `THIRD_PARTY.md` and `docs/pgn-support.md`.

## Quick start

Install the toolchain pinned in `.moonbit-version`, then:

```bash
moon check --deny-warn
moon test
moon run cmd/n2k --target native -- id 0x19F80196
```

Expected output:

```text
raw=0x19f80196 priority=6 data_page=1 pdu_format=248 pdu_specific=1 source=150 pgn=129025 pdu=PDU2
```

### CLI tour

```bash
# Explain a 29-bit CAN ID (JSON envelope)
moon run cmd/n2k --target native -- id 0x18EAFFFE --json

# Decode a Position, Rapid Update payload
moon run cmd/n2k --target native -- decode --pgn 129025 --hex 40a13120fa0cfbf9 --json

# Decode one CAN frame end to end
moon run cmd/n2k --target native -- decode-frame --id 0x19F80196 --data 40a13120fa0cfbf9 --json

# Segment a 16-byte payload into Fast Packet frames
moon run cmd/n2k --target native -- fast-send --id 0x19F80505 --hex 00112233445566778899aabbccddeeff --json

# Run the deterministic scenario (25 frames, 5 single + 20 fast packet)
moon run cmd/n2k --target native -- simulate --scenario basic --json

# Internal consistency checks (exit 0 / 6)
moon run cmd/n2k --target native -- selftest
```

Exit codes: `0` success, `2` usage, `3` input parsing, `4` protocol, `6`
selftest failure (errors go to stderr; `--json` stdout carries only the
envelope).

## Development

```bash
moon fmt --check                 # formatting gate
moon check --deny-warn           # compile gate (all targets in CI)
moon test --target all           # unit + state machine + vector tests
moon run cmd/n2k --target native -- selftest
```

The core never reads files, never touches the wall clock and never opens a
network socket. Fast Packet reassembly receives its time at every call site
(`now_ms`), which makes timeout behaviour exactly testable.

## Repository layout

```text
src/protocol      errors, diagnostics
src/identifier    29-bit CAN ID, PGN model
src/frame         CAN frame, hex codec
src/bits          bounded BitReader / BitWriter (LSB-first)
src/message       Message / Transport model
src/fast_packet   sender segmentation, reassembler state machine
src/codec         FieldValue model
src/registry      PGN metadata, router, generic encode/decode
src/pgn           the 10 P0 PGN layouts + typed helpers
src/simulator     deterministic scenario devices
src/cli           command logic, JSON envelopes
cmd/n2k           native entry point
fixtures          pinned reference vectors
docs              architecture, scope, testing, support matrix, acceptance
examples          minimal runnable examples
```

## License

Apache-2.0. Third-party reference sources are documented in `NOTICE` and
`THIRD_PARTY.md`. NMEA 2000 is a proprietary standard of the National Marine
Electronics Association; this is an independent implementation based on
public information, not endorsed by or affiliated with NMEA.

## Status

P0 complete: all ten PGNs, Fast Packet send/receive with robustness
policies, simulator and CLI. AI assistance is documented in
`docs/ai-usage.md`; the development log in `docs/development-log.md`
records what was built in which order.
