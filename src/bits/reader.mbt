// Bounded bit-level reader over a byte buffer (plan section 7.3).
//
// Bit order: NMEA 2000 / J1939 use Intel (LSB-first) bit numbering.
// `read_uint(offset~, bits~)` assembles the value so that bit `i` of the
// result equals bit `offset+i` of the buffer. Byte-aligned reads therefore
// behave as little-endian integers.
//
// All arithmetic is integer-only; floating point is never involved.

///|
/// A reader over a fixed byte buffer.
pub struct BitReader {
  /// The buffer this reader is bounded by.
  data : Bytes
}

///|
/// Construct a reader over `data`.
pub fn BitReader::new(data : Bytes) -> BitReader {
  { data, }
}

///|
/// Total number of bits available in the underlying buffer.
pub fn BitReader::bit_length(self : BitReader) -> Int32 {
  self.data.length() * 8
}

///|
/// Validate an access window.
fn BitReader::check_range(
  self : BitReader,
  offset : Int32,
  bits : Int32,
) -> Unit raise @protocol.ProtocolError {
  if bits < 0 {
    raise @protocol.BitsOutOfBounds(offset~, bits~, available=self.bit_length())
  }
  if offset < 0 || offset + bits > self.bit_length() {
    raise @protocol.BitsOutOfBounds(offset~, bits~, available=self.bit_length())
  }
}

///|
/// Read `bits` bits (1..64) starting at bit `offset` as an unsigned value.
///
/// Errors with `BitsOutOfBounds` (carrying offset/bits/available) when the
/// window exceeds the buffer.
pub fn BitReader::read_uint(
  self : BitReader,
  offset~ : Int32,
  bits~ : Int32,
) -> UInt64 raise @protocol.ProtocolError {
  self.check_range(offset, bits)
  let mut value : UInt64 = 0UL
  for i in 0..<bits {
    let bit_index = offset + i
    let byte = self.data.at(bit_index >> 3).to_int()
    if ((byte >> (bit_index & 7)) & 1) == 1 {
      value = value.lor(1UL << i)
    }
  }
  value
}

///|
/// Read `bits` bits (1..64) starting at bit `offset` as a two's-complement
/// signed value.
pub fn BitReader::read_int(
  self : BitReader,
  offset~ : Int32,
  bits~ : Int32,
) -> Int64 raise @protocol.ProtocolError {
  let u = self.read_uint(offset~, bits~)
  if bits >= 64 {
    return u.reinterpret_as_int64()
  }
  let sign_bit = 1UL << (bits - 1)
  if u.land(sign_bit) != 0UL {
    // Sign-extend: set every bit at or above `bits`, keep the low bits.
    let ext_mask = ((1UL << bits) - 1UL).lnot()
    u.lor(ext_mask).reinterpret_as_int64()
  } else {
    u.reinterpret_as_int64()
  }
}

///|
/// Read one bit as a boolean (BIT-001 convenience form).
pub fn BitReader::read_flag(
  self : BitReader,
  offset~ : Int32,
) -> Bool raise @protocol.ProtocolError {
  self.read_uint(offset~, bits=1) == 1UL
}
