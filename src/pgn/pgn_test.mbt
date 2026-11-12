// PGN codec tests (plan section 7.6: normal, min/max, NA, truncated,
// round-trip, reference vector — per PGN).
//
// Reference payload hex values come from fixtures/pgn-vectors.json,
// hand-derived from the canboat@6ce848c6 field layouts.

///|

///|
fn decode_payload(
  meta : @registry.PgnMetadata,
  payload : Bytes,
) -> Array[(String, @codec.FieldValue)] raise @protocol.ProtocolError {
  let r = @registry.Registry::new()
  r.register(meta)
  let id = meta.make_can_id(source=36)
  let msg = @message.Message::make(
    id,
    payload,
    transport=match meta.transport {
      @registry.SingleFrame => @message.SingleFrame
      @registry.FastPacket => @message.FastPacket
    },
    source_frame_count=1,
  )
  match r.decode(msg) {
    Known(pgn=_, name=_, fields~) => fields
    Unknown(_) => raise @protocol.UnknownPgn(pgn=0)
  }
}

///|
fn field_value(
  fields : Array[(String, @codec.FieldValue)],
  name : String,
) -> @codec.FieldValue raise {
  for pair in fields {
    if pair.0 == name {
      return pair.1
    }
  }
  fail("field not found: \{name}")
}

///|
fn raw_of(v : @codec.FieldValue) -> UInt64 raise {
  match v.raw() {
    Some(r) => r
    None => fail("no raw value")
  }
}

///|
/// T09: 59904 ISO Request reference vector and round-trip.
test "PGN-59904 ISO Request" {
  let meta = @pgn.pgn_meta_iso_request()
  let payload = @frame.hex_to_bytes("14f001")
  let fields = decode_payload(meta, payload)
  assert_eq(raw_of(field_value(fields, "PGN requested")), 126996UL)
  // Round-trip.
  let r = @registry.Registry::new()
  let encoded = r.encode_fields(meta, [
    ("PGN requested", @codec.Unsigned(126996UL)),
  ])
  assert_eq(@frame.bytes_to_hex(encoded), "14f001")
  // Truncation.
  let mut truncated = false
  try {
    let _ignored = decode_payload(meta, @frame.hex_to_bytes("14f0"))
  } catch {
    @protocol.TruncatedField(pgn=59904, ..) => truncated = true
    _ => ()
  }
  assert_true(truncated)
}

///|
/// T09: 60928 ISO Address Claim NAME bit field round-trip.
test "PGN-60928 ISO Address Claim" {
  let meta = @pgn.pgn_meta_iso_address_claim()
  let payload = @frame.hex_to_bytes("64403f170a8278c1")
  let fields = decode_payload(meta, payload)
  assert_eq(raw_of(field_value(fields, "Unique Number")), 2048100UL)
  assert_eq(raw_of(field_value(fields, "Manufacturer Code")), 185UL)
  assert_eq(raw_of(field_value(fields, "Device Function")), 130UL)
  assert_eq(raw_of(field_value(fields, "Device Class")), 60UL)
  assert_eq(raw_of(field_value(fields, "Industry Group")), 4UL)
  // Round-trip through encode.
  let r = @registry.Registry::new()
  let encoded = r.encode_fields(meta, [
    ("Unique Number", @codec.Unsigned(2048100UL)),
    ("Manufacturer Code", @codec.Unsigned(185UL)),
    ("Device Instance Lower", @codec.Unsigned(2UL)),
    ("Device Instance Upper", @codec.Unsigned(1UL)),
    ("Device Function", @codec.Unsigned(130UL)),
    ("Spare", @codec.Bits(0UL)),
    ("Device Class", @codec.Unsigned(60UL)),
    ("System Instance", @codec.Unsigned(1UL)),
    ("Industry Group", @codec.Unsigned(4UL)),
    ("Arbitrary address capable", @codec.Bits(1UL)),
  ])
  assert_eq(@frame.bytes_to_hex(encoded), "64403f170a8278c1")
  // Min/max boundary: all-zero NAME and all-ones NAME decode.
  let min_fields = decode_payload(meta, Bytes::makei(8, fn(_i) { b'\x00' }))
  assert_eq(raw_of(field_value(min_fields, "Unique Number")), 0UL)
  let max_fields = decode_payload(meta, Bytes::makei(8, fn(_i) { b'\xff' }))
  assert_eq(raw_of(field_value(max_fields, "Manufacturer Code")), 0x7FFUL)
}

