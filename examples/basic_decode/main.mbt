///|
/// Renders one decoded field as `<raw> -> <physical>`.
///
/// Scaled fields keep the signed value the layout declared, so a negative
/// longitude does not print as its two's-complement unsigned bit pattern.
/// Fixed formatting comes from `@cli.format_double` rather than a second
/// implementation here, so the example and the CLI cannot drift apart.
fn describe(field_value : @codec.FieldValue) -> String {
  match field_value {
    @codec.SignedPhysical(raw, resolution, offset) =>
      "raw=\{raw} -> \{@cli.format_double(raw.to_double() * resolution + offset)}"
    @codec.Physical(raw, resolution, offset) =>
      "raw=\{raw} -> \{@cli.format_double(raw.to_double() * resolution + offset)}"
    other =>
      match other.raw() {
        Some(raw) => "raw=\{raw}"
        None => "no numeric value"
      }
  }
}

///|
/// Minimal end-to-end example: one CAN frame in, named physical quantities out.
///
/// Input : the identifier and the 8 payload bytes fixed below; this pair is a
///         verified reference vector for PGN 129025 (Position, Rapid Update).
/// Output: the PGN derived from the identifier, then one line per field.
/// Fails : propagates `ProtocolError` when a known PGN cannot be decoded. This
///         input is a verified vector, so it does not raise.
fn main raise {
  let can_id = @identifier.CanId::from_raw(0x19F80196U)
  let payload = @frame.hex_to_bytes("40a13120fa0cfbf9")
  let message = @message.Message::make(
    can_id,
    payload,
    transport=@message.SingleFrame,
    source_frame_count=1,
  )
  match @pgn.decode_pgn_message(@pgn.default_registry(), message) {
    @registry.Known(pgn~, name~, fields~) => {
      println("pgn=\{pgn} name=\{name}")
      for field in fields {
        let (field_name, field_value) = field
        println("  \{field_name}: \{describe(field_value)}")
      }
    }
    @registry.Unknown(message) =>
      println(
        "unknown pgn=\{message.pgn.value}; payload kept as \{message.payload.length()} bytes",
      )
  }
}
