// Field value model (plan section 5.5).
//
// The raw value and the physical value are both preserved: Physical keeps
// raw + resolution + offset so the physical quantity is derived on demand
// without ever collapsing everything into a single Double. Illegal enum
// values surface as Lookup(raw, None) instead of pretending a name.

///|
/// Decoded value of one PGN field.
#derive(@debug.Debug, Eq)
pub(all) enum FieldValue {
  /// Raw unsigned integer as stored on the wire.
  Unsigned(UInt64)
  /// Raw two's-complement signed integer.
  Signed(Int64)
  /// Physical quantity: `value = raw * resolution + offset`, with the raw
  /// bits kept alongside.
  Physical(UInt64, Double, Double)
  /// Enum/lookup entry; None when the raw value has no known name.
  Lookup(UInt64, String?)
  /// Bit field (flags), raw only.
  Bits(UInt64)
  /// Text payload (e.g. Product Information strings).
  Text(String)
  /// Opaque byte payload.
  Bytes(Bytes)
  /// Field explicitly marked Not Available per its definition.
  NotAvailable
}

///|
/// Promote derived trait methods to regular methods.
pub extend FieldValue with @debug.Debug::{to_repr}

///|
pub extend FieldValue with Eq::{not_equal, equal}

///|
/// The raw bit pattern behind a value, when one exists.
pub fn FieldValue::raw(self : FieldValue) -> UInt64? {
  match self {
    Unsigned(raw) => Some(raw)
    Signed(raw) => Some(raw.reinterpret_as_uint64())
    Physical(raw, _, _) => Some(raw)
    Lookup(raw, _) => Some(raw)
    Bits(raw) => Some(raw)
    Text(_) => None
    Bytes(_) => None
    NotAvailable => None
  }
}

///|
/// Physical value for a Physical field: `raw * resolution + offset`.
pub fn FieldValue::physical(self : FieldValue) -> Double? {
  match self {
    Physical(raw, resolution, offset) =>
      Some(raw.to_double() * resolution + offset)
    _ => None
  }
}
