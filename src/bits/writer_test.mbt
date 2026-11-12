// BitWriter tests (plan section 8.4, BIT-009..BIT-010).

///|
/// Low-`bits`-bit mask as a UInt64 (all ones for 64).
fn mask_for(bits : Int32) -> UInt64 {
  if bits >= 64 {
    0xFFFFFFFFFFFFFFFFUL
  } else {
    (1UL << bits) - 1UL
  }
}

///|
/// BIT-009: writing one field does not disturb neighbouring bits.
test "BIT-009 write preserves neighbouring bits" {
  let writer = @bits.BitWriter::new(4)
  // Fill buffer with 0xAA..., then patch a 4-bit window in the middle.
  writer.write_uint(offset=0, bits=32, 0xAAAAAAAAUL)
  writer.write_uint(offset=12, bits=4, 0x5UL)
  let reader = @bits.BitReader::new(writer.to_bytes())
  assert_eq(reader.read_uint(offset=0, bits=12), 0xAAAUL)
  assert_eq(reader.read_uint(offset=12, bits=4), 0x5UL)
  assert_eq(reader.read_uint(offset=16, bits=16), 0xAAAAUL)
  // Adjacent single-bit writes flip exactly one bit each.
  let writer2 = @bits.BitWriter::new(1)
  writer2.write_uint(offset=0, bits=1, 1UL)
  writer2.write_uint(offset=1, bits=1, 0UL)
  writer2.write_uint(offset=2, bits=1, 1UL)
  let reader2 = @bits.BitReader::new(writer2.to_bytes())
  assert_eq(reader2.read_uint(offset=0, bits=3), 0b101UL)
}

///|
/// BIT-010: deterministic pseudo-random write/read round-trips.
test "BIT-010 random write/read round-trip" {
  // Fixed-seed LCG keeps the test deterministic (no real randomness).
  let mut seed : UInt64 = 0x2545F4914F6CDD1DUL
  for _trial in 0..<50 {
    let writer = @bits.BitWriter::new(8)
    let mut offset = 0
    while offset < 64 {
      seed = seed * 6364136223846793005UL + 1442695040888963407UL
      let width_raw = (seed >> 33).to_int() % 16 + 1
      seed = seed * 6364136223846793005UL + 1442695040888963407UL
      let width = if offset + width_raw > 64 { 64 - offset } else { width_raw }
      let value = seed
      writer.write_uint(offset~, bits=width, value)
      let reader = @bits.BitReader::new(writer.to_bytes())
      assert_eq(
        reader.read_uint(offset~, bits=width),
        value.land(mask_for(width)),
      )
      offset = offset + width
    }
  }
}

///|
/// Signed write/read round-trip including negative values.
test "BIT signed write/read round-trip" {
  let cases : Array[(Int32, Int64)] = [
    (8, -1L),
    (8, -128L),
    (8, 127L),
    (16, -32768L),
    (16, 32767L),
    (32, -123456789L),
    (64, -9007199254740993L),
    (64, 9007199254740993L),
    (12, -2048L),
    (12, 2047L),
  ]
  for case in cases {
    let writer = @bits.BitWriter::new(8)
    writer.write_int(offset=0, bits=case.0, case.1)
    let reader = @bits.BitReader::new(writer.to_bytes())
    assert_eq(reader.read_int(offset=0, bits=case.0), case.1)
  }
}

///|
/// Writer rejects out-of-bounds windows and invalid sizes.
test "BIT writer bounds" {
  let writer = @bits.BitWriter::new(2)
  let mut rejected = 0
  writer.write_uint(offset=9, bits=16, 0UL) catch {
    @protocol.BitsOutOfBounds(..) => rejected = rejected + 1
    _ => ()
  }
  writer.write_uint(offset=0, bits=32, 0UL) catch {
    @protocol.BitsOutOfBounds(..) => rejected = rejected + 1
    _ => ()
  }
  assert_eq(rejected, 2)
  let mut size_rejected = false
  try {
    let _ignored = @bits.BitWriter::new(0)
  } catch {
    @protocol.InvalidFrameLength(..) => size_rejected = true
    _ => ()
  }
  assert_true(size_rejected)
}
