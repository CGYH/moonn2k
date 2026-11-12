// Identifier test suite (plan section 8.4 A, ID-001..ID-014).
//
// Reference vectors are hand-derived from the bit layout in plan 3.2 and
// cross-checked against the canboat project's ID interpretation; see
// fixtures/identifier.json for source notes.

///|
/// ID-001: all-zero identifier parses with all-zero fields (PDU1, PGN 0).
test "ID-001 all-zero identifier parses" {
  let id = @identifier.CanId::from_raw(0U)
  assert_eq(id.priority(), 0)
  assert_eq(id.reserved_bit(), 0)
  assert_eq(id.data_page(), 0)
  assert_eq(id.pdu_format(), 0)
  assert_eq(id.pdu_specific(), 0)
  assert_eq(id.source(), 0)
  assert_eq(id.is_pdu1(), true)
  assert_eq(id.destination(), Some(0))
  assert_eq(id.pgn().value, 0)
}

///|
/// ID-002: maximum 29-bit value parses; every field is all ones.
test "ID-002 maximum 29-bit identifier parses" {
  let id = @identifier.CanId::from_raw(0x1FFFFFFFU)
  assert_eq(id.priority(), 7)
  assert_eq(id.reserved_bit(), 1)
  assert_eq(id.data_page(), 1)
  assert_eq(id.pdu_format(), 255)
  assert_eq(id.pdu_specific(), 255)
  assert_eq(id.source(), 255)
  assert_eq(id.is_pdu1(), false)
  assert_eq(id.pgn().value, 0x1FFFF)
}

///|
/// ID-003: values beyond 29 bits are rejected with InvalidCanId.
test "ID-003 value beyond 29 bits rejected" {
  let mut got_error = false
  let mut raw_seen = 0U
  try {
    let _ignored = @identifier.CanId::from_raw(0x20000000U)
  } catch {
    @protocol.InvalidCanId(raw~, ..) => {
      got_error = true
      raw_seen = raw
    }
    _ => ()
  }
  assert_true(got_error)
  assert_eq(raw_seen, 0x20000000U)
}

///|
/// ID-004: PF=239 is PDU1; PS is the destination, excluded from the PGN.
test "ID-004 PF 239 is PDU1" {
  let id = @identifier.CanId::make(
    priority=6,
    data_page=0,
    pdu_format=239,
    pdu_specific=100,
    source=50,
  )
  assert_eq(id.is_pdu1(), true)
  assert_eq(id.destination(), Some(100))
  assert_eq(id.pgn().value, 239 << 8)
  assert_eq(id.pgn().is_pdu1, true)
}

///|
/// ID-005: PF=240 is PDU2; PS joins the PGN low 8 bits, destination is None.
test "ID-005 PF 240 is PDU2" {
  let id = @identifier.CanId::make(
    priority=6,
    data_page=0,
    pdu_format=240,
    pdu_specific=7,
    source=50,
  )
  assert_eq(id.is_pdu1(), false)
  assert_eq(id.destination(), None)
  assert_eq(id.pgn().value, (240 << 8) | 7)
  assert_eq(id.pgn().is_pdu1, false)
}

///|
/// ID-006: PDU1 destination extraction (ISO Request to global address 255).
test "ID-006 PDU1 destination extracted" {
  let id = @identifier.CanId::from_raw(0x18EAFFFEU)
  assert_eq(id.is_pdu1(), true)
  assert_eq(id.destination(), Some(255))
  assert_eq(id.pdu_specific(), 255)
}

///|
/// ID-007: PDU2 destination is None (Position Rapid Update broadcast).
test "ID-007 PDU2 destination is None" {
  let id = @identifier.CanId::from_raw(0x19F80196U)
  assert_eq(id.is_pdu1(), false)
  assert_eq(id.destination(), None)
}

///|
/// ID-008: source address extraction.
test "ID-008 source address" {
  assert_eq(@identifier.CanId::from_raw(0x18EAFFFEU).source(), 254)
  assert_eq(@identifier.CanId::from_raw(0x19F80196U).source(), 150)
}

