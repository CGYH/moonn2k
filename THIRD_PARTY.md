# Third-party sources

This file records every external source used for protocol definitions,
reference vectors or implementation cross-checks, with the version that was
pinned during development (plan sections 3.6, 13).

## canboat (field layouts)

- Upstream: https://github.com/canboat/canboat
- File used: `docs/canboat.json`
- Pinned revision: `canboat/canboat@6ce848c6048ae81414c90dd3cee57699f98c6738`
  (SchemaVersion 2.8.0, master commit dated 2026-11-12, fetched 2026-11-12)
- License: Apache-2.0 (as stated by the upstream project)
- What was used: per-PGN field names, bit offsets, bit lengths, units,
  resolutions and signedness for the ten P0 PGNs (59904, 60928, 126992,
  126993, 126996, 127250, 128267, 129025, 129026, 130306). No code was
  copied; the layouts were re-implemented in MoonBit.
- Modifications: none to the upstream data.

## Not-Available patterns

The canboat definitions above do not carry per-field NA values. The NA
patterns in `src/pgn/metadata.mbt` (all-ones for unsigned radian/speed/
date/time fields, 0x7FFFFFFF for 1e-7 degree positions, 0x7FFF for signed
millimetre offsets) follow common NMEA 2000 practice. They are engineering
choices, not claims about the standard, and each is flagged in
`fixtures/pgn-vectors.json`.

## Fast Packet padding

The 0xFF padding of short final frames (plan 5.8) is an engineering choice
aligned with common implementations. Receivers derive valid payload bytes
from the declared length, so padding never leaks into decoded values.

## moonbitlang/core

- Runtime dependency of every MoonBit project, resolved by the pinned
  toolchain in `.moonbit-version` (`0.1.20261104`, moonc v0.10.20).
- License: Apache-2.0.