///|
/// T09: 126992 System Time with date/time scaling and NA.
test "PGN-126992 System Time" {
  let meta = @pgn.pgn_meta_system_time()
  let fields = decode_payload(meta, @frame.hex_to_bytes("ff00384a00ccbf19"))
  assert_eq(raw_of(field_value(fields, "SID")), 255UL)
  assert_eq(raw_of(field_value(fields, "Date")), 19000UL)
  assert_eq(raw_of(field_value(fields, "Time")), 432000000UL)
  match field_value(fields, "Time").physical() {
    Some(v) => assert_eq(v, 43200.0)
    None => fail("Time physical missing")
  }
  // NA: date 0xFFFF and time 0xFFFFFFFF are NotAvailable per definition.
  let na_fields = decode_payload(meta, @frame.hex_to_bytes("0100ffffffffffff"))
  assert_eq(field_value(na_fields, "Date"), @codec.NotAvailable)
  assert_eq(field_value(na_fields, "Time"), @codec.NotAvailable)
  // Round-trip.
  let r = @registry.Registry::new()
  let encoded = r.encode_fields(meta, [
    ("SID", @codec.Unsigned(255UL)),
    ("Source", @codec.Unsigned(0UL)),
    ("Reserved (bits 12..16)", @codec.Bits(0UL)),
    ("Date", @codec.Unsigned(19000UL)),
    ("Time", @codec.Unsigned(432000000UL)),
  ])
  assert_eq(@frame.bytes_to_hex(encoded), "ff00384a00ccbf19")
}

///|
/// T09: 126993 Heartbeat.
test "PGN-126993 Heartbeat" {
  let meta = @pgn.pgn_meta_heartbeat()
  let fields = decode_payload(meta, @frame.hex_to_bytes("e8032a3100000000"))
  assert_eq(raw_of(field_value(fields, "Data transmit offset")), 1000UL)
  match field_value(fields, "Data transmit offset").physical() {
    Some(v) => assert_eq(v, 1.0)
    None => fail("offset physical missing")
  }
  assert_eq(raw_of(field_value(fields, "Sequence Counter")), 42UL)
  match field_value(fields, "Controller 1 State") {
    @codec.Bits(raw) => assert_eq(raw, 1UL)
    _ => fail("expected Bits")
  }
  // Round-trip.
  let r = @registry.Registry::new()
  let encoded = r.encode_fields(meta, [
    ("Data transmit offset", @codec.Unsigned(1000UL)),
    ("Sequence Counter", @codec.Unsigned(42UL)),
    ("Controller 1 State", @codec.Bits(1UL)),
    ("Controller 2 State", @codec.Bits(0UL)),
    ("Equipment Status", @codec.Bits(3UL)),
    ("Reserved (bits 30..64)", @codec.Bits(0UL)),
  ])
  assert_eq(@frame.bytes_to_hex(encoded), "e8032a3100000000")
  // Truncation: 4 bytes cannot hold the 34-bit reserved tail read.
  let mut truncated = false
  try {
    let _ignored = decode_payload(meta, @frame.hex_to_bytes("e8032a31"))
  } catch {
    @protocol.TruncatedField(..) => truncated = true
    _ => ()
  }
  assert_true(truncated)
}

///|
/// T10: 127250 Vessel Heading — normal, signed fields, lookup, NA,
/// min/max, truncation, round-trip, reference vector.
test "PGN-127250 Vessel Heading" {
  let meta = @pgn.pgn_meta_vessel_heading()
  let fields = decode_payload(meta, @frame.hex_to_bytes("4211116400ceff01"))
  assert_eq(raw_of(field_value(fields, "SID")), 66UL)
  assert_eq(raw_of(field_value(fields, "Heading")), 4369UL)
  match field_value(fields, "Heading").physical() {
    Some(v) => assert_true(v > 0.43689 && v < 0.43691)
    None => fail("Heading physical missing")
  }
  assert_eq(raw_of(field_value(fields, "Deviation")), 100UL)
  assert_eq(raw_of(field_value(fields, "Variation")), 0xFFFFFFFFFFFFFFCEUL)
  match field_value(fields, "Reference") {
    @codec.Lookup(1UL, Some("Magnetic")) => ()
    _ => fail("expected Magnetic reference")
  }
  // NA patterns.
  let na = decode_payload(meta, @frame.hex_to_bytes("ffffffff7fff7f01"))
  assert_eq(field_value(na, "Heading"), @codec.NotAvailable)
  assert_eq(field_value(na, "Deviation"), @codec.NotAvailable)
  assert_eq(field_value(na, "Variation"), @codec.NotAvailable)
  // Signed round-trip: deviation -0.005 rad via encode.
  let r = @registry.Registry::new()
  let encoded = r.encode_fields(meta, [
    ("SID", @codec.Unsigned(66UL)),
    ("Heading", @codec.Unsigned(4369UL)),
    ("Deviation", @codec.Signed(100L)),
    ("Variation", @codec.Signed(-50L)),
    ("Reference", @codec.Lookup(1UL, None)),
    ("Reserved (bits 58..64)", @codec.Bits(0UL)),
  ])
  assert_eq(@frame.bytes_to_hex(encoded), "4211116400ceff01")
  // Truncation: 5-byte payload cannot fit Variation (bits 40..56).
  let mut truncated = false
  try {
    let _ignored = decode_payload(meta, @frame.hex_to_bytes("4211116400"))
  } catch {
    @protocol.TruncatedField(pgn=127250, ..) => truncated = true
    _ => ()
  }
  assert_true(truncated)
}