///|
/// ID-009: priority extraction across the full 0..7 range.
test "ID-009 priority range" {
  for p in [0, 1, 2, 3, 4, 5, 6, 7] {
    let id = @identifier.CanId::make(
      priority=p,
      data_page=0,
      pdu_format=240,
      pdu_specific=0,
      source=0,
    )
    assert_eq(id.priority(), p)
  }
}

///|
/// ID-010: construct -> raw -> parse round-trip on representative inputs.
test "ID-010 construct/parse round-trip" {
  let samples = [
    (0, 0, 0, 0, 0),
    (7, 1, 255, 255, 255),
    (6, 0, 234, 255, 254),
    (6, 1, 248, 1, 150),
    (3, 0, 239, 128, 33),
    (2, 0, 240, 0, 255),
  ]
  for sample in samples {
    let made = @identifier.CanId::make(
      priority=sample.0,
      data_page=sample.1,
      pdu_format=sample.2,
      pdu_specific=sample.3,
      source=sample.4,
    )
    let parsed = @identifier.CanId::from_raw(made.to_raw())
    assert_eq(parsed, made)
    assert_eq(parsed.priority(), sample.0)
    assert_eq(parsed.data_page(), sample.1)
    assert_eq(parsed.pdu_format(), sample.2)
    assert_eq(parsed.pdu_specific(), sample.3)
    assert_eq(parsed.source(), sample.4)
  }
}

///|
/// ID-011: ISO Request reference vector (PGN 59904, PDU1, dest 255).
/// Hand-derived: priority 6, dp 0, PF 0xEA (234), PS 0xFF, source 0xFE.
test "ID-011 ISO Request vector" {
  let id = @identifier.CanId::from_raw(0x18EAFFFEU)
  assert_eq(id.priority(), 6)
  assert_eq(id.data_page(), 0)
  assert_eq(id.pdu_format(), 234)
  assert_eq(id.pdu_specific(), 255)
  assert_eq(id.source(), 254)
  let pgn = id.pgn()
  assert_eq(pgn.value, 59904)
  assert_eq(pgn.is_pdu1, true)
  assert_eq(pgn.destination, Some(255))
}

///|
/// ID-012: Position Rapid Update reference vector (PGN 129025, PDU2).
/// Hand-derived from plan 3.2: priority 6, dp 1, PF 0xF8 (248), PS 0x01,
/// source 0x96 (150). PGN = (1 << 16) | (248 << 8) | 1 = 129025.
test "ID-012 Position Rapid Update vector" {
  let id = @identifier.CanId::from_raw(0x19F80196U)
  assert_eq(id.priority(), 6)
  assert_eq(id.data_page(), 1)
  assert_eq(id.pdu_format(), 248)
  assert_eq(id.pdu_specific(), 1)
  assert_eq(id.source(), 150)
  let pgn = id.pgn()
  assert_eq(pgn.value, 129025)
  assert_eq(pgn.is_pdu1, false)
  assert_eq(pgn.destination, None)
}

///|
/// ID-013: strict mode rejects a set reserved bit.
test "ID-013 strict mode reserved bit rejected" {
  // priority 6 | reserved bit 25 | source 0x55, data page 0.
  let raw = 0x1A000055U
  let lenient_id = @identifier.CanId::from_raw(raw)
  assert_eq(lenient_id.reserved_bit(), 1)
  let mut got_error = false
  let mut raw_seen = 0U
  try {
    let _ignored = @identifier.CanId::from_raw_strict(raw)
  } catch {
    @protocol.InvalidCanId(raw~, ..) => {
      got_error = true
      raw_seen = raw
    }
    _ => ()
  }
  assert_true(got_error)
  assert_eq(raw_seen, 0x1A000055U)
}

///|
/// ID-014: lenient mode accepts with a diagnostic; clean IDs have none.
test "ID-014 lenient mode diagnostics" {
  let flagged = @identifier.CanId::from_raw(0x1A000055U)
  let diags = flagged.diagnostics()
  assert_eq(diags.length(), 1)
  assert_eq(diags[0].code, "ReservedBitSet")
  assert_eq(diags[0].severity, @protocol.Warning)
  let clean = @identifier.CanId::from_raw(0x19F80196U)
  assert_eq(clean.diagnostics().length(), 0)
}
