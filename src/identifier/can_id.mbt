// Extended 29-bit CAN identifier model for NMEA 2000 (plan section 3.2).
//
// Layout (bits 31..29 unused, bits 28..0 carry the 29-bit identifier):
//   priority         bits 28..26 (3 bits, 0 = highest priority)
//   reserved         bit  25
//   data page        bit  24
//   PDU format (PF)  bits 23..16
//   PDU specific(PS) bits 15..8
//   source address   bits  7..0
//
// PGN computation differs by PDU format:
//   PF < 240  -> PDU1: PS is the destination address and is EXCLUDED from
//                    the PGN low 8 bits.
//   PF >= 240 -> PDU2: PS is the group extension and IS included in the
//                    PGN low 8 bits.
//
// All bit arithmetic uses UInt; floating point is never involved.

///|
/// Largest legal 29-bit extended CAN identifier.
pub const MAX_RAW : UInt32 = 0x1FFFFFFFU

///|
/// PF boundary: PDU1 below this value, PDU2 at or above it.
pub const PDU2_MIN_PF : Int32 = 240

///|
/// Extended 29-bit CAN identifier.
///
/// Construct only via `from_raw`, `from_raw_strict` or `make`; the `raw`
/// field is readable everywhere but constructible only inside this package,
/// so every public constructor validates its input.
#derive(@debug.Debug, Eq)
pub struct CanId {
  raw : UInt32
}

///|
/// Parse a raw identifier in lenient mode.
///
/// Rejects values outside the 29-bit range. The reserved bit is preserved
/// as-is; use `from_raw_strict` to reject reserved-bit usage and
/// `diagnostics` to inspect lenient-mode findings.
pub fn CanId::from_raw(raw : UInt32) -> CanId raise @protocol.ProtocolError {
  if raw > MAX_RAW {
    raise @protocol.InvalidCanId(
      raw~,
      reason="value exceeds the 29-bit extended identifier range",
    )
  }
  { raw, }
}

///|
/// Parse in strict mode: additionally rejects identifiers whose reserved
/// bit is set. The data page is always legal (0 or 1).
pub fn CanId::from_raw_strict(
  raw : UInt32,
) -> CanId raise @protocol.ProtocolError {
  let id = CanId::from_raw(raw)
  if id.reserved_bit() == 1 {
    raise @protocol.InvalidCanId(
      raw~,
      reason="reserved bit set, rejected in strict mode",
    )
  }
  id
}

///|
/// Construct an identifier from its fields, validating every range.
pub fn CanId::make(
  priority~ : Int32,
  data_page~ : Int32,
  pdu_format~ : Int32,
  pdu_specific~ : Int32,
  source~ : Int32,
) -> CanId raise @protocol.ProtocolError {
  if priority < 0 || priority > 7 {
    raise @protocol.InvalidCanId(raw=0U, reason="priority must be 0..7")
  }
  if data_page < 0 || data_page > 1 {
    raise @protocol.InvalidCanId(raw=0U, reason="data page must be 0..1")
  }
  if pdu_format < 0 || pdu_format > 255 {
    raise @protocol.InvalidCanId(raw=0U, reason="PDU format must be 0..255")
  }
  if pdu_specific < 0 || pdu_specific > 255 {
    raise @protocol.InvalidCanId(raw=0U, reason="PDU specific must be 0..255")
  }
  if source < 0 || source > 255 {
    raise @protocol.InvalidCanId(raw=0U, reason="source address must be 0..255")
  }
  let raw = (priority.reinterpret_as_uint() << 26)
    .lor(data_page.reinterpret_as_uint() << 24)
    .lor(pdu_format.reinterpret_as_uint() << 16)
    .lor(pdu_specific.reinterpret_as_uint() << 8)
    .lor(source.reinterpret_as_uint())
  { raw, }
}

///|
/// Return the raw 29-bit value.
pub fn CanId::to_raw(self : CanId) -> UInt32 {
  self.raw
}

///|
/// Priority field, 0 (highest) .. 7 (lowest).
pub fn CanId::priority(self : CanId) -> Int32 {
  (self.raw >> 26).reinterpret_as_int()
}

///|
/// Reserved bit (0 or 1), preserved as-is in lenient mode.
pub fn CanId::reserved_bit(self : CanId) -> Int32 {
  ((self.raw >> 25) & 1U).reinterpret_as_int()
}

///|
/// Data page bit (0 or 1).
pub fn CanId::data_page(self : CanId) -> Int32 {
  ((self.raw >> 24) & 1U).reinterpret_as_int()
}

///|
/// PDU format byte, 0..255. Values below 240 mean PDU1.
pub fn CanId::pdu_format(self : CanId) -> Int32 {
  ((self.raw >> 16) & 0xFFU).reinterpret_as_int()
}

///|
/// PDU specific byte, 0..255. Destination address for PDU1, group
/// extension for PDU2.
pub fn CanId::pdu_specific(self : CanId) -> Int32 {
  ((self.raw >> 8) & 0xFFU).reinterpret_as_int()
}

///|
/// Source address, 0..255.
pub fn CanId::source(self : CanId) -> Int32 {
  (self.raw & 0xFFU).reinterpret_as_int()
}

///|
/// True when the PDU format is below 240 (PDU1, point-to-point).
pub fn CanId::is_pdu1(self : CanId) -> Bool {
  self.pdu_format() < PDU2_MIN_PF
}

///|
/// Destination address; only present for PDU1 identifiers.
pub fn CanId::destination(self : CanId) -> Int32? {
  if self.is_pdu1() {
    Some(self.pdu_specific())
  } else {
    None
  }
}

///|
/// Compute the parameter group number for this identifier (plan 3.2):
/// `pgn = (dp << 16) | (pf << 8) | (pf >= 240 ? ps : 0)`.
pub fn CanId::pgn(self : CanId) -> Pgn {
  let pf = self.pdu_format()
  if pf < PDU2_MIN_PF {
    {
      value: (self.data_page() << 16) | (pf << 8),
      is_pdu1: true,
      destination: Some(self.pdu_specific()),
    }
  } else {
    {
      value: (self.data_page() << 16) | (pf << 8) | self.pdu_specific(),
      is_pdu1: false,
      destination: None,
    }
  }
}

///|
/// Non-fatal findings for this identifier in lenient mode (plan 3.2:
/// "解析层保留信息，宽松模式可以带诊断接受"). Currently reports a set
/// reserved bit; future checks may add more findings without breaking
/// the API.
pub fn CanId::diagnostics(self : CanId) -> Array[@protocol.Diagnostic] {
  let out : Array[@protocol.Diagnostic] = []
  if self.reserved_bit() == 1 {
    out.push(
      @protocol.Diagnostic::make(
        "ReservedBitSet",
        @protocol.Warning,
        "reserved bit is set; identifier accepted in lenient mode",
        context=[("raw", self.raw.to_string())],
      ),
    )
  }
  out
}

///|
/// Promote derived trait methods to regular methods (toolchain deprecates
/// implicit promotion).
pub extend CanId with @debug.Debug::{to_repr}

///|
pub extend CanId with Eq::{not_equal, equal}