///|
/// T10: 128267 Water Depth — 32-bit scaled depth, signed offset.
test "PGN-128267 Water Depth" {
  let meta = @pgn.pgn_meta_water_depth()
  let fields = decode_payload(meta, @frame.hex_to_bytes("0c40e201001efb0a"))
  assert_eq(raw_of(field_value(fields, "Depth")), 123456UL)
  match field_value(fields, "Depth").physical() {
    Some(v) => assert_eq(v, 1234.56)
    None => fail("Depth physical missing")
  }
  assert_eq(raw_of(field_value(fields, "Offset")), 0xFFFFFFFFFFFFFB1EUL)
  match field_value(fields, "Offset").physical() {
    Some(v) => assert_eq(v, -1.25)
    None => fail("Offset physical missing")
  }
  assert_eq(raw_of(field_value(fields, "Range")), 10UL)
  // Max depth and NA.
  let max_fields = decode_payload(meta, @frame.hex_to_bytes("0cffffffff000000"))
  assert_eq(field_value(max_fields, "Depth"), @codec.NotAvailable)
  // Round-trip.
  let r = @registry.Registry::new()
  let encoded = r.encode_fields(meta, [
    ("SID", @codec.Unsigned(12UL)),
    ("Depth", @codec.Unsigned(123456UL)),
    ("Offset", @codec.Signed(-1250L)),
    ("Range", @codec.Unsigned(10UL)),
  ])
  assert_eq(@frame.bytes_to_hex(encoded), "0c40e201001efb0a")
}

///|
/// T10: 129025 Position, Rapid Update — signed 1e-7 degrees, NA, round-trip.
test "PGN-129025 Position Rapid" {
  let meta = @pgn.pgn_meta_position_rapid()
  let fields = decode_payload(meta, @frame.hex_to_bytes("40a13120fa0cfbf9"))
  match field_value(fields, "Latitude") {
    @codec.SignedPhysical(540123456L, res, _) => assert_eq(res, 0.0000001)
    _ => fail("expected SignedPhysical latitude")
  }
  match field_value(fields, "Latitude").physical() {
    Some(v) => assert_true(v > 54.0123455 && v < 54.0123457)
    None => fail("latitude physical missing")
  }
  match field_value(fields, "Longitude").physical() {
    Some(v) => assert_true(v > -10.0987655 && v < -10.0987653)
    None => fail("longitude physical missing")
  }
  // NA: 0x7FFFFFFF for both positions.
  let na = decode_payload(meta, @frame.hex_to_bytes("ffffff7fffffff7f"))
  assert_eq(field_value(na, "Latitude"), @codec.NotAvailable)
  assert_eq(field_value(na, "Longitude"), @codec.NotAvailable)
  // Round-trip.
  let r = @registry.Registry::new()
  let encoded = r.encode_fields(meta, [
    ("Latitude", @codec.Signed(540123456L)),
    ("Longitude", @codec.Signed(-100987654L)),
  ])
  assert_eq(@frame.bytes_to_hex(encoded), "40a13120fa0cfbf9")
  // Truncation.
  let mut truncated = false
  try {
    let _ignored = decode_payload(meta, @frame.hex_to_bytes("40a13120fa"))
  } catch {
    @protocol.TruncatedField(pgn=129025, ..) => truncated = true
    _ => ()
  }
  assert_true(truncated)
}

