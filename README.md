# moonn2k

**moonn2k** is a pure-MoonBit, offline-verifiable NMEA 2000 protocol toolkit:
extended 29-bit CAN ID / PGN parsing, single-frame and Fast Packet codecs,
typed field codecs for 10 selected PGNs, deterministic virtual devices and a
native CLI — all testable without any marine hardware or network access.

> Status: **bootstrap (T00)**. This repository is under active development for
> the MoonBit monthly hackathon. Feature claims live in the support matrix in
> `docs/pgn-support.md` once protocol modules land; nothing beyond this
> bootstrap is implemented yet.

## Development

```bash
moon check --deny-warn
moon test
```

Toolchain is pinned in `.moonbit-version`.

## License

Apache-2.0. Third-party reference sources are documented in `NOTICE` and
`THIRD_PARTY.md`.
