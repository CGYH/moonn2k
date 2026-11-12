// Classic CAN frame model (plan section 5.3).

///|
/// Maximum classic CAN payload size in bytes.
pub const MAX_FRAME_DATA : Int32 = 8

///|
/// A classic CAN frame: extended identifier plus 0..8 payload bytes.
///
/// Construct only via `make` / `from_hex`; fields are readable everywhere
/// but constructible only inside this package, so the 0..8 length invariant
/// cannot be bypassed.
#derive(@debug.Debug, Eq)
pub struct CanFrame {
  id : @identifier.CanId
  data : Bytes
}

///|
/// Promote derived trait methods to regular methods (toolchain deprecates
/// implicit promotion).
pub extend CanFrame with @debug.Debug::{to_repr}

///|
pub extend CanFrame with Eq::{not_equal, equal}

///|
/// Construct a frame from an identifier and payload bytes.
///
/// Payloads longer than 8 bytes are rejected; no implicit truncation is
/// provided (plan 5.3).
pub fn CanFrame::make(
  id : @identifier.CanId,
  data : Bytes,
) -> CanFrame raise @protocol.ProtocolError {
  if data.length() < 0 || data.length() > MAX_FRAME_DATA {
    raise @protocol.InvalidFrameLength(
      length=data.length(),
      reason="classic CAN payload must be 0..8 bytes",
    )
  }
  { id, data, }
}

///|
/// Parse hex payload text into a frame. Hex policy: see `hex_to_bytes`.
/// Payloads longer than 8 bytes are rejected with `InvalidFrameLength`.
pub fn CanFrame::from_hex(
  id : @identifier.CanId,
  hex : String,
) -> CanFrame raise @protocol.ProtocolError {
  let data = hex_to_bytes(hex)
  CanFrame::make(id, data)
}

///|
/// Canonical hex rendering of the payload (lowercase, compact).
pub fn CanFrame::to_hex(self : CanFrame) -> String {
  bytes_to_hex(self.data)
}
