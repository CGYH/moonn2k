// Complete message model (plan section 5.4).
//
// Lives above identifier/protocol so that both the fast packet layer and
// the codec layer can reference it without cycles.

///|
/// How the payload travelled on the bus.
#derive(@debug.Debug, Eq)
pub(all) enum Transport {
  /// Payload fit in one classic CAN frame (0..8 bytes).
  SingleFrame
  /// Payload was transported via Fast Packet (9..223 bytes).
  FastPacket
}

///|
/// Promote derived trait methods to regular methods.
pub extend Transport with @debug.Debug::{to_repr}

///|
pub extend Transport with Eq::{not_equal, equal}

///|
/// A fully reassembled message: identifier, PGN, payload and transport kind.
#derive(@debug.Debug)
pub(all) struct Message {
  /// Extended CAN identifier the message arrived with.
  id : @identifier.CanId
  /// Parameter group number derived from the identifier.
  pgn : @identifier.Pgn
  /// Payload bytes (0..8 single frame, 9..223 fast packet).
  payload : Bytes
  transport : Transport
  /// Number of CAN frames the payload was carried in (1..32).
  source_frame_count : Int32
}

///|
/// Construct a message with validated payload bounds and transport kind.
pub fn Message::make(
  id : @identifier.CanId,
  payload : Bytes,
  transport~ : Transport,
  source_frame_count~ : Int32,
) -> Message raise @protocol.ProtocolError {
  let len = payload.length()
  match transport {
    SingleFrame =>
      if len > 8 {
        raise @protocol.InvalidFrameLength(
          length=len,
          reason="single frame payload must be 0..8 bytes",
        )
      }
    FastPacket =>
      if len < FAST_PACKET_MIN || len > FAST_PACKET_MAX {
        raise @protocol.InvalidFrameLength(
          length=len,
          reason="fast packet payload must be 9..223 bytes",
        )
      }
  }
  if source_frame_count < 1 || source_frame_count > FAST_PACKET_MAX_FRAMES {
    raise @protocol.InvalidFrameLength(
      length=source_frame_count,
      reason="source frame count must be 1..32",
    )
  }
  { id, pgn: id.pgn(), payload, transport, source_frame_count, }
}

///|
/// Promote the derived debug rendering to a regular method.
pub extend Message with @debug.Debug::{to_repr}

///|
/// Fast Packet payload bounds (plan section 3.3).
pub const FAST_PACKET_MIN : Int32 = 9

///|
pub const FAST_PACKET_MAX : Int32 = 223

///|
/// Maximum classic CAN frames per Fast Packet transfer (plan 3.3).
pub const FAST_PACKET_MAX_FRAMES : Int32 = 32
