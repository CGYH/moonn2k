// P0 PGN metadata (plan sections 2, 7.6; T09/T10/T11).
//
// Every field layout below was verified against the canboat project's
// docs/canboat.json, pinned at canboat/canboat@6ce848c6048ae81414c90dd3cee57699f98c6738
// (SchemaVersion 2.8.0, fetched 2026-11-12). Bit offsets and lengths are
// reproduced verbatim from that file; see fixtures/pgn-*.json vectors and
// THIRD_PARTY.md.
//
// Not-Available patterns are NOT defined by canboat for these PGNs. The
// values used here follow common NMEA 2000 practice (all-ones for unsigned
// radian/speed fields, 0x7FFFFFFF for 1e-7 degree positions, 0x7FFF for
// signed millimetre offsets); fixtures note this per field.

///|
pub const PGN_ISO_REQUEST : Int32 = 59904

///|
pub const PGN_ISO_ADDRESS_CLAIM : Int32 = 60928

///|
pub const PGN_SYSTEM_TIME : Int32 = 126992

///|
pub const PGN_HEARTBEAT : Int32 = 126993

///|
pub const PGN_PRODUCT_INFO : Int32 = 126996

///|
pub const PGN_VESSEL_HEADING : Int32 = 127250

///|
pub const PGN_WATER_DEPTH : Int32 = 128267

///|
pub const PGN_POSITION_RAPID : Int32 = 129025

///|
pub const PGN_COG_SOG_RAPID : Int32 = 129026

///|
pub const PGN_WIND_DATA : Int32 = 130306

///|
/// @registry.Unsigned field helper.
fn uf(
  name : String,
  off : Int32,
  bits : Int32,
  res~ : Double? = None,
  unit~ : String? = None,
  na~ : UInt64? = None,
) -> @registry.PgnField {
  {
    name,
    field_type: @registry.Unsigned,
    bit_offset: off,
    bit_length: bits,
    resolution: res,
    offset: None,
    unit,
    na_raw: na,
    lookup: [],
  }
}

///|
/// @registry.Signed field helper.
fn sf(
  name : String,
  off : Int32,
  bits : Int32,
  res~ : Double? = None,
  unit~ : String? = None,
  na~ : UInt64? = None,
) -> @registry.PgnField {
  {
    name,
    field_type: @registry.Signed,
    bit_offset: off,
    bit_length: bits,
    resolution: res,
    offset: None,
    unit,
    na_raw: na,
    lookup: [],
  }
}

///|
/// @registry.Lookup/enum field helper.
fn lf(
  name : String,
  off : Int32,
  bits : Int32,
  table : Array[(UInt64, String)],
  na~ : UInt64? = None,
) -> @registry.PgnField {
  {
    name,
    field_type: @registry.Lookup,
    bit_offset: off,
    bit_length: bits,
    resolution: None,
    offset: None,
    unit: None,
    na_raw: na,
    lookup: table,
  }
}

///|
/// Bit-field (flags) helper.
fn bf(name : String, off : Int32, bits : Int32) -> @registry.PgnField {
  {
    name,
    field_type: @registry.BitField,
    bit_offset: off,
    bit_length: bits,
    resolution: None,
    offset: None,
    unit: None,
    na_raw: None,
    lookup: [],
  }
}

///|
/// Fixed-width text field helper (NUL padded).
fn tf(name : String, off : Int32, bits : Int32) -> @registry.PgnField {
  {
    name,
    field_type: @registry.Text,
    bit_offset: off,
    bit_length: bits,
    resolution: None,
    offset: None,
    unit: None,
    na_raw: None,
    lookup: [],
  }
}

///|
/// PGN 59904 ISO Request: one 24-bit PGN field (canboat Length 3).
pub fn pgn_meta_iso_request() -> @registry.PgnMetadata {
  {
    pgn: PGN_ISO_REQUEST,
    name: "ISO Request",
    transport: SingleFrame,
    default_priority: 6,
    length: 3,
    fields: [uf("PGN requested", 0, 24)],
  }
}