///|
/// T10: 129026 COG & SOG, Rapid Update.
test "PGN-129026 COG SOG Rapid" {
  let meta = @pgn.pgn_meta_cog_sog_rapid()
  let fields = decode_payload(meta, @frame.hex_to_bytes("4d003930fa000000"))
  assert_eq(raw_of(field_value(fields, "SID")), 77UL)
  match field_value(fields, "COG Reference") {
    @codec.Lookup(0UL, Some("True")) => ()
    _ => fail("expected True reference")
  }
  assert_eq(raw_of(field_value(fields, "COG")), 12345UL)
  assert_eq(raw_of(field_value(fields, "SOG")), 250UL)
  match field_value(fields, "SOG").physical() {
    Some(v) => assert_eq(v, 2.5)
    None => fail("SOG physical missing")
  }
  // NA.
  let na = decode_payload(meta, @frame.hex_to_bytes("4d00ffffffff0000"))
  assert_eq(field_value(na, "COG"), @codec.NotAvailable)
  assert_eq(field_value(na, "SOG"), @codec.NotAvailable)
  // Round-trip.
  let r = @registry.Registry::new()
  let encoded = r.encode_fields(meta, [
    ("SID", @codec.Unsigned(77UL)),
    ("COG Reference", @codec.Lookup(0UL, None)),
    ("Reserved (bits 10..16)", @codec.Bits(0UL)),
    ("COG", @codec.Unsigned(12345UL)),
    ("SOG", @codec.Unsigned(250UL)),
    ("Reserved (bits 48..64)", @codec.Bits(0UL)),
  ])
  assert_eq(@frame.bytes_to_hex(encoded), "4d003930fa000000")
}

///|
/// T10: 130306 Wind Data — speed, angle, 3-bit reference lookup.
test "PGN-130306 Wind Data" {
  let meta = @pgn.pgn_meta_wind_data()
  let fields = decode_payload(meta, @frame.hex_to_bytes("c852035c3d020000"))
  assert_eq(raw_of(field_value(fields, "SID")), 200UL)
  assert_eq(raw_of(field_value(fields, "Wind Speed")), 850UL)
  match field_value(fields, "Wind Speed").physical() {
    Some(v) => assert_eq(v, 8.5)
    None => fail("speed physical missing")
  }
  assert_eq(raw_of(field_value(fields, "Wind Angle")), 15708UL)
  match field_value(fields, "Reference") {
    @codec.Lookup(2UL, Some("Apparent (Relative to vessel centerline)")) => ()
    _ => fail("unexpected reference")
  }
  // NA.
  let na = decode_payload(meta, @frame.hex_to_bytes("c8ffffffff000000"))
  assert_eq(field_value(na, "Wind Speed"), @codec.NotAvailable)
  assert_eq(field_value(na, "Wind Angle"), @codec.NotAvailable)
  // Round-trip.
  let r = @registry.Registry::new()
  let encoded = r.encode_fields(meta, [
    ("SID", @codec.Unsigned(200UL)),
    ("Wind Speed", @codec.Unsigned(850UL)),
    ("Wind Angle", @codec.Unsigned(15708UL)),
    ("Reference", @codec.Lookup(2UL, None)),
    ("Reserved (bits 43..64)", @codec.Bits(0UL)),
  ])
  assert_eq(@frame.bytes_to_hex(encoded), "c852035c3d020000")
}

