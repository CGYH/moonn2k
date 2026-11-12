// Hex and frame tests (plan section 8.4, HEX-001..HEX-008).

///|
fn test_id() -> @identifier.CanId raise @protocol.ProtocolError {
  @identifier.CanId::from_raw(0x19F80196U)
}

///|
/// HEX-001: empty payload round-trips through both directions.
test "HEX-001 empty payload" {
  let empty = @frame.hex_to_bytes("")
  assert_eq(@frame.bytes_to_hex(empty), "")
  let frame = @frame.CanFrame::from_hex(test_id(), "")
  assert_eq(frame.data.length(), 0)
  assert_eq(frame.to_hex(), "")
}

///|
/// HEX-002: full 8-byte payload is accepted.
test "HEX-002 eight bytes accepted" {
  let frame = @frame.CanFrame::from_hex(test_id(), "0011223344556677")
  assert_eq(frame.data.length(), 8)
  assert_eq(frame.to_hex(), "0011223344556677")
}

///|
/// HEX-003: nine bytes are rejected with InvalidFrameLength.
test "HEX-003 nine bytes rejected" {
  let mut got_length_error = false
  let mut reported_length = 0
  try {
    let _ignored = @frame.CanFrame::from_hex(test_id(), "001122334455667788")
  } catch {
    @protocol.InvalidFrameLength(length~, ..) => {
      got_length_error = true
      reported_length = length
    }
    _ => ()
  }
  assert_true(got_length_error)
  assert_eq(reported_length, 9)
}

///|
/// HEX-004: odd digit count is rejected with InvalidHex.
test "HEX-004 odd length rejected" {
  let mut got_hex_error = false
  try {
    let _ignored = @frame.hex_to_bytes("001")
  } catch {
    @protocol.InvalidHex(..) => got_hex_error = true
    _ => ()
  }
  assert_true(got_hex_error)
}

///|
/// HEX-005: non-hex characters are rejected with InvalidHex.
test "HEX-005 invalid character rejected" {
  for bad in ["00zz", "0x11", "ab,cd", "ab-cd", "ab;cd", "ab\ncd"] {
    let mut rejected = false
    try {
      let _ignored = @frame.hex_to_bytes(bad)
    } catch {
      @protocol.InvalidHex(..) => rejected = true
      _ => ()
    }
    assert_true(rejected)
  }
}

///|
/// HEX-006: any input case; output is always canonical lowercase.
test "HEX-006 case normalization" {
  assert_eq(@frame.bytes_to_hex(@frame.hex_to_bytes("AaBbCcDd")), "aabbccdd")
  let frame = @frame.CanFrame::from_hex(test_id(), "AaBbCcDd")
  assert_eq(frame.to_hex(), "aabbccdd")
}

///|
/// HEX-007: spaces and colons are accepted as separators on input.
test "HEX-007 allowed separators" {
  assert_eq(@frame.bytes_to_hex(@frame.hex_to_bytes("00 11:22")), "001122")
  assert_eq(@frame.bytes_to_hex(@frame.hex_to_bytes(":aa:bb:")), "aabb")
}

///|
/// HEX-008: other separators are rejected on input (comma, dash, semicolon).
test "HEX-008 disallowed separators rejected" {
  let mut rejected = 0
  for bad in ["00,11", "00-11", "00;11", "00_11"] {
    try {
      let _ignored = @frame.hex_to_bytes(bad)
    } catch {
      @protocol.InvalidHex(..) => rejected = rejected + 1
      _ => ()
    }
  }
  assert_eq(rejected, 4)
}

///|
/// Round-trip property over fixed byte patterns: hex out == canonical in.
test "HEX round-trip over patterns" {
  let patterns = [
    "00", "ff", "0001020304050607", "deadbeef", "807f0100ff7f0001",
  ]
  for p in patterns {
    let frame = @frame.CanFrame::from_hex(test_id(), p)
    assert_eq(frame.to_hex(), p)
  }
}