///|
/// PGN 60928 ISO Address Claim: 64-bit NAME bit field (canboat Length 8).
pub fn pgn_meta_iso_address_claim() -> @registry.PgnMetadata {
  {
    pgn: PGN_ISO_ADDRESS_CLAIM,
    name: "ISO Address Claim",
    transport: SingleFrame,
    default_priority: 6,
    length: 8,
    fields: [
      uf("Unique Number", 0, 21),
      uf("Manufacturer Code", 21, 11),
      uf("Device Instance Lower", 32, 3),
      uf("Device Instance Upper", 35, 5),
      uf("Device Function", 40, 8),
      bf("Spare", 48, 1),
      uf("Device Class", 49, 7),
      uf("System Instance", 56, 4),
      uf("Industry Group", 60, 3),
      bf("Arbitrary address capable", 63, 1),
    ],
  }
}

///|
/// PGN 126992 System Time (canboat Length 8).
pub fn pgn_meta_system_time() -> @registry.PgnMetadata {
  {
    pgn: PGN_SYSTEM_TIME,
    name: "System Time",
    transport: SingleFrame,
    default_priority: 6,
    length: 8,
    fields: [
      uf("SID", 0, 8),
      uf("Source", 8, 4),
      bf("Reserved (bits 12..16)", 12, 4),
      uf("Date", 16, 16, res=Some(1.0), unit=Some("d"), na=Some(0xFFFFUL)),
      uf(
        "Time",
        32,
        32,
        res=Some(0.0001),
        unit=Some("s"),
        na=Some(0xFFFFFFFFUL),
      ),
    ],
  }
}

///|
/// PGN 126993 Heartbeat (canboat Length 8).
pub fn pgn_meta_heartbeat() -> @registry.PgnMetadata {
  {
    pgn: PGN_HEARTBEAT,
    name: "Heartbeat",
    transport: SingleFrame,
    default_priority: 7,
    length: 8,
    fields: [
      uf("Data transmit offset", 0, 16, res=Some(0.001), unit=Some("s")),
      uf("Sequence Counter", 16, 8),
      bf("Controller 1 State", 24, 2),
      bf("Controller 2 State", 26, 2),
      bf("Equipment Status", 28, 2),
      bf("Reserved (bits 30..64)", 30, 34),
    ],
  }
}

///|
/// PGN 126996 Product Information (canboat Length 134, Fast Packet).
pub fn pgn_meta_product_info() -> @registry.PgnMetadata {
  {
    pgn: PGN_PRODUCT_INFO,
    name: "Product Information",
    transport: FastPacket,
    default_priority: 6,
    length: 134,
    fields: [
      uf("NMEA 2000 Version", 0, 16, res=Some(0.001)),
      uf("Product Code", 16, 16),
      tf("Model ID", 32, 256),
      tf("Software Version Code", 288, 256),
      tf("Model Version", 544, 256),
      tf("Model Serial Code", 800, 256),
      uf("Certification Level", 1056, 8),
      uf("Load Equivalency", 1064, 8),
    ],
  }
}

///|
/// PGN 127250 Vessel Heading (canboat Length 8).
pub fn pgn_meta_vessel_heading() -> @registry.PgnMetadata {
  {
    pgn: PGN_VESSEL_HEADING,
    name: "Vessel Heading",
    transport: SingleFrame,
    default_priority: 2,
    length: 8,
    fields: [
      uf("SID", 0, 8),
      uf(
        "Heading",
        8,
        16,
        res=Some(0.0001),
        unit=Some("rad"),
        na=Some(0xFFFFUL),
      ),
      sf(
        "Deviation",
        24,
        16,
        res=Some(0.0001),
        unit=Some("rad"),
        na=Some(0x7FFFUL),
      ),
      sf(
        "Variation",
        40,
        16,
        res=Some(0.0001),
        unit=Some("rad"),
        na=Some(0x7FFFUL),
      ),
      lf("Reference", 56, 2, [
        (0UL, "True"),
        (1UL, "Magnetic"),
        (2UL, "Error"),
        (3UL, "Simulator"),
      ]),
      bf("Reserved (bits 58..64)", 58, 6),
    ],
  }
}

