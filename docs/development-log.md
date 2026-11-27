# Development log

## 2026-11-12 — T00..T13 in one working session

Executed the task packages of the project plan in order. Each package was
compiled, tested and committed independently; test and acceptance gates
were run before every commit.

- **T00 bootstrap** — `chore: bootstrap MoonBit module and CI`
  Toolchain found at `~/.moon` (moon 0.1.20261104, moonc v0.10.20). Module
  skeleton, CI workflow (fmt/check/test × wasm-gc/js/native), Apache-2.0
  scaffolding, `.moonbit-version` pin. Learned: current toolchain wants
  `#derive(...)` before type declarations, `suberror` for raisable error
  types, `Int32` as canonical type name (fmt normalizes), and tests must
  qualify package items (`@pkg.Item`).
- **T01 identifier** — `feat(identifier): ...`
  29-bit CAN ID parse/construct with strict/lenient reserved-bit handling.
  Two plan-document inconsistencies caught and fixed by the section 3.2
  formula: the CLI example `0x18F80196` cannot carry `pgn: 129025` (needs
  `0x19F80196`), and the PGN value space is 17 bits (max 0x1FFFF), not 18.
- **T02 frame/hex** — `feat(frame): ...`
  Canonical lowercase compact hex out; any-case input with space/colon
  separators; hard 0..8 byte frame invariant.
- **T03/T04 bits** — `feat(bits): ...`
  LSB-first reader/writer. The sign-extension mask initially dropped the
  `-1`; BIT-007 caught it. BIT-010 uses a fixed-seed LCG, no wall clock.
- **T05–T07 fast packet** — `feat(fast_packet): ...`
  Sender (FPS-001..010 incl. every legal length round-trip) and the
  reassembler state machine (FPR-001..026). The tombstone initially
  suppressed by key only; FPR-022 showed that would swallow a new transfer
  on the same session key, so completion tombstones now fingerprint the
  first frame (declared length + first 6 payload bytes).
- **T08 codec/registry** — `feat(codec,registry): ...`
  FieldValue keeps raw and physical representations; registry is
  instance-scoped (no global mutable state); unknown PGN passthrough;
  field errors carry pgn+field context.
- **T09–T11 PGNs** — `feat(pgn): ...`
  Downloaded and pinned canboat `docs/canboat.json` (commit 6ce848c6,
  SchemaVersion 2.8.0) through the GitHub API and verified all ten field
  layouts against it. Generated reference vectors programmatically
  (`fixtures/pgn-vectors.json`). Fixed two real bugs the tests exposed:
  signed scaled fields produced garbage physical values (new
  SignedPhysical value), and BitWriter's 64-byte cap rejected the
  134-byte Product Information payload (raised to 223). T11 end-to-end:
  typed encode → segment → shuffled ingest → reassemble → typed decode.
- **T12 simulator/CLI** — `feat(simulator,cli): ...`
  Deterministic basic scenario (SIM-001..006) and the six-command CLI as a
  pure `run(argv) -> Output` function with plan-25 JSON envelopes and exit
  codes 0/2/3/4/6; `cmd/n2k` is 20 lines of glue.
- **T13 docs/acceptance** — this file, README, protocol-scope, testing,
  pgn-support, acceptance evidence, THIRD_PARTY pinning, examples.

Final state: 117 tests green on wasm-gc, js and native; fmt and
`check --deny-warn` clean on all targets.

## 2026-11-27 — toolchain moved to moonc v1.0.0-rc1, CI pin repaired

Two separate defects, both invisible from the badge-free "green" claim above.

**1. The toolchain was below the required compiler version.** Local development
ran on moon `0.1.20261104` / moonc `v0.10.20`, but the competition baseline is
moonc >= `1.0.0-rc1`. Upgrading to moon `0.1.20261126` / moonc
`v1.0.0-rc1+3c0520448` was, to our surprise, almost free: `moon check
--target all --deny-warn` stayed at **zero warnings** with no source change, so
none of the 0.10-era syntax (`#derive`, `suberror`, `Int32`, qualified test
items) needed rewriting. The only fallout was formatting: the new formatter
requires a trailing comma on the last field of a multi-line enum constructor
payload, which reordered `src/protocol/error.mbt` (3 declarations) and
`src/registry/decode.mbt` (1). Nothing semantic changed, which is why 0.1.1 is
a patch release.

**2. CI had never actually run its gates.** Both historical workflow runs
failed at step 4 (`moon fmt --check`, exit 255) and skipped `check` and `test`.
The step was labelled "pinned by .moonbit-version" but its body was just
`curl .../install/unix.sh | bash`, i.e. it installed **latest**. On the runner
that was newer than the local pin, so the newer formatter rejected the older
formatting — the pin existed only in a comment. The lesson is that a
`.moonbit-version` file nobody reads is worse than no file, because it makes
the workflow *look* reproducible.

Fix: `.github/scripts/install-toolchain.sh` reads the release tag from
`.moonbit-version` and passes it to the installer, then asserts the resulting
`moonc` against `.moonc-minimum` with `sort -V -C`. The assertion runs after a
cache restore too, so a stale `~/.moon` cache cannot quietly downgrade the
compiler. The workflow gained a `moon build` step (the old one only had
fmt/check/test but the acceptance wording asks for check *and* build *and*
test) and a smoke job that runs the CLI selftest, one end-to-end decode and
both examples.

Known local limitation, recorded rather than worked around:
`moon test --target native` cannot run on this Windows machine — every runtime
C source fails with `cl.exe ... error D8050: 无法执行 c1.dll`. An empty
`moon new` project fails identically, so it is the local MSVC install, not this
codebase. Native is covered by CI on `ubuntu-latest` instead.
