// PGN metadata model and instance-scoped registry (plan sections 5.9, 7.5).
//
// The registry is a plain value owned by the caller: no global mutable map,
// so tests never pollute each other. Lookup failure is NOT an error; the
// router passes unknown PGNs through untouched (plan 7.5).

///|
/// Field kind as declared by the metadata.
#derive(@debug.Debug, Eq)
pub(all) enum FieldType {
  /// Unsigned integer of bit_length bits.
  Unsigned
  /// Two's-complement signed integer.
  Signed
  /// Bit field / flags.
  BitField
  /// Lookup/enum with names resolved from the field's table.
  Lookup
  /// UTF-8-ish text payload (consumes whole bytes from its offset).
  Text
  /// Opaque bytes.
  Opaque
}

///|
pub extend FieldType with @debug.Debug::{to_repr}

///|
pub extend FieldType with Eq::{not_equal, equal}

///|
/// One field of a PGN's payload layout.
#derive(@debug.Debug)
pub(all) struct PgnField {
  name : String
  field_type : FieldType
  /// Bit offset from the start of the payload (LSB-first bit order).
  bit_offset : Int32
  bit_length : Int32
  /// Physical scaling; None keeps the raw value only.
  resolution : Double?
  /// Physical offset applied after scaling.
  offset : Double?
  /// Unit string for the physical value.
  unit : String?
  /// Raw bit pattern meaning Not Available, per the field definition.
  /// Only exact matches become NotAvailable (plan 3.5: never treat every
  /// all-ones value as NA implicitly).
  na_raw : UInt64?
  /// Ordered lookup table for enum fields.
  lookup : Array[(UInt64, String)]
}

///|
pub extend PgnField with @debug.Debug::{to_repr}

///|
/// PGN-level metadata.
#derive(@debug.Debug)
pub(all) struct PgnMetadata {
  pgn : Int32
  name : String
  transport : Transport
  /// Default priority used by the simulator when emitting this PGN.
  default_priority : Int32
  /// Fixed payload length in bytes, or -1 for variable length.
  length : Int32
  fields : Array[PgnField]
}

///|
pub extend PgnMetadata with @debug.Debug::{to_repr}

///|
/// Transport kind for metadata (mirrors @message.Transport to avoid a
/// dependency edge; conversion happens at the boundary).
#derive(@debug.Debug, Eq)
pub(all) enum Transport {
  SingleFrame
  FastPacket
}

///|
pub extend Transport with @debug.Debug::{to_repr}

///|
pub extend Transport with Eq::{not_equal, equal}

///|
/// Instance-scoped PGN registry.
pub struct Registry {
  entries : Map[Int32, PgnMetadata]
}

///|
/// Create an empty registry.
pub fn Registry::new() -> Registry {
  { entries: Map([]), }
}

///|
/// Register (or replace) metadata for a PGN.
pub fn Registry::register(self : Registry, m : PgnMetadata) -> Unit {
  let _ = self.entries.set(m.pgn, m)
}

///|
/// Look up metadata; None means "unknown PGN", which is not an error
/// (plan 7.5).
pub fn Registry::lookup(self : Registry, pgn : Int32) -> PgnMetadata? {
  self.entries.get(pgn)
}

///|
/// All registered metadata, ordered by PGN for a stable support matrix
/// (plan 7.5: consumed by CLI explain and doc generation).
pub fn Registry::supported(self : Registry) -> Array[PgnMetadata] {
  let out : Array[PgnMetadata] = []
  for _, m in self.entries {
    out.push(m)
  }
  out.sort_by(fn(a, b) { a.pgn - b.pgn })
  out
}

///|
/// Build a CAN ID for this PGN from metadata: priority defaults to the
/// metadata default, and PDU1 destinations map to the PDU specific byte
/// (PDU2 ignores the destination).
pub fn PgnMetadata::make_can_id(
  self : PgnMetadata,
  source~ : Int32,
  destination~ : Int32? = None,
  priority~ : Int32? = None,
) -> @identifier.CanId raise @protocol.ProtocolError {
  let value = self.pgn
  let dp = value >> 16
  let pf = (value >> 8) & 0xFF
  let is_pdu1 = pf < 240
  let ps = match destination {
    Some(d) => if is_pdu1 { d } else { value & 0xFF }
    None => if is_pdu1 { 255 } else { value & 0xFF }
  }
  @identifier.CanId::make(
    priority=match priority {
      Some(p) => p
      None => self.default_priority
    },
    data_page=dp,
    pdu_format=pf,
    pdu_specific=ps,
    source~,
  )
}
