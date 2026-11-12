// PGN router: known PGNs decode through metadata; unknown PGNs pass
// through untouched (plan section 7.5).

///|
/// Result of routing one message through the registry.
#derive(@debug.Debug)
pub enum DecodedMessage {
  /// Known PGN decoded field-by-field via metadata.
  Known(
    pgn~ : Int32,
    name~ : String,
    fields~ : Array[(String, @codec.FieldValue)]
  )
  /// Unknown PGN: the original message, untouched. Never an error.
  Unknown(@message.Message)
}

///|
pub extend DecodedMessage with @debug.Debug::{to_repr}

///|
/// Decode a message. Errors for known PGNs always carry PGN and field
/// context (plan 7.5).
pub fn Registry::decode(
  self : Registry,
  msg : @message.Message,
) -> DecodedMessage raise @protocol.ProtocolError {
  let pgn = msg.pgn.value
  match self.lookup(pgn) {
    None => Unknown(msg)
    Some(meta) => {
      let reader = @bits.BitReader::new(msg.payload)
      let available_bits = msg.payload.length() * 8
      let out : Array[(String, @codec.FieldValue)] = []
      for field in meta.fields {
        match field.field_type {
          Text | Opaque => {
            // Byte-oriented fields: bit_offset must be byte aligned.
            let start = field.bit_offset / 8
            let len = if field.bit_length < 0 {
              // -1: consume the remaining payload bytes.
              msg.payload.length() - start
            } else {
              field.bit_length / 8
            }
            if len < 0 || start + len > msg.payload.length() {
              raise @protocol.TruncatedField(
                pgn~,
                field=field.name,
                offset=field.bit_offset,
                needed=len * 8,
                available=available_bits,
              )
            }
            if field.field_type is Opaque {
              out.push(
                (
                  field.name,
                  @codec.Bytes(
                    Bytes::makei(len, fn(i) { msg.payload.at(start + i) }),
                  ),
                ),
              )
            } else {
              out.push((field.name, decode_text(msg.payload, start, len)))
            }
          }
          other => {
            let raw = try {
              if other is Signed {
                reader
                .read_int(offset=field.bit_offset, bits=field.bit_length)
                .reinterpret_as_uint64()
              } else {
                reader.read_uint(offset=field.bit_offset, bits=field.bit_length)
              }
            } catch {
              @protocol.BitsOutOfBounds(offset~, bits~, available~) =>
                raise @protocol.TruncatedField(
                  pgn~,
                  field=field.name,
                  offset~,
                  needed=bits,
                  available~,
                )
              e => raise e
            }
            out.push((field.name, interpret(field, raw)))
          }
        }
      }
      Known(pgn~, name=meta.name, fields=out)
    }
  }
}

///|
/// Interpret a raw unsigned value per the field definition: exact NA
/// pattern, lookup name, physical scaling, or plain raw.
fn interpret(f : PgnField, raw : UInt64) -> @codec.FieldValue {
  match f.na_raw {
    Some(na) => if raw == na { return @codec.NotAvailable }
    None => ()
  }
  match f.field_type {
    Lookup => {
      let mut name : String? = None
      for pair in f.lookup {
        if pair.0 == raw {
          name = Some(pair.1)
          break
        }
      }
      @codec.Lookup(raw, name)
    }
    Unsigned | Signed =>
      match f.resolution {
        Some(res) => @codec.Physical(raw, res, offset_value(f.offset))
        None => @codec.Unsigned(raw)
      }
    BitField => @codec.Bits(raw)
    // Text/Opaque are handled in the byte-oriented branch above.
    Text | Opaque => @codec.Unsigned(raw)
  }
}

///|
fn offset_value(o : Double?) -> Double {
  match o {
    Some(v) => v
    None => 0.0
  }
}

///|
/// Decode a fixed-length text field, stopping at NUL/0xFF padding and
/// dropping trailing whitespace-free bytes.
fn decode_text(
  payload : Bytes,
  start : Int32,
  len : Int32,
) -> @codec.FieldValue {
  let chars : Array[Char] = []
  for i in 0..<len {
    let b = payload.at(start + i).to_int()
    if b == 0 || b == 0xFF {
      break
    }
    // Printable ASCII only in P0 texts; other bytes become '?'.
    if b >= 0x20 && b <= 0x7E {
      chars.push(b.unsafe_to_char())
    } else {
      chars.push('?')
    }
  }
  let out = StringBuilder()
  for c in chars {
    out.write_char(c)
  }
  @codec.Text(out.to_string())
}
