// CLI logic tests (plan section 8.4, CLI-001..CLI-010).
//
// The CLI layer is pure: @cli.run(argv) -> Output. Exit codes and stream
// separation are asserted here; cmd/n2k only maps them to the process.

///|
/// CLI-001: id command normal output (JSON shape per plan 25.3).
test "CLI-001 id command" {
  let out = @cli.run(["id", "0x18EAFFFE", "--json"])
  assert_eq(out.exit_code(), @cli.EXIT_OK)
  assert_true(out.stdout().contains("\"command\":\"id\""))
  assert_true(out.stdout().contains("\"pgn\":59904"))
  assert_true(out.stdout().contains("\"pdu\":\"PDU1\""))
  assert_true(out.stdout().contains("\"destination\":255"))
  assert_eq(out.stderr(), "")
}

///|
/// CLI-002: decode command normal output (plan 25.4).
test "CLI-002 decode command" {
  let out = @cli.run([
    "decode", "--pgn", "129025", "--hex", "40a13120fa0cfbf9", "--json",
  ])
  assert_eq(out.exit_code(), @cli.EXIT_OK)
  assert_true(out.stdout().contains("\"name\":\"Position, Rapid Update\""))
  assert_true(out.stdout().contains("\"value\":54.012346"))
  assert_true(out.stdout().contains("\"payload_hex\":\"40a13120fa0cfbf9\""))
}

///|
/// CLI-003: decode-frame normal output.
test "CLI-003 decode-frame command" {
  let out = @cli.run([
    "decode-frame", "--id", "0x19F80196", "--data", "40a13120fa0cfbf9", "--json",
  ])
  assert_eq(out.exit_code(), @cli.EXIT_OK)
  assert_true(out.stdout().contains("\"pgn\":129025"))
  assert_true(out.stdout().contains("\"transport\":\"single-frame\""))
}

///|
/// CLI-004: fast-send normal output (plan 25.5): declared length and
/// frame geometry are part of the contract.
test "CLI-004 fast-send command" {
  let out = @cli.run([
    "fast-send", "--id", "0x19F80505", "--hex", "00112233445566778899aabbccddeeff",
    "--json",
  ])
  assert_eq(out.exit_code(), @cli.EXIT_OK)
  assert_true(out.stdout().contains("\"payload_length\":16"))
  assert_true(out.stdout().contains("\"frame_count\":3"))
  assert_true(out.stdout().contains("\"sequence_id\":0"))
}

///|
/// CLI-005: simulate --json is valid envelope JSON with stable keys.
test "CLI-005 simulate json" {
  let out = @cli.run(["simulate", "--scenario", "basic", "--json"])
  assert_eq(out.exit_code(), @cli.EXIT_OK)
  assert_true(out.stdout().contains("\"scenario\":\"basic\""))
  assert_true(out.stdout().contains("\"frame_count\":25"))
  assert_true(out.stdout().contains("\"duration_ms\":500"))
  // Determinism: two runs identical.
  let again = @cli.run(["simulate", "--scenario", "basic", "--json"])
  assert_eq(out.stdout(), again.stdout())
}

///|
/// CLI-006: selftest passes with exit code 0.
test "CLI-006 selftest" {
  let out = @cli.run(["selftest"])
  assert_eq(out.exit_code(), @cli.EXIT_OK)
  assert_true(out.stdout().contains("selftest ok"))
  let json_out = @cli.run(["selftest", "--json"])
  assert_eq(json_out.exit_code(), @cli.EXIT_OK)
  assert_true(json_out.stdout().contains("\"ok\":true"))
}

///|
/// CLI-007: unknown command -> exit code 2, message on stderr.
test "CLI-007 unknown command exit code" {
  let out = @cli.run(["bogus"])
  assert_eq(out.exit_code(), @cli.EXIT_USAGE)
  assert_eq(out.stdout(), "")
  assert_true(out.stderr().contains("\"code\":\"UsageError\""))
  assert_true(out.stderr().contains("unknown command"))
}

///|
/// CLI-008: invalid hex -> exit code 3.
test "CLI-008 invalid hex exit code" {
  let out = @cli.run(["decode", "--pgn", "129025", "--hex", "zz"])
  assert_eq(out.exit_code(), @cli.EXIT_INPUT)
  assert_true(out.stderr().contains("\"code\":\"InvalidHex\""))
  let bad_id = @cli.run(["id", "nothex"])
  assert_eq(bad_id.exit_code(), @cli.EXIT_INPUT)
  // Beyond 29 bits is a protocol-level rejection (exit 4).
  let over = @cli.run(["id", "0x3FFFFFFF"])
  assert_eq(over.exit_code(), @cli.EXIT_PROTOCOL)
  assert_true(over.stderr().contains("\"code\":\"InvalidCanId\""))
}

///|
/// CLI-009: protocol errors go to stderr, never stdout.
test "CLI-009 protocol error on stderr" {
  let out = @cli.run(["fast-send", "--id", "0x19F80505", "--hex", "00112233"])
  assert_eq(out.exit_code(), @cli.EXIT_PROTOCOL)
  assert_eq(out.stdout(), "")
  assert_true(out.stderr().contains("FastPacketError"))
  assert_eq(@cli.run(["id"]).exit_code(), @cli.EXIT_USAGE)
}

///|
/// CLI-010: help lists the P0 commands.
test "CLI-010 help" {
  let out = @cli.run(["help"])
  assert_eq(out.exit_code(), @cli.EXIT_OK)
  for
    cmd in ["id", "decode", "decode-frame", "fast-send", "simulate", "selftest"] {
    assert_true(out.stdout().contains(cmd))
  }
}

///|
/// JSON envelope shape (plan 25.1/25.2): tool, version, ok, diagnostics.
/// The version comes from the constant rather than a literal, so bumping the
/// tool version does not silently rot this assertion.
test "CLI envelope shape" {
  let out = @cli.run(["id", "0x18EAFFFE", "--json"])
  assert_true(
    out
    .stdout()
    .has_prefix("{\"tool\":\"moonn2k\",\"version\":\"\{@cli.VERSION}\""),
  )
  assert_true(out.stdout().has_suffix(",\"diagnostics\":[]}\n"))
  let err = @cli.run(["id", "0x3FFFFFFF"])
  assert_true(err.stderr().contains("\"ok\":false"))
  assert_true(err.stderr().contains("\"diagnostics\":[]}"))
}
