# moonn2k agent guide

## Scope
Pure MoonBit NMEA 2000 toolkit. P0 only: CAN ID, PGN, single frame, Fast Packet,
10 selected PGNs, simulator, CLI and tests. No hardware, no full J1939 TP, no Web UI.

## Commands
- moon fmt --check
- moon check --target all --deny-warn
- moon test --target all --deny-warn
- moon run cmd/n2k --target native -- selftest

## Rules
- Core packages depend only on moonbitlang/core.
- No file, network, wall-clock or hardware access in core.
- Do not modify fixtures to hide a bug.
- Do not delete or skip failing tests.
- Pin and document every external reference version.
- Unknown PGNs pass through; malformed known PGNs return structured errors.
- Keep each change limited to one module and its tests.
- One task package at a time (T00..T13, see the execution plan document).