///|
/// PGN 128267 Water Depth (canboat Length 8): 32-bit depth, signed offset.
pub fn pgn_meta_water_depth() -> @registry.PgnMetadata {
  {
    pgn: PGN_WATER_DEPTH,
    name: "Water Depth",
    transport: SingleFrame,
    default_priority: 6,
    length: 8,
    fields: [
      uf("SID", 0, 8),
      uf("Depth", 8, 32, res=Some(0.01), unit=Some("m"), na=Some(0xFFFFFFFFUL)),
      sf("Offset", 40, 16, res=Some(0.001), unit=Some("m"), na=Some(0x7FFFUL)),
      uf("Range", 56, 8, res=Some(10.0), unit=Some("m")),
    ],
  }
}

///|
/// PGN 129025 Position, Rapid Update (canboat Length 8).
pub fn pgn_meta_position_rapid() -> @registry.PgnMetadata {
  {
    pgn: PGN_POSITION_RAPID,
    name: "Position, Rapid Update",
    transport: SingleFrame,
    default_priority: 6,
    length: 8,
    fields: [
      sf(
        "Latitude",
        0,
        32,
        res=Some(0.0000001),
        unit=Some("deg"),
        na=Some(0x7FFFFFFFUL),
      ),
      sf(
        "Longitude",
        32,
        32,
        res=Some(0.0000001),
        unit=Some("deg"),
        na=Some(0x7FFFFFFFUL),
      ),
    ],
  }
}

///|
/// PGN 129026 COG & SOG, Rapid Update (canboat Length 8).
pub fn pgn_meta_cog_sog_rapid() -> @registry.PgnMetadata {
  {
    pgn: PGN_COG_SOG_RAPID,
    name: "COG & SOG, Rapid Update",
    transport: SingleFrame,
    default_priority: 6,
    length: 8,
    fields: [
      uf("SID", 0, 8),
      lf("COG Reference", 8, 2, [
        (0UL, "True"),
        (1UL, "Magnetic"),
        (2UL, "Error"),
        (3UL, "Simulator"),
      ]),
      bf("Reserved (bits 10..16)", 10, 6),
      uf("COG", 16, 16, res=Some(0.0001), unit=Some("rad"), na=Some(0xFFFFUL)),
      uf("SOG", 32, 16, res=Some(0.01), unit=Some("m/s"), na=Some(0xFFFFUL)),
      bf("Reserved (bits 48..64)", 48, 16),
    ],
  }
}

///|
/// PGN 130306 Wind Data (canboat Length 8).
pub fn pgn_meta_wind_data() -> @registry.PgnMetadata {
  {
    pgn: PGN_WIND_DATA,
    name: "Wind Data",
    transport: SingleFrame,
    default_priority: 2,
    length: 8,
    fields: [
      uf("SID", 0, 8),
      uf(
        "Wind Speed",
        8,
        16,
        res=Some(0.01),
        unit=Some("m/s"),
        na=Some(0xFFFFUL),
      ),
      uf(
        "Wind Angle",
        24,
        16,
        res=Some(0.0001),
        unit=Some("rad"),
        na=Some(0xFFFFUL),
      ),
      lf("Reference", 40, 3, [
        (0UL, "True (North referenced)"),
        (1UL, "Magnetic (North referenced)"),
        (2UL, "Apparent (Relative to vessel centerline)"),
        (3UL, "True (North referenced), historical"),
        (4UL, "Apparent (Relative to vessel centerline), historical"),
      ]),
      bf("Reserved (bits 43..64)", 43, 21),
    ],
  }
}

///|
/// Build a registry pre-loaded with the whole P0 support set, ordered and
/// documented in docs/pgn-support.md.
pub fn default_registry() -> @registry.Registry {
  let r = @registry.Registry::new()
  r.register(pgn_meta_iso_request())
  r.register(pgn_meta_iso_address_claim())
  r.register(pgn_meta_system_time())
  r.register(pgn_meta_heartbeat())
  r.register(pgn_meta_product_info())
  r.register(pgn_meta_vessel_heading())
  r.register(pgn_meta_water_depth())
  r.register(pgn_meta_position_rapid())
  r.register(pgn_meta_cog_sog_rapid())
  r.register(pgn_meta_wind_data())
  r
}
