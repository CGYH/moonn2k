// Typed message construction on top of the registry (plan sections 4.2
// layer 2/3 boundary; used by the T11 end-to-end test, the simulator and
// the CLI).

///|
/// Encode typed field values into a complete Message for the given PGN
/// metadata. Payloads of 0..8 bytes become single-frame messages; 9..223
/// become FastPacket messages (transport chosen by length, matching the
/// wire rules).
pub fn encode_pgn_message(
  r : @registry.Registry,
  meta : @registry.PgnMetadata,
  fields : Array[(String, @codec.FieldValue)],
  source~ : Int32,
  destination~ : Int32? = None,
  priority~ : Int32? = None,
) -> @message.Message raise @protocol.ProtocolError {
  let payload = r.encode_fields(meta, fields)
  let id = pgn_can_id(meta, source~, destination~, priority~)
  let transport = if payload.length() <= 8 {
    @message.SingleFrame
  } else {
    @message.FastPacket
  }
  // Fast Packet frame count: 1 + ceil((len-6)/7) for 9..223 byte payloads.
  let frame_count = if payload.length() <= 8 {
    1
  } else {
    @fast_packet.frame_count_for(payload.length())
  }
  @message.Message::make(
    id,
    payload,
    transport~,
    source_frame_count=frame_count,
  )
}

///|
/// Decode a Message through the registry (thin forwarder so callers above
/// this layer need only import src/pgn).
pub fn decode_pgn_message(
  r : @registry.Registry,
  msg : @message.Message,
) -> @registry.DecodedMessage raise @protocol.ProtocolError {
  r.decode(msg)
}

///|
/// Canonical hex rendering of a payload (CLI decode output uses this).
pub fn payload_hex(payload : Bytes) -> String {
  @frame.bytes_to_hex(payload)
}

///|
/// Build the default CAN ID for a PGN (forwarder so callers above this
/// layer need only import src/pgn).
pub fn pgn_can_id(
  meta : @registry.PgnMetadata,
  source~ : Int32,
  destination~ : Int32? = None,
  priority~ : Int32? = None,
) -> @identifier.CanId raise @protocol.ProtocolError {
  meta.make_can_id(source~, destination~, priority~)
}
