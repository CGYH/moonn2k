// Deterministic virtual devices (plan section 7.7, T12).
//
// Fixed inputs, fixed field values, explicit virtual time step: two runs
// of the same scenario produce byte-identical output. No wall clock, no
// randomness, no I/O.

///|
/// One scheduled output of the scenario.
#derive(@debug.Debug)
pub(all) struct SimEntry {
  /// Virtual time the message is emitted at.
  at_ms : Int32
  message : @message.Message
}

///|
pub extend SimEntry with @debug.Debug::{to_repr}

///|
/// Metadata describing what a scenario contains.
#derive(@debug.Debug)
pub(all) struct ScenarioInfo {
  name : String
  step_ms : Int32
  /// PGNs emitted, in order.
  pgns : Array[Int32]
}

///|
pub extend ScenarioInfo with @debug.Debug::{to_repr}

///|
/// The "basic" scenario (plan 7.7): System Time, Position Rapid Update,
/// COG & SOG Rapid Update, Vessel Heading, Wind Data and Product
/// Information (Fast Packet). All values are fixed constants; positions
/// sit near a demo harbour, heading/COG east, 10 kn wind from 90 deg.
pub fn simulate_basic(step_ms~ : Int32 = 100) -> SimResult {
  let reg = @pgn.default_registry()
  let out : Array[SimEntry] = []
  let mut t = 0
  // System Time: date 19000, time 43200.0000 s.
  out.push({
    at_ms: t,
    message: try! @pgn.encode_pgn_message(
      reg,
      @pgn.pgn_meta_system_time(),
      [
        ("SID", @codec.Unsigned(255UL)),
        ("Source", @codec.Unsigned(0UL)),
        ("Reserved (bits 12..16)", @codec.Bits(0UL)),
        ("Date", @codec.Unsigned(19000UL)),
        ("Time", @codec.Unsigned(432000000UL)),
      ],
      source=36,
    ),
  })
  t = t + step_ms
  // Position, Rapid Update: 54.0123456 N, 10.0987654 E (positive east).
  out.push({
    at_ms: t,
    message: try! @pgn.encode_pgn_message(
      reg,
      @pgn.pgn_meta_position_rapid(),
      [
        ("Latitude", @codec.Signed(540123456L)),
        ("Longitude", @codec.Signed(100987654L)),
      ],
      source=36,
    ),
  })
  t = t + step_ms
  // COG & SOG: COG 0.7854 rad (45 deg), SOG 5.14 m/s (~10 kn).
  out.push({
    at_ms: t,
    message: try! @pgn.encode_pgn_message(
      reg,
      @pgn.pgn_meta_cog_sog_rapid(),
      [
        ("SID", @codec.Unsigned(12UL)),
        ("COG Reference", @codec.Lookup(0UL, None)),
        ("Reserved (bits 10..16)", @codec.Bits(0UL)),
        ("COG", @codec.Unsigned(7854UL)),
        ("SOG", @codec.Unsigned(514UL)),
        ("Reserved (bits 48..64)", @codec.Bits(0UL)),
      ],
      source=36,
    ),
  })
  t = t + step_ms
  // Vessel Heading: 1.5708 rad (90 deg), magnetic, no deviation.
  out.push({
    at_ms: t,
    message: try! @pgn.encode_pgn_message(
      reg,
      @pgn.pgn_meta_vessel_heading(),
      [
        ("SID", @codec.Unsigned(20UL)),
        ("Heading", @codec.Unsigned(15708UL)),
        ("Deviation", @codec.Signed(0L)),
        ("Variation", @codec.Signed(25L)),
        ("Reference", @codec.Lookup(1UL, None)),
        ("Reserved (bits 58..64)", @codec.Bits(0UL)),
      ],
      source=36,
    ),
  })
  t = t + step_ms
  // Wind Data: 5.0 m/s apparent from 1.5708 rad.
  out.push({
    at_ms: t,
    message: try! @pgn.encode_pgn_message(
      reg,
      @pgn.pgn_meta_wind_data(),
      [
        ("SID", @codec.Unsigned(30UL)),
        ("Wind Speed", @codec.Unsigned(500UL)),
        ("Wind Angle", @codec.Unsigned(15708UL)),
        ("Reference", @codec.Lookup(2UL, None)),
        ("Reserved (bits 43..64)", @codec.Bits(0UL)),
      ],
      source=36,
    ),
  })
  t = t + step_ms
  // Product Information (Fast Packet, 134 bytes).
  out.push({
    at_ms: t,
    message: try! @pgn.encode_pgn_message(
      reg,
      @pgn.pgn_meta_product_info(),
      [
        ("NMEA 2000 Version", @codec.Unsigned(2100UL)),
        ("Product Code", @codec.Unsigned(888UL)),
        ("Model ID", @codec.Text("moonn2k-demo")),
        ("Software Version Code", @codec.Text("v0.1.0")),
        ("Model Version", @codec.Text("sim-unit-1")),
        ("Model Serial Code", @codec.Text("SN00042")),
        ("Certification Level", @codec.Unsigned(0UL)),
        ("Load Equivalency", @codec.Unsigned(1UL)),
      ],
      source=36,
    ),
  })
  {
    info: {
      name: "basic",
      step_ms,
      pgns: [126992, 129025, 129026, 127250, 130306, 126996],
    },
    entries: out,
  }
}

///|
/// Scenario output.
#derive(@debug.Debug)
pub(all) struct SimResult {
  info : ScenarioInfo
  entries : Array[SimEntry]
}

///|
pub extend SimResult with @debug.Debug::{to_repr}

///|
/// Scenario metadata.
pub fn SimResult::info(self : SimResult) -> ScenarioInfo {
  self.info
}

///|
/// Scheduled messages in virtual time order.
pub fn SimResult::entries(self : SimResult) -> Array[SimEntry] {
  self.entries
}

///|
/// Look up a scenario by name; "basic" is the only P0 scenario.
pub fn run_scenario(name : String, step_ms~ : Int32 = 100) -> SimResult? {
  if name == "basic" {
    Some(simulate_basic(step_ms~))
  } else {
    None
  }
}

///|
/// One CAN frame scheduled at a virtual time (Fast Packet messages expand
/// to their full frame sequence).
pub(all) struct SimFrame {
  at_ms : Int32
  frame : @frame.CanFrame
}

///|
/// Expand the scenario into scheduled CAN frames (CLI simulate output).
pub fn SimResult::to_frames(
  self : SimResult,
  sequence_id~ : Int32 = 0,
) -> Array[SimFrame] raise @protocol.ProtocolError {
  let out : Array[SimFrame] = []
  for e in self.entries {
    if e.message.transport is @message.SingleFrame {
      let f = @frame.CanFrame::make(e.message.id, e.message.payload)
      out.push({ at_ms: e.at_ms, frame: f, })
    } else {
      for
        f in @fast_packet.segment(e.message.id, e.message.payload, sequence_id) {
        out.push({ at_ms: e.at_ms, frame: f, })
      }
    }
  }
  out
}
