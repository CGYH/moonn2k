// Parameter group number model (plan section 5.2).
//
// A PGN is derived from the CAN ID's data page, PDU format and (for PDU2)
// PDU specific byte. It is a plain value: unknown PGNs are legal and the
// registry lookup failure is not a protocol error (handled in the codec
// layer, plan section 7.5).

///|
/// Parameter group number with PDU-level context.
#derive(@debug.Debug, Eq)
pub(all) struct Pgn {
  /// Numeric PGN value, 0..0x3FFFF (18 significant bits).
  value : Int32
  /// True when the identifier was PDU1 (point-to-point).
  is_pdu1 : Bool
  /// Destination address for PDU1 identifiers, otherwise None.
  destination : Int32?
}

///|
/// Largest legal PGN value: data page (1 bit, bit 16) | PF (8 bits,
/// bits 8..15) | PS (8 bits, bits 0..7) = 17 bits.
pub const MAX_PGN_VALUE : Int32 = 0x1FFFF

///|
/// Promote derived trait methods to regular methods (toolchain deprecates
/// implicit promotion).
pub extend Pgn with @debug.Debug::{to_repr}

///|
pub extend Pgn with Eq::{not_equal, equal}
