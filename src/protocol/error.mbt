// Structured protocol errors for the moonn2k core (plan section 5.6).
//
// Every variant carries typed context (raw values, PGN, field name, offsets,
// limits) instead of pre-formatted strings, so callers can classify failures
// without parsing messages. Normal unknown PGNs are NOT errors: UnknownPgn is
// only raised when a caller explicitly opts into strict-known mode.

///|
/// Structured protocol error covering every failure mode in the core.
#derive(@debug.Debug)
pub(all) suberror ProtocolError {
  /// Raw value outside the 29-bit extended identifier range, or a field
  /// rejected while constructing an identifier.
  InvalidCanId(raw~ : UInt32, reason~ : String)
  /// CAN frame payload outside the 0..8 byte range.
  InvalidFrameLength(length~ : Int32, reason~ : String)
  /// Hexadecimal text could not be parsed (odd length, invalid characters).
  InvalidHex(reason~ : String, input~ : String)
  /// A typed PGN field needs more bits/bytes than the payload provides.
  TruncatedField(
    pgn~ : Int32,
    field~ : String,
    offset~ : Int32,
    needed~ : Int32,
    available~ : Int32
  )
  /// A field value violates its PGN definition (range, enum, encoding).
  InvalidFieldValue(pgn~ : Int32, field~ : String, reason~ : String)
  /// A field uses a type this build does not support.
  UnsupportedFieldType(pgn~ : Int32, field~ : String, type_name~ : String)
  /// Fast Packet declared length outside 9..223.
  InvalidFastPacketLength(declared~ : Int32, reason~ : String)
  /// A Fast Packet frame does not fit the current session state.
  UnexpectedFastFrame(
    reason~ : String,
    pgn~ : Int32,
    source~ : Int32,
    sequence_id~ : Int32,
    frame_index~ : Int32
  )
  /// Same session and frame index but different payload bytes.
  ConflictingDuplicateFrame(
    pgn~ : Int32,
    source~ : Int32,
    sequence_id~ : Int32,
    frame_index~ : Int32
  )
  /// More concurrent reassembly sessions than the configured limit.
  SessionLimitExceeded(limit~ : Int32)
  /// Payload larger than the Fast Packet maximum (223 bytes).
  PayloadTooLarge(length~ : Int32, limit~ : Int32)
  /// Only raised in explicit strict-known mode; never by the default router.
  UnknownPgn(pgn~ : Int32)
}

///|
/// Promote the derived debug rendering to a regular method (toolchain
/// deprecates implicit promotion).
pub extend ProtocolError with @debug.Debug::{to_repr}
