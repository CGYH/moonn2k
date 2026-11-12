// Generic field encoder: the inverse of Registry::decode, driven by the
// same metadata (plan section 7.6 encode(TypedMessage) -> Bytes).

///|
/// Encode typed field values into a fixed-length payload using the
/// metadata layout. Field names must match the metadata exactly;
/// NotAvailable writes the field's NA pattern (or all ones when the
/// definition has none). Text fields are NUL padded.
pub fn Registry::encode_fields(
  _self : Registry,
  meta : PgnMetadata,
  fields : Array[(String, @codec.FieldValue)],
) -> Bytes raise @protocol.ProtocolError {
  if meta.length <= 0 {
    raise @protocol.InvalidFieldValue(
      pgn=meta.pgn,
      field="<payload>",
      reason="encode requires a fixed payload length",
    )
  }
  let writer = @bits.BitWriter::new(meta.length)
  let by_name : Map[String, @codec.FieldValue] = Map([])
  for pair in fields {
    let _ = by_name.set(pair.0, pair.1)
  }
  for f in meta.fields {
    let value = match by_name.get(f.name) {
      Some(v) => v
      None =>
        raise @protocol.InvalidFieldValue(
          pgn=meta.pgn,
          field=f.name,
          reason="missing value for declared field",
        )
    }
    let bits = f.bit_length
    match value {
      @codec.NotAvailable =>
        match f.na_raw {
          Some(na) => writer.write_uint(offset=f.bit_offset, bits~, na)
          // All ones for the declared width.
          None =>
            writer.write_uint(offset=f.bit_offset, bits~, (1UL << bits) - 1UL)
        }
      @codec.Unsigned(raw) => writer.write_uint(offset=f.bit_offset, bits~, raw)
      @codec.Signed(v) => writer.write_int(offset=f.bit_offset, bits~, v)
      @codec.SignedPhysical(v, _, _) =>
        writer.write_int(offset=f.bit_offset, bits~, v)
      @codec.Physical(raw, _, _) =>
        writer.write_uint(offset=f.bit_offset, bits~, raw)
      @codec.Lookup(raw, _) =>
        writer.write_uint(offset=f.bit_offset, bits~, raw)
      @codec.Bits(raw) => writer.write_uint(offset=f.bit_offset, bits~, raw)
      @codec.Text(s) => encode_text(writer, meta.pgn, f, s)
      @codec.Bytes(b) => {
        let len = if bits < 0 { 0 } else { bits / 8 }
        if b.length() > len {
          raise @protocol.InvalidFieldValue(
            pgn=meta.pgn,
            field=f.name,
            reason="byte payload longer than declared field",
          )
        }
        for i in 0..<b.length() {
          writer.write_uint(
            offset=f.bit_offset + i * 8,
            bits=8,
            b.at(i).to_int().to_uint64(),
          )
        }
      }
    }
  }
  writer.to_bytes()
}

///|
/// Write a text field: printable ASCII bytes, then NUL padding.
fn encode_text(
  writer : @bits.BitWriter,
  pgn : Int32,
  f : PgnField,
  text : String,
) -> Unit raise @protocol.ProtocolError {
  let capacity = f.bit_length / 8
  let chars : Array[Int32] = []
  for ch in text {
    let code = ch.to_int()
    if code < 0x20 || code > 0x7E {
      raise @protocol.InvalidFieldValue(
        pgn~,
        field=f.name,
        reason="P0 text fields accept printable ASCII only",
      )
    }
    chars.push(code)
  }
  if chars.length() > capacity {
    raise @protocol.InvalidFieldValue(
      pgn~,
      field=f.name,
      reason="text longer than declared field",
    )
  }
  for i in 0..<capacity {
    let byte = if i < chars.length() { chars[i] } else { 0 }
    writer.write_uint(offset=f.bit_offset + i * 8, bits=8, byte.to_uint64())
  }
}
