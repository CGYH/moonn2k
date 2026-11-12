// Bit-level writer over a mutable byte buffer (plan section 7.3).
//
// Mirrors BitReader semantics: LSB-first bit order, little-endian byte
// order for byte-aligned fields. Writes only touch the requested window;
// neighbouring bits are preserved (read-modify-write).

///|
/// A writer over a fixed-size byte buffer.
pub struct BitWriter {
  data : FixedArray[Byte]
}

///|
/// Construct a writer for `size` bytes (1..64). The buffer starts zeroed.
pub fn BitWriter::new(size : Int32) -> BitWriter raise @protocol.ProtocolError {
  if size < 1 || size > 64 {
    raise @protocol.InvalidFrameLength(
      length=size,
      reason="bit writer size must be 1..64 bytes",
    )
  }
  { data: FixedArray::make(size, b'\x00'), }
}

///|
/// Total number of bits available in the buffer.
pub fn BitWriter::bit_length(self : BitWriter) -> Int32 {
  self.data.length() * 8
}

///|
/// Snapshot the buffer contents.
pub fn BitWriter::to_bytes(self : BitWriter) -> Bytes {
  Bytes::makei(self.data.length(), fn(i) { self.data[i] })
}

///|
/// Validate an access window.
fn BitWriter::check_range(
  self : BitWriter,
  offset : Int32,
  bits : Int32,
) -> Unit raise @protocol.ProtocolError {
  if bits < 0 || offset < 0 || offset + bits > self.bit_length() {
    raise @protocol.BitsOutOfBounds(offset~, bits~, available=self.bit_length())
  }
}

///|
/// Write the low `bits` bits (0..64) of `value` at bit `offset`.
///
/// Only the requested window is modified; bits above the window in `value`
/// are ignored, and adjacent buffer bits are preserved. Zero-width writes
/// are accepted as no-ops.
pub fn BitWriter::write_uint(
  self : BitWriter,
  offset~ : Int32,
  bits~ : Int32,
  value : UInt64,
) -> Unit raise @protocol.ProtocolError {
  self.check_range(offset, bits)
  for i in 0..<bits {
    let bit_index = offset + i
    let byte_i = bit_index >> 3
    let bit_in_byte = bit_index & 7
    let mask = b'\x01'.shl(bit_in_byte)
    if (value >> i).land(1UL) == 1UL {
      self.data[byte_i] = self.data[byte_i].lor(mask)
    } else {
      self.data[byte_i] = self.data[byte_i].land(mask.lnot())
    }
  }
}

///|
/// Write `value` as a two's-complement signed value of `bits` bits
/// (1..64). The low `bits` bits of the representation are stored.
pub fn BitWriter::write_int(
  self : BitWriter,
  offset~ : Int32,
  bits~ : Int32,
  value : Int64,
) -> Unit raise @protocol.ProtocolError {
  self.write_uint(offset~, bits~, value.reinterpret_as_uint64())
}
