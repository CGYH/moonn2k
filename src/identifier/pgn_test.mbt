// Pgn model tests (plan section 5.2).

///|
/// Pgn is a plain value struct: equality is structural and unknown values
/// are legal (registry lookup failure is not a protocol error).
test "PGN-STRUCT value equality and unknown passthrough" {
  let known : @identifier.Pgn = {
    value: 129025,
    is_pdu1: false,
    destination: None,
  }
  let unknown : @identifier.Pgn = {
    value: 65280,
    is_pdu1: false,
    destination: None,
  }
  assert_eq(known, known)
  assert_false(known == unknown)
  assert_eq(unknown.value, 65280)
}

///|
/// Pgn covers the full 18-bit space (data page | PF | PS).
test "PGN-STRUCT value range boundary" {
  let max : @identifier.Pgn = {
    value: 0x1FFFF,
    is_pdu1: false,
    destination: None,
  }
  assert_eq(max.value, @identifier.MAX_PGN_VALUE)
}
