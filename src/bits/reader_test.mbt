// BitReader tests (plan section 8.4, BIT-001..BIT-008).

///|
/// BIT-001: single-bit reads across byte boundaries.
test "BIT-001 single bit read" {
  // 0b10100101 = 0xA5, LSB-first: bits are 1,0,1,0,0,1,0,1.
  let reader = @bits.BitReader::new(b"\xa5\xff")
  assert_eq(reader.read_flag(offset=0), true)
  assert_eq(reader.read_flag(offset=1), false)
  assert_eq(reader.read_flag(offset=2), true)
  assert_eq(reader.read_flag(offset=3), false)
  assert_eq(reader.read_flag(offset=5), true)
  assert_eq(reader.read_flag(offset=8), true)
  assert_eq(reader.read_uint(offset=7, bits=1), 1UL)
  assert_eq(reader.read_uint(offset=8, bits=1), 1UL)
}

///|
/// BIT-002: byte-aligned 8-bit reads.
test "BIT-002 8-bit read" {
  let reader = @bits.BitReader::new(b"\x34\x00")
  assert_eq(reader.read_uint(offset=0, bits=8), 0x34UL)
  assert_eq(reader.read_uint(offset=8, bits=8), 0x00UL)
  assert_eq(reader.read_uint(offset=0, bits=0), 0UL)
}

///|
/// BIT-003: 16-bit read spanning two bytes behaves little-endian.
test "BIT-003 16-bit cross-byte read" {
  let reader = @bits.BitReader::new(b"\x78\x56\x00\x00")
  assert_eq(reader.read_uint(offset=0, bits=16), 0x5678UL)
  // Unaligned 16-bit window: result bit i = buffer bit (4+i).
  // Derived from 0x78=...1000 1111(2)... LSB-first splicing; the signed and
  // round-trip tests below independently verify the same semantics.
  assert_eq(reader.read_uint(offset=4, bits=16), 0x567UL)
}

///|
/// BIT-004: non-byte-aligned read.
test "BIT-004 unaligned read" {
  // 0x00 0xFF: bits 4..11 = 0b11110000 read LSB-first = 0x0F0? Compute:
  // bit i of result = bit (4+i) of buffer. bits 4..7 = 0000, bits 8..11 = 1111
  // value bits: 0,0,0,0,1,1,1,1 -> 0b11110000 = 0xF0.
  let reader = @bits.BitReader::new(b"\x00\xff\x00\x00")
  assert_eq(reader.read_uint(offset=4, bits=8), 0xF0UL)
}

///|
/// BIT-005: 32-bit read.
test "BIT-005 32-bit read" {
  let reader = @bits.BitReader::new(b"\x78\x56\x34\x12")
  assert_eq(reader.read_uint(offset=0, bits=32), 0x12345678UL)
  let reader2 = @bits.BitReader::new(b"\x00\x00\x00\x80")
  assert_eq(reader2.read_uint(offset=0, bits=32), 0x80000000UL)
}

///|
/// BIT-006: 64-bit read.
test "BIT-006 64-bit read" {
  let reader = @bits.BitReader::new(b"\x78\x56\x34\x12\xef\xcd\xab\x90")
  assert_eq(reader.read_uint(offset=0, bits=64), 0x90ABCDEF12345678UL)
}

///|
/// BIT-007: signed reads of negative values (two's complement).
test "BIT-007 signed negative read" {
  // 0xFF as 8-bit signed = -1.
  let reader = @bits.BitReader::new(b"\xff\xff\xff\xff\xff\xff\xff\xff")
  assert_eq(reader.read_int(offset=0, bits=8), -1L)
  assert_eq(reader.read_int(offset=0, bits=16), -1L)
  assert_eq(reader.read_int(offset=0, bits=64), -1L)
  // 0x80 as 8-bit signed = -128.
  let reader2 = @bits.BitReader::new(b"\x80\x00\x00\x00\x00\x00\x00\x00")
  assert_eq(reader2.read_int(offset=0, bits=8), -128L)
  // 0xFFFF as 16-bit signed = -1; 0x8000 = -32768.
  let reader3 = @bits.BitReader::new(b"\xff\xff\x00\x80\x00\x00\x00\x00")
  assert_eq(reader3.read_int(offset=0, bits=16), -1L)
  assert_eq(reader3.read_int(offset=16, bits=16), -32768L)
  // Positive values stay positive.
  let reader4 = @bits.BitReader::new(b"\x7f\x00\x00\x00\x00\x00\x00\x00")
  assert_eq(reader4.read_int(offset=0, bits=8), 127L)
}

///|
/// BIT-008: out-of-bounds reads fail with offset/bits/available context.
test "BIT-008 out-of-bounds read" {
  let reader = @bits.BitReader::new(b"\x00\x00")
  assert_eq(reader.bit_length(), 16)
  let mut error_seen = false
  let mut e_offset = 0
  let mut e_bits = 0
  let mut e_available = 0
  try {
    let _ignored = reader.read_uint(offset=8, bits=16)
  } catch {
    @protocol.BitsOutOfBounds(offset~, bits~, available~) => {
      error_seen = true
      e_offset = offset
      e_bits = bits
      e_available = available
    }
    _ => ()
  }
  assert_true(error_seen)
  assert_eq(e_offset, 8)
  assert_eq(e_bits, 16)
  assert_eq(e_available, 16)
  // Negative offset and negative width are also rejected.
  let mut rejected = 0
  try {
    let _ignored = reader.read_uint(offset=-1, bits=4)
  } catch {
    @protocol.BitsOutOfBounds(..) => rejected = rejected + 1
    _ => ()
  }
  try {
    let _ignored = reader.read_uint(offset=0, bits=-4)
  } catch {
    @protocol.BitsOutOfBounds(..) => rejected = rejected + 1
    _ => ()
  }
  assert_eq(rejected, 2)
}
