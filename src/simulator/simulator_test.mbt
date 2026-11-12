// Simulator tests (plan section 8.4, SIM-001..SIM-006).

///|
/// SIM-001: the same scenario run twice is byte-identical.
test "SIM-001 deterministic output" {
  let a = @simulator.simulate_basic(step_ms=100)
  let b = @simulator.simulate_basic(step_ms=100)
  assert_eq(a.entries.length(), b.entries.length())
  for i in 0..<a.entries.length() {
    assert_eq(a.entries[i].at_ms, b.entries[i].at_ms)
    assert_eq(
      @pgn.payload_hex(a.entries[i].message.payload),
      @pgn.payload_hex(b.entries[i].message.payload),
    )
    assert_eq(
      a.entries[i].message.id.to_raw(),
      b.entries[i].message.id.to_raw(),
    )
  }
}

///|
/// SIM-002: virtual time advances by the explicit step.
test "SIM-002 virtual time steps" {
  let r = @simulator.simulate_basic(step_ms=250)
  for i, e in r.entries {
    assert_eq(e.at_ms, i * 250)
  }
}

///|
/// SIM-003: the basic scenario contains single-frame and Fast Packet.
test "SIM-003 mixed transports" {
  let r = @simulator.simulate_basic(step_ms=100)
  let mut single = 0
  let mut fast = 0
  for e in r.entries {
    match e.message.transport {
      @message.SingleFrame => single = single + 1
      @message.FastPacket => fast = fast + 1
    }
  }
  assert_eq(single, 5)
  assert_eq(fast, 1)
}

///|
/// SIM-004: every emitted message survives the protocol stack: segment
/// (when Fast Packet), ingest, reassemble, decode — no failures.
test "SIM-004 outputs pass protocol stack" {
  let r = @simulator.simulate_basic(step_ms=100)
  let reg = @pgn.default_registry()
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let mut decoded = 0
  for e in r.entries {
    if e.message.transport is @message.SingleFrame {
      match @pgn.decode_pgn_message(reg, e.message) {
        Known(pgn=_, ..) => decoded = decoded + 1
        Unknown(_) => fail("scenario PGN must be known")
      }
    } else {
      let frames = @fast_packet.segment(e.message.id, e.message.payload, 0)
      let mut completed : @message.Message? = None
      let mut t = e.at_ms
      for f in frames {
        t = t + 10
        match re.ingest(f, t) {
          @fast_packet.Completed(m) => completed = Some(m)
          _ => ()
        }
      }
      match completed {
        Some(m) =>
          match @pgn.decode_pgn_message(reg, m) {
            Known(pgn=_, ..) => decoded = decoded + 1
            Unknown(_) => fail("scenario PGN must be known")
          }
        None => fail("fast packet scenario message did not complete")
      }
    }
  }
  assert_eq(decoded, 6)
}

///|
/// SIM-005: reassembled Fast Packet payload matches the scenario input
/// field values.
test "SIM-005 reassembled fields match input" {
  let r = @simulator.simulate_basic(step_ms=100)
  let reg = @pgn.default_registry()
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let last = r.entries[5]
  let frames = @fast_packet.segment(last.message.id, last.message.payload, 0)
  let mut completed : @message.Message? = None
  let mut t = last.at_ms
  for f in frames {
    t = t + 10
    match re.ingest(f, t) {
      @fast_packet.Completed(m) => completed = Some(m)
      _ => ()
    }
  }
  match completed {
    Some(m) =>
      match @pgn.decode_pgn_message(reg, m) {
        Known(pgn=_, name=_, fields~) =>
          match sim_field(fields, "Model ID") {
            @codec.Text("moonn2k-demo") => ()
            _ => fail("model id changed across the stack")
          }
        Unknown(_) => fail("product info must be known")
      }
    None => fail("no completion")
  }
}

///|
fn sim_field(
  fields : Array[(String, @codec.FieldValue)],
  name : String,
) -> @codec.FieldValue raise {
  for pair in fields {
    if pair.0 == name {
      return pair.1
    }
  }
  fail("field missing")
}

///|
/// SIM-006: unknown scenario names are rejected deterministically.
test "SIM-006 scenario lookup" {
  assert_eq(@simulator.run_scenario("basic") is Some(_), true)
  assert_eq(@simulator.run_scenario("storm") is None, true)
}
