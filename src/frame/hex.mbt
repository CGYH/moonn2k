// Hexadecimal text <-> bytes conversion (plan section 7.2).
//
// Input policy: hex digits in either case; single spaces and colons are
// ignored between digits. Any other character is rejected. The digit count
// must be even.
//
// Output policy: exactly one canonical form — lowercase, no separators, no
// prefix, "" for empty input — so snapshots stay stable (plan 7.2 建议).

///|
/// Convert one hex digit character to its 0..15 value.
fn hex_digit_value(ch : Char) -> Int32? {
  if ch >= '0' && ch <= '9' {
    Some(ch.to_int() - 0x30)
  } else if ch >= 'a' && ch <= 'f' {
    Some(ch.to_int() - 0x57)
  } else if ch >= 'A' && ch <= 'F' {
    Some(ch.to_int() - 0x37)
  } else {
    None
  }
}

///|
/// Parse hex text into bytes.
///
/// Rejects non-hex characters (other than the allowed space/colon
/// separators) and odd digit counts with `InvalidHex`; frame-level length
/// limits are enforced by `CanFrame::make`.
pub fn hex_to_bytes(input : String) -> Bytes raise @protocol.ProtocolError {
  let digits : Array[Int32] = []
  for ch in input {
    if ch == ' ' || ch == ':' {
      continue
    }
    match hex_digit_value(ch) {
      Some(v) => digits.push(v)
      None =>
        raise @protocol.InvalidHex(
          reason="non-hex character (allowed separators: space, colon)",
          input~,
        )
    }
  }
  if digits.length() % 2 != 0 {
    raise @protocol.InvalidHex(reason="hex input has odd length", input~)
  }
  Bytes::makei(digits.length() / 2, fn(i) {
    let hi = digits[i * 2]
    let lo = digits[i * 2 + 1]
    ((hi << 4) | lo).to_byte()
  })
}

///|
/// One nibble (0..15) to its lowercase hex character.
fn nib_char(nibble : Int32) -> Char {
  let code = if nibble < 10 { 0x30 + nibble } else { 0x57 + nibble }
  code.unsafe_to_char()
}

///|
/// Canonical hex rendering: lowercase, compact, no prefix.
pub fn bytes_to_hex(data : Bytes) -> String {
  let out = StringBuilder()
  for i in 0..<data.length() {
    let b = data.at(i).to_int()
    out.write_char(nib_char(b >> 4))
    out.write_char(nib_char(b & 0xF))
  }
  out.to_string()
}
