// @registry.Registry tests (plan 15.10 / 7.5).

///|
fn test_meta() -> @registry.PgnMetadata {
  {
    pgn: 65280,
    name: "Test Message",
    transport: SingleFrame,
    default_priority: 6,
    length: 8,
    fields: [
      {
        name: "temperature",
        field_type: Unsigned,
        bit_offset: 0,
        bit_length: 16,
        resolution: Some(0.01),
        offset: Some(-10.0),
        unit: Some("K"),
        na_raw: Some(0xFFFFUL),
        lookup: [],
      },
      {
        name: "source_mode",
        field_type: Lookup,
        bit_offset: 16,
        bit_length: 4,
        resolution: None,
        offset: None,
        unit: None,
        na_raw: Some(0xFUL),
        lookup: [(0UL, "auto"), (1UL, "manual")],
      },
      {
        name: "reserved",
        field_type: BitField,
        bit_offset: 20,
        bit_length: 4,
        resolution: None,
        offset: None,
        unit: None,
        na_raw: None,
        lookup: [],
      },
    ],
  }
}

///|
/// @registry.Registry is instance-scoped: two registries never interfere.
test "registry instance isolation" {
  let r1 = @registry.Registry::new()
  let r2 = @registry.Registry::new()
  r1.register(test_meta())
  assert_eq(r1.lookup(65280) is Some(_), true)
  assert_eq(r2.lookup(65280) is None, true)
}

///|
/// Support matrix is ordered by PGN and reflects registrations.
test "registry support matrix ordered" {
  let r = @registry.Registry::new()
  r.register(test_meta())
  r.register({
    pgn: 129025,
    name: "Position, Rapid Update",
    transport: SingleFrame,
    default_priority: 6,
    length: 8,
    fields: [],
  })
  r.register({
    pgn: 59904,
    name: "ISO Request",
    transport: SingleFrame,
    default_priority: 6,
    length: 3,
    fields: [],
  })
  let supported = r.supported()
  assert_eq(supported.length(), 3)
  assert_eq(supported[0].pgn, 59904)
  assert_eq(supported[1].pgn, 65280)
  assert_eq(supported[2].pgn, 129025)
}

///|
/// Known PGN decodes with raw + physical + lookup + NA per field definition.
test "decode known pgn with scaling lookup na" {
  let r = @registry.Registry::new()
  r.register(test_meta())
  let id = @identifier.CanId::make(
    priority=6,
    data_page=0,
    pdu_format=255,
    pdu_specific=0,
    source=42,
  )
  // temperature raw 5010 -> 50.10 - 10 = 40.10 K; lookup 1 = manual;
  // reserved bits 0b0101.
  let payload = Bytes::makei(3, fn(i) {
    if i == 0 {
      b'\x92'
    } else if i == 1 {
      b'\x13'
    } else {
      b'\x51'
    }
  })
  let msg = @message.Message::make(
    id,
    payload,
    transport=@message.SingleFrame,
    source_frame_count=1,
  )
  match r.decode(msg) {
    Known(pgn=_, name~, fields~) => {
      assert_eq(name, "Test Message")
      assert_eq(fields[0].0, "temperature")
      match fields[0].1 {
        @codec.Physical(raw, res, off) => {
          assert_eq(raw, 5010UL)
          assert_eq(res, 0.01)
          assert_eq(off, -10.0)
        }
        _ => fail("expected Physical for temperature")
      }
      match fields[1].1 {
        @codec.Lookup(raw, name) => {
          assert_eq(raw, 1UL)
          assert_eq(name, Some("manual"))
        }
        _ => fail("expected Lookup for source_mode")
      }
      match fields[2].1 {
        @codec.Bits(raw) => assert_eq(raw, 5UL)
        _ => fail("expected Bits for reserved")
      }
    }
    Unknown(_) => fail("registered PGN must not be Unknown")
  }
}

///|
/// Exact NA pattern yields NotAvailable; other all-ones patterns do not
/// silently become NA (plan 3.5).
test "decode na pattern only for exact match" {
  let r = @registry.Registry::new()
  r.register(test_meta())
  let id = @identifier.CanId::make(
    priority=6,
    data_page=0,
    pdu_format=255,
    pdu_specific=0,
    source=42,
  )
  // temperature = 0xFFFF (NA); lookup raw = 0xF (NA per its own definition), reserved = 0x5.
  let msg = @message.Message::make(
    id,
    b"\xff\xff\x5f",
    transport=@message.SingleFrame,
    source_frame_count=1,
  )
  match r.decode(msg) {
    Known(pgn=_, name=_, fields~) => {
      assert_eq(fields[0].1, @codec.NotAvailable)
      assert_eq(fields[1].1, @codec.NotAvailable)
    }
    Unknown(_) => fail("registered PGN must not be Unknown")
  }
}

///|
/// Unknown PGN passes through untouched, never an error (plan 7.5).
test "decode unknown pgn passthrough" {
  let r = @registry.Registry::new()
  r.register(test_meta())
  let id = @identifier.CanId::make(
    priority=6,
    data_page=1,
    pdu_format=248,
    pdu_specific=1,
    source=42,
  )
  let msg = @message.Message::make(
    id,
    b"\x01\x02\x03",
    transport=@message.SingleFrame,
    source_frame_count=1,
  )
  match r.decode(msg) {
    Unknown(original) => {
      assert_eq(original.pgn.value, 129025)
      assert_eq(frame_hex(original.payload), "010203")
    }
    Known(..) => fail("unregistered PGN must stay Unknown")
  }
}

///|
fn frame_hex(payload : Bytes) -> String {
  let out = StringBuilder()
  for i in 0..<payload.length() {
    let b = payload.at(i).to_int()
    let hi = b >> 4
    let lo = b & 0xF
    out.write_char(
      (if hi < 10 { 0x30 + hi } else { 0x57 + hi }).unsafe_to_char(),
    )
    out.write_char(
      (if lo < 10 { 0x30 + lo } else { 0x57 + lo }).unsafe_to_char(),
    )
  }
  out.to_string()
}

///|
/// Truncated payloads raise TruncatedField carrying PGN and field context
/// (plan 7.5: field errors get unified context).
test "decode truncation carries field context" {
  let r = @registry.Registry::new()
  r.register(test_meta())
  let id = @identifier.CanId::make(
    priority=6,
    data_page=0,
    pdu_format=255,
    pdu_specific=0,
    source=42,
  )
  // 1 byte only: the 16-bit temperature field cannot fit.
  let msg = @message.Message::make(
    id,
    b"\x92",
    transport=@message.SingleFrame,
    source_frame_count=1,
  )
  let mut context_ok = false
  try {
    let _ignored = r.decode(msg)
  } catch {
    @protocol.TruncatedField(pgn=65280, field="temperature", ..) =>
      context_ok = true
    _ => ()
  }
  assert_true(context_ok)
}
