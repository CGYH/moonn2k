// @protocol.ProtocolError / @protocol.Diagnostic coverage (plan 8.7: every error variant must be
// triggered by at least one test — NEG-005 groundwork).

///|
/// Every @protocol.ProtocolError variant is constructible with its typed context.
test "protocol error variants carry context" {
  let errors : Array[@protocol.ProtocolError] = [
    InvalidCanId(raw=0x20000000U, reason="range"),
    InvalidFrameLength(length=9, reason="frame"),
    InvalidHex(reason="odd length", input="abc"),
    TruncatedField(
      pgn=129025,
      field="longitude",
      offset=32,
      needed=32,
      available=16,
    ),
    InvalidFieldValue(pgn=127250, field="reference", reason="enum"),
    UnsupportedFieldType(pgn=1, field="x", type_name="f16"),
    InvalidFastPacketLength(declared=8, reason="below minimum"),
    UnexpectedFastFrame(
      reason="unexpected",
      pgn=0,
      source=0,
      sequence_id=0,
      frame_index=0,
    ),
    ConflictingDuplicateFrame(pgn=1, source=2, sequence_id=3, frame_index=4),
    SessionLimitExceeded(limit=8),
    PayloadTooLarge(length=224, limit=223),
    UnknownPgn(pgn=65280),
  ]
  assert_eq(errors.length(), 12)
}

///|
/// @protocol.ProtocolError equality is structural (derived Debug supports diffing in
/// test failures; Eq via == is not required by the API contract).
test "protocol error pattern matching by fields" {
  let err : @protocol.ProtocolError = InvalidCanId(
    raw=0x20000000U,
    reason="range",
  )
  match err {
    InvalidCanId(raw=0x20000000U, reason="range") => ()
    _ => fail("expected matching InvalidCanId")
  }
}

///|
/// @protocol.Diagnostic helpers: severity ordering values and stable context string.
test "diagnostic make and context rendering" {
  let d = @protocol.Diagnostic::make(
    "ReservedBitSet",
    Warning,
    "reserved bit is set",
    context=[("raw", "123"), ("source", "42")],
  )
  assert_eq(d.severity, Warning)
  assert_eq(d.context_string(), "raw=123; source=42")
  let plain = @protocol.Diagnostic::make("Note", Info, "nothing special")
  assert_eq(plain.context_string(), "")
  assert_eq(plain.severity, Info)
}
