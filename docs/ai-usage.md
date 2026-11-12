# AI usage

This project was implemented with heavy AI assistance under a strict
task-package discipline (the "execution plan" document). The arrangement,
per the plan:

- One task package (T00..T13) per working batch; no cross-module edits.
- The test lists (ID/HEX/BIT/FPS/FPR/PGN/SIM/CLI) were fixed before the
  corresponding code; a package was only committed when its gates passed
  (`moon fmt --check`, `moon check --deny-warn`, `moon test --target all`).
- The AI wrote code, tests, docs and the reference-vector generator; a
  human-compatible trail exists as the git history, one commit per package.

What the AI was not allowed to do, and did not do:

- Change frozen scope decisions (the ten PGNs, no hardware, no J1939 TP).
- Invent field layouts: every offset/length came from the pinned canboat
  revision; where the plan document contradicted its own formula (CLI
  example `0x18F80196` vs `pgn 129025`; PGN value space width) the formula
  won and the deviation is recorded in fixtures and the dev log.
- Delete or weaken failing tests: all fixes were made in the
  implementation (e.g. the sign-extension mask, the tombstone fingerprint,
  the BitWriter size cap), never by relaxing assertions.

Honest limits of AI involvement:

- The AI cannot run NMEA 2000 hardware, so wire compatibility rests on the
  pinned canboat layouts plus round-trip consistency, not on device
  measurements.
- Code review was done by the same AI session (self-review against the
  test gates); an independent human review is still worthwhile before the
  hackathon submission.