///|
/// T11: 126996 Product Information — 134-byte payload with text fields.
test "PGN-126996 Product Information" {
  let meta = @pgn.pgn_meta_product_info()
  assert_eq(meta.length, 134)
  let hex = "340878036d6f6f6e6e326b2d64656d6f000000000000000000000000000000000000000076302e312e30000000000000000000000000000000000000000000000000000073696d2d756e69742d3100000000000000000000000000000000000000000000534e3030303432000000000000000000000000000000000000000000000000000001"
  let fields = decode_payload(meta, @frame.hex_to_bytes(hex))
  assert_eq(raw_of(field_value(fields, "NMEA 2000 Version")), 2100UL)
  match field_value(fields, "NMEA 2000 Version").physical() {
    Some(v) => assert_eq(v, 2.1)
    None => fail("version physical missing")
  }
  assert_eq(raw_of(field_value(fields, "Product Code")), 888UL)
  match field_value(fields, "Model ID") {
    @codec.Text("moonn2k-demo") => ()
    _ => fail("unexpected model id")
  }
  match field_value(fields, "Software Version Code") {
    @codec.Text("v0.1.0") => ()
    _ => fail("unexpected sw code")
  }
  match field_value(fields, "Model Serial Code") {
    @codec.Text("SN00042") => ()
    _ => fail("unexpected serial")
  }
  // Round-trip through encode.
  let r = @registry.Registry::new()
  let encoded = r.encode_fields(meta, [
    ("NMEA 2000 Version", @codec.Unsigned(2100UL)),
    ("Product Code", @codec.Unsigned(888UL)),
    ("Model ID", @codec.Text("moonn2k-demo")),
    ("Software Version Code", @codec.Text("v0.1.0")),
    ("Model Version", @codec.Text("sim-unit-1")),
    ("Model Serial Code", @codec.Text("SN00042")),
    ("Certification Level", @codec.Unsigned(0UL)),
    ("Load Equivalency", @codec.Unsigned(1UL)),
  ])
  assert_eq(@frame.bytes_to_hex(encoded), hex)
  // The 134-byte reference payload itself must decode; a 100-byte cut
  // must fail with TruncatedField.
  let mut truncated = false
  try {
    let _ignored = decode_payload(
      meta,
      @frame.hex_to_bytes(hex[:200].to_owned()),
    )
  } catch {
    @protocol.TruncatedField(..) => truncated = true
    _ => ()
  }
  assert_true(truncated)
}

///|
/// @registry.Registry contains exactly the P0 support set.
test "PGN default registry support matrix" {
  let r = @pgn.default_registry()
  let supported = r.supported()
  assert_eq(supported.length(), 10)
  assert_eq(supported[0].pgn, 59904)
  assert_eq(supported[1].pgn, 60928)
  assert_eq(supported[4].pgn, 126996)
  assert_eq(supported[4].transport, @registry.FastPacket)
  assert_eq(supported[9].pgn, 130306)
}

///|
/// T11: Product Information end-to-end — typed encode, Fast Packet
/// segmentation, shuffled ingest, reassembly and typed decode.
test "PGN-126996 fast packet end-to-end" {
  let meta = @pgn.pgn_meta_product_info()
  let r = @pgn.default_registry()
  let fields : Array[(String, @codec.FieldValue)] = [
    ("NMEA 2000 Version", @codec.Unsigned(2100UL)),
    ("Product Code", @codec.Unsigned(888UL)),
    ("Model ID", @codec.Text("moonn2k-demo")),
    ("Software Version Code", @codec.Text("v0.1.0")),
    ("Model Version", @codec.Text("sim-unit-1")),
    ("Model Serial Code", @codec.Text("SN00042")),
    ("Certification Level", @codec.Unsigned(0UL)),
    ("Load Equivalency", @codec.Unsigned(1UL)),
  ]
  // 1. Typed encode into a complete message.
  let msg = @pgn.encode_pgn_message(
    r,
    meta,
    fields,
    source=36,
    priority=Some(6),
  )
  assert_eq(msg.transport, @message.FastPacket)
  assert_eq(msg.payload.length(), 134)
  // 2. Segment into CAN frames.
  let frames = @fast_packet.segment(msg.id, msg.payload, 4)
  assert_eq(frames.length(), 20)
  // 3. Shuffled ingest: every later frame arrives before the first frame.
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let mut completed : @message.Message? = None
  let mut now = 0
  for i in 1..<20 {
    now = now + 5
    match re.ingest(frames[i], now) {
      @fast_packet.Accepted(_) => ()
      _ => fail("unexpected event while staging")
    }
  }
  now = now + 5
  match re.ingest(frames[0], now) {
    @fast_packet.Completed(m) => completed = Some(m)
    _ => fail("expected completion on first frame")
  }
  // 4. Typed decode of the reassembled payload.
  match completed {
    Some(m) => {
      assert_eq(
        @frame.bytes_to_hex(m.payload),
        @frame.bytes_to_hex(msg.payload),
      )
      match @pgn.decode_pgn_message(r, m) {
        Known(pgn=126996, name=_, fields~) => {
          match field_value(fields, "Model ID") {
            @codec.Text("moonn2k-demo") => ()
            _ => fail("model id mismatch after round-trip")
          }
          match field_value(fields, "Model Serial Code") {
            @codec.Text("SN00042") => ()
            _ => fail("serial mismatch after round-trip")
          }
        }
        Known(pgn=_, name=_, fields=_) => fail("wrong PGN decoded")
        Unknown(_) => fail("product info must be known")
      }
    }
    None => fail("end-to-end transfer did not complete")
  }
}
