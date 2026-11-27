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
| CI gates on 3 targets | `.github/workflows/ci.yml` (fmt, then check + build + test × wasm-gc, js, native, plus a CLI/examples smoke job) | done |
| Toolchain requirement enforced | `.moonbit-version` + `.moonc-minimum` asserted by `.github/scripts/install-toolchain.sh`; a stale cache cannot bypass the assertion | done |
| Pinned references | `THIRD_PARTY.md` (canboat@6ce848c6) | done |
| Honest scope | `docs/protocol-scope.md` | done |

## Reproduction steps (clean environment)

```bash
# 1. clone
git clone https://github.com/CGYH/moonn2k && cd moonn2k

# 2. install the pinned toolchain (version in .moonbit-version, floor in .moonc-minimum)
#    Linux/macOS:
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- "$(cat .moonbit-version)"
#    Windows (PowerShell):
#      Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
#      $env:MOONBIT_INSTALL_VERSION = (Get-Content .moonbit-version -Raw).Trim()
#      irm https://cli.moonbitlang.com/install/powershell.ps1 | iex
moon version --all          # moonc must be >= 1.0.0-rc1

# 3. gates
moon fmt --check
moon check --target all --deny-warn
moon test --target all

# 4. build and run the CLI (moon run avoids depending on the artifact path)
moon build --target native
moon run cmd/n2k --target native -- id 0x19F80196
moon run cmd/n2k --target native -- selftest

# 5. deterministic demo
moon run cmd/n2k --target native -- simulate --scenario basic --json
```

## Recorded local run (2026-11-27, toolchain 0.1.20261126 / moonc v1.0.0-rc1)

```text
moon fmt --check        -> clean
moon check --target all --deny-warn -> clean (no warnings)
moon test --target wasm-gc -> Total tests: 117, passed: 117, failed: 0.
moon test --target js      -> Total tests: 117, passed: 117, failed: 0.
```

`native` was **not** reproducible on the Windows development machine used for
this run: `moon test --target native` aborts while compiling the runtime C
sources (`cl.exe ... error D8050: 无法执行 c1.dll`). A freshly created empty
`moon new` project fails the same way on that machine, so the cause is the
local MSVC installation, not this repository. The `native` target is
exercised by CI on `ubuntu-latest` (clang), which is the recorded evidence
for that target — see the CI run linked in the README.

## Known gaps (not hidden)

- Differential testing against a second reference decoder (e.g. canboatjs
  binary output) has not been run; layouts are pinned to the canboat JSON
  database instead.
- NA patterns are common practice, not verified against official NMEA data.
- No fuzzing beyond deterministic pseudo-random bit round-trips.
- mooncakes.io publication has not been done (requires account).
- The GitHub repository URL in `moon.mod` assumes `CGYH/moonn2k`; adjust if
  the final repository name differs.
