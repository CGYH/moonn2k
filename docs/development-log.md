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
