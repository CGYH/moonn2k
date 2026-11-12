// Fast Packet sender tests (plan section 8.4, FPS-001..FPS-010).

///|
/// Build a PDU2 identifier carrying the given PGN and source address.
fn id_for(
  pgn : Int32,
  source : Int32,
) -> @identifier.CanId raise @protocol.ProtocolError {
  let dp = pgn >> 16
  let pf = (pgn >> 8) & 0xFF
  let ps = pgn & 0xFF
  @identifier.CanId::make(
    priority=6,
    data_page=dp,
    pdu_format=pf,
    pdu_specific=ps,
    source~,
  )
}

///|
/// Deterministic payload pattern of `len` bytes.
fn pattern_payload(len : Int32) -> Bytes {
  Bytes::makei(len, fn(i) { (((i * 7 + 3) % 256) | 1).to_byte() })
}

///|
/// FPS-001: 8 bytes is rejected (single-frame territory).
test "FPS-001 eight bytes rejected" {
  let id = id_for(126996, 150)
  let mut rejected = false
  try {
    let _ignored = @fast_packet.segment(id, pattern_payload(8), 0)
  } catch {
    @protocol.InvalidFastPacketLength(declared=8, ..) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}

///|
/// FPS-002: 9 bytes -> 2 frames.
test "FPS-002 nine bytes two frames" {
  let id = id_for(126996, 150)
  let frames = @fast_packet.segment(id, pattern_payload(9), 3)
  assert_eq(frames.length(), 2)
}

///|
/// FPS-003: 13 bytes -> 2 frames (6 + 7, exact fit).
test "FPS-003 thirteen bytes two frames" {
  let id = id_for(126996, 150)
  let frames = @fast_packet.segment(id, pattern_payload(13), 0)
  assert_eq(frames.length(), 2)
  assert_eq(frames[1].data.at(1), pattern_payload(13).at(6))
}

///|
/// FPS-004: 14 bytes -> 3 frames.
test "FPS-004 fourteen bytes three frames" {
  let id = id_for(126996, 150)
  let frames = @fast_packet.segment(id, pattern_payload(14), 0)
  assert_eq(frames.length(), 3)
}

///|
/// FPS-005: 223 bytes -> 32 frames (the protocol maximum).
test "FPS-005 223 bytes 32 frames" {
  let id = id_for(126996, 150)
  let frames = @fast_packet.segment(id, pattern_payload(223), 7)
  assert_eq(frames.length(), 32)
  assert_eq(frames[31].data.at(0).to_int(), (7 << 5) | 31)
}

///|
/// FPS-006: 224 bytes is rejected.
test "FPS-006 224 bytes rejected" {
  let id = id_for(126996, 150)
  let mut rejected = false
  try {
    let _ignored = @fast_packet.segment(id, pattern_payload(224), 0)
  } catch {
    @protocol.PayloadTooLarge(length=224, limit=223) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}

///|
/// FPS-007: first frame header: seq<<5 | 0, declared length, 6 payload bytes.
test "FPS-007 first frame header" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(9)
  let frames = @fast_packet.segment(id, payload, 5)
  let first = frames[0].data
  assert_eq(first.length(), 8)
  assert_eq(first.at(0).to_int(), 5 << 5)
  assert_eq(first.at(1).to_int(), 9)
  for i in 0..<6 {
    assert_eq(first.at(2 + i), payload.at(i))
  }
}

///|
/// FPS-008: later frame headers: seq<<5 | counter, 7 payload bytes each.
test "FPS-008 later frame header" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(20)
  let frames = @fast_packet.segment(id, payload, 2)
  assert_eq(frames.length(), 3)
  for f in 1..<3 {
    assert_eq(frames[f].data.at(0).to_int(), (2 << 5) | f)
    for i in 0..<7 {
      let offset = 6 + (f - 1) * 7 + i
      if offset < 20 {
        assert_eq(frames[f].data.at(1 + i), payload.at(offset))
      }
    }
  }
}

///|
/// FPS-009: final frame is padded to 8 bytes with 0xFF (engineering
/// choice aligned with common implementations, not a standard mandate).
test "FPS-009 final frame padding" {
  let id = id_for(126996, 150)
  let frames = @fast_packet.segment(id, pattern_payload(9), 0)
  let last = frames[1].data
  assert_eq(last.length(), 8)
  for i in 4..<8 {
    assert_eq(last.at(i), b'\xff')
  }
}

///|
/// FPS-010: segment -> ordered reassemble reproduces the payload for every
/// legal length 9..223.
test "FPS-010 all legal lengths round-trip" {
  let id = id_for(126996, 150)
  for len in 9..<=223 {
    let payload = pattern_payload(len)
    let frames = @fast_packet.segment(id, payload, 1)
    assert_eq(frames.length(), @fast_packet.frame_count_for(len))
    let re = @fast_packet.FastPacketReassembler::new(
      @fast_packet.ReassemblyConfig::default(),
    )
    let mut completed : Bytes? = None
    let mut now = 0
    for frame in frames {
      now = now + 10
      match re.ingest(frame, now) {
        @fast_packet.Completed(m) => completed = Some(m.payload)
        _ => ()
      }
    }
    match completed {
      Some(p) => assert_eq(@frame.bytes_to_hex(p), @frame.bytes_to_hex(payload))
      None => fail("FPS-010: length \{len} never completed")
    }
  }
}
