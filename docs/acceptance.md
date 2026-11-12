# Acceptance

## Evidence table

| Acceptance point | Evidence | Status |
|---|---|---|
| MoonBit is the implementation language | `src/**/*.mbt`, `cmd/n2k/main.mbt` | done |
| Core has no I/O / wall clock / hardware | no `@env`/file imports in `src/**` (CLI only reads `@env.args()` inside `cmd/n2k`) | done |
| 29-bit ID semantics | `src/identifier/can_id_test.mbt` (ID-001..014) | done |
| Hex/frame rules | `src/frame/hex_test.mbt` (HEX-001..008) | done |
| Bit reader/writer | `src/bits/*_test.mbt` (BIT-001..010) | done |
| Fast Packet sender | `src/fast_packet/sender_test.mbt` (FPS-001..010, all lengths 9..223) | done |
| Fast Packet reassembler | `src/fast_packet/reassembler_test.mbt` (FPR-001..026) | done |
| 10 PGN codecs + vectors | `src/pgn/pgn_test.mbt`, `fixtures/pgn-vectors.json` | done |
| Unknown PGN passthrough | `src/registry/registry_test.mbt` | done |
| Deterministic simulator | `src/simulator/simulator_test.mbt` (SIM-001..006) | done |
| CLI six commands + exit codes | `src/cli/cli_test.mbt` (CLI-001..010) | done |
| CI gates on 3 targets | `.github/workflows/ci.yml` (fmt / check / test × wasm-gc, js, native) | done |
| Pinned references | `THIRD_PARTY.md` (canboat@6ce848c6) | done |
| Honest scope | `docs/protocol-scope.md` | done |

## Reproduction steps (clean environment)

```bash
# 1. clone
git clone https://github.com/CGYH/moonn2k && cd moonn2k

# 2. install the pinned toolchain (version in .moonbit-version)
#    Linux/macOS:
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
#    Windows (PowerShell):
#      Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
#      irm https://cli.moonbitlang.com/install/powershell.ps1 | iex

# 3. gates
moon fmt --check
moon check --target all --deny-warn
moon test --target all

# 4. build and run the CLI
moon build --target native
./_build/native/debug/build/cmd/n2k/n2k.exe id 0x19F80196
./_build/native/debug/build/cmd/n2k/n2k.exe selftest

# 5. deterministic demo
./_build/native/debug/build/cmd/n2k/n2k.exe simulate --scenario basic --json
```

## Recorded local run (2026-11-12, toolchain 0.1.20261104 / moonc v0.10.20)

```text
moon test --target all
  Total tests: 117, passed: 117, failed: 0. [wasm-gc]
  Total tests: 117, passed: 117, failed: 0. [js]
  Total tests: 117, passed: 117, failed: 0. [native]
moon fmt --check   -> clean
moon check --deny-warn -> clean (all targets)
n2k selftest -> can-id-roundtrip ok, hex-roundtrip ok,
                fast-packet-roundtrip ok, pgn-roundtrip ok
```

## Known gaps (not hidden)

- Differential testing against a second reference decoder (e.g. canboatjs
  binary output) has not been run; layouts are pinned to the canboat JSON
  database instead.
- NA patterns are common practice, not verified against official NMEA data.
- No fuzzing beyond deterministic pseudo-random bit round-trips.
- mooncakes.io publication has not been done (requires account).
- The GitHub repository URL in `moon.mod` assumes `CGYH/moonn2k`; adjust if
  the final repository name differs.
