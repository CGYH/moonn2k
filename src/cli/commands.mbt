// decode / decode-frame / fast-send / simulate / selftest commands.

///|
fn field_json(fields : Array[(String, @codec.FieldValue)]) -> (String, String) {
  // (fields object, raw_fields object)
  let f = StringBuilder()
  let rf = StringBuilder()
  for i, pair in fields {
    if i > 0 {
      f.write_string(",")
      rf.write_string(",")
    }
    f.write_string(json_string(pair.0) + ":")
    rf.write_string(json_string(pair.0) + ":")
    match pair.1.raw() {
      Some(raw) => rf.write_string(u64_to_string(raw))
      None => rf.write_string("null")
    }
    match pair.1 {
      @codec.NotAvailable => f.write_string("{\"value\":\"NotAvailable\"}")
      @codec.Unsigned(raw) =>
        f.write_string("{\"raw\":" + u64_to_string(raw) + "}")
      @codec.Signed(v) => f.write_string("{\"raw\":" + v.to_string() + "}")
      @codec.Physical(raw, res, off) => {
        // Physical: value = raw * res + off; keep unit-less here.
        let value = raw.to_double() * res + off
        f.write_string(
          "{\"raw\":" +
          u64_to_string(raw) +
          ",\"value\":" +
          format_double(value) +
          "}",
        )
      }
      @codec.SignedPhysical(v, res, off) => {
        let value = v.to_double() * res + off
        f.write_string(
          "{\"raw\":" +
          v.to_string() +
          ",\"value\":" +
          format_double(value) +
          "}",
        )
      }
      @codec.Lookup(raw, name) =>
        match name {
          Some(n) =>
            f.write_string(
              "{\"raw\":" +
              u64_to_string(raw) +
              ",\"name\":" +
              json_string(n) +
              "}",
            )
          None =>
            f.write_string("{\"raw\":" + u64_to_string(raw) + ",\"name\":null}")
        }
      @codec.Bits(raw) =>
        f.write_string("{\"raw\":" + u64_to_string(raw) + ",\"bits\":true}")
      @codec.Text(s) => f.write_string("{\"text\":" + json_string(s) + "}")
      @codec.Bytes(b) =>
        f.write_string("{\"hex\":" + json_string(@pgn.payload_hex(b)) + "}")
    }
  }
  ("{" + f.to_string() + "}", "{" + rf.to_string() + "}")
}

///|
fn decode_data_json(
  msg : @message.Message,
  reg : @registry.Registry,
) -> String raise @protocol.ProtocolError {
  let transport = match msg.transport {
    @message.SingleFrame => "single-frame"
    @message.FastPacket => "fast-packet"
  }
  match reg.decode(msg) {
    Known(pgn~, name~, fields~) => {
      let (fjson, rfjson) = field_json(fields)
      "{\"pgn\":" +
      pgn.to_string() +
      ",\"name\":" +
      json_string(name) +
      ",\"transport\":\"" +
      transport +
      "\",\"payload_hex\":\"" +
      @pgn.payload_hex(msg.payload) +
      "\",\"fields\":" +
      fjson +
      ",\"raw_fields\":" +
      rfjson +
      "}"
    }
    Unknown(original) =>
      // Unknown PGN passthrough: report identity, no field decode.
      "{\"pgn\":" +
      original.pgn.value.to_string() +
      ",\"name\":null,\"transport\":\"" +
      transport +
      "\",\"payload_hex\":\"" +
      @pgn.payload_hex(original.payload) +
      "\",\"fields\":{},\"raw_fields\":{},\"unknown\":true}"
  }
}

///|
/// Shared flag parsing for decode-style commands.
fn extract_hex(flags : Map[String, String], key : String) -> String? {
  flags.get(key)
}

///|
/// `decode --pgn <n> --hex <hex> [--json]` (plan CLI-002, 25.4).
fn run_decode(args : Array[String]) -> Output {
  let (flags, _) = parse_flags(args, 1)
  let pgn_text = match extract_hex(flags, "--pgn") {
    Some(v) => v
    None => return usage_error("decode", "missing --pgn <n>")
  }
  let hex_text = match extract_hex(flags, "--hex") {
    Some(v) => v
    None => return usage_error("decode", "missing --hex <hex>")
  }
  let pgn_value = parse_int(pgn_text)
  match pgn_value {
    None =>
      return input_error(
        "decode",
        "InvalidInput",
        "cannot parse --pgn value '" + pgn_text + "'",
      )
    Some(pgn) => {
      let reg = @pgn.default_registry()
      match reg.lookup(pgn) {
        None => {
          // Unknown PGN: still decodable as passthrough; need an id.
          let id = attempt(fn() raise @protocol.ProtocolError {
            @identifier.CanId::make(
              priority=6,
              data_page=pgn >> 16,
              pdu_format=(pgn >> 8) & 0xFF,
              pdu_specific=pgn & 0xFF,
              source=0,
            )
          })
          match id {
            Some(i) =>
              run_decode_payload(
                "decode",
                i,
                hex_text,
                flags.contains("--json"),
              )
            None =>
              return input_error("decode", "InvalidInput", "PGN out of range")
          }
        }
        Some(meta) => {
          let id = attempt(fn() raise @protocol.ProtocolError {
            meta.make_can_id(source=0)
          })
          match id {
            Some(i) =>
              run_decode_payload(
                "decode",
                i,
                hex_text,
                flags.contains("--json"),
              )
            None =>
              return usage_error("decode", "cannot build identifier for PGN")
          }
        }
      }
    }
  }
}

///|
/// Decode a payload against a fixed id; shared by decode and decode-frame.
fn run_decode_payload(
  command : String,
  id : @identifier.CanId,
  hex_text : String,
  json_mode : Bool,
) -> Output {
  let payload : Bytes? = attempt(fn() raise @protocol.ProtocolError {
    @frame.hex_to_bytes(hex_text)
  })
  match payload {
    None =>
      return input_error(
        command, "InvalidHex", "payload is not valid hexadecimal",
      )
    Some(data) => {
      let transport = if data.length() <= 8 {
        @message.SingleFrame
      } else {
        @message.FastPacket
      }
      let msg : @message.Message? = attempt(fn() raise @protocol.ProtocolError {
        @message.Message::make(
          id,
          data,
          transport~,
          source_frame_count=if data.length() <= 8 {
            1
          } else {
            @fast_packet.frame_count_for(data.length())
          },
        )
      })
      match msg {
        Some(m) => {
          let reg = @pgn.default_registry()
          let data_json : String? = attempt(fn() raise @protocol.ProtocolError {
            decode_data_json(m, reg)
          })
          match data_json {
            Some(d) =>
              if json_mode {
                ok_json(command, d)
              } else {
                ok_text(human_decode(d))
              }
            None =>
              {
                exit_code: EXIT_PROTOCOL,
                stdout: "",
                stderr: envelope_err(
                  command, "DecodeError", "payload does not satisfy the PGN layout",
                ) +
                "\n",
              }
          }
        }
        None =>
          {
            exit_code: EXIT_PROTOCOL,
            stdout: "",
            stderr: envelope_err(
              command, "InvalidFrameLength", "payload length violates the transport rules",
            ) +
            "\n",
          }
      }
    }
  }
}

///|
/// One-line human rendering of the decode JSON (stable field order).
fn human_decode(data_json : String) -> String {
  // The JSON is the contract; the human output is a compacted view.
  data_json
}

///|
/// `decode-frame --id <hex> --data <hex> [--json]` (plan CLI-003).
fn run_decode_frame(args : Array[String]) -> Output {
  let (flags, _) = parse_flags(args, 1)
  let id_text = match extract_hex(flags, "--id") {
    Some(v) => v
    None => return usage_error("decode-frame", "missing --id <hex>")
  }
  let data_text = match extract_hex(flags, "--data") {
    Some(v) => v
    None => return usage_error("decode-frame", "missing --data <hex>")
  }
  let raw : UInt32? = parse_hex_uint(id_text)
  match raw {
    None =>
      input_error(
        "decode-frame",
        "InvalidHex",
        "cannot parse --id '" + id_text + "'",
      )
    Some(raw_value) => {
      let id : @identifier.CanId? = attempt(fn() raise @protocol.ProtocolError {
        @identifier.CanId::from_raw(raw_value)
      })
      match id {
        Some(i) =>
          run_decode_payload(
            "decode-frame",
            i,
            data_text,
            flags.contains("--json"),
          )
        None =>
          {
            exit_code: EXIT_PROTOCOL,
            stdout: "",
            stderr: envelope_err(
              "decode-frame", "InvalidCanId", "identifier outside the 29-bit range",
            ) +
            "\n",
          }
      }
    }
  }
}

///|
/// `fast-send --id <hex> --hex <hex> [--sequence <n>] [--json]` (CLI-004).
fn run_fast_send(args : Array[String]) -> Output {
  let (flags, _) = parse_flags(args, 1)
  let id_text = match extract_hex(flags, "--id") {
    Some(v) => v
    None => return usage_error("fast-send", "missing --id <hex>")
  }
  let hex_text = match extract_hex(flags, "--hex") {
    Some(v) => v
    None => return usage_error("fast-send", "missing --hex <hex>")
  }
  let sequence = match flags.get("--sequence") {
    Some(s) =>
      match parse_int(s) {
        Some(n) => n
        None =>
          return input_error(
            "fast-send",
            "InvalidInput",
            "cannot parse --sequence '" + s + "'",
          )
      }
    None => 0
  }
  let raw : UInt32? = parse_hex_uint(id_text)
  match raw {
    None =>
      input_error(
        "fast-send",
        "InvalidHex",
        "cannot parse --id '" + id_text + "'",
      )
    Some(raw_value) => {
      let id : @identifier.CanId? = attempt(fn() raise @protocol.ProtocolError {
        @identifier.CanId::from_raw(raw_value)
      })
      match id {
        None =>
          {
            exit_code: EXIT_PROTOCOL,
            stdout: "",
            stderr: envelope_err(
              "fast-send", "InvalidCanId", "identifier outside the 29-bit range",
            ) +
            "\n",
          }
        Some(i) => {
          let payload : Bytes? = attempt(fn() raise @protocol.ProtocolError {
            @frame.hex_to_bytes(hex_text)
          })
          match payload {
            None =>
              input_error(
                "fast-send", "InvalidHex", "payload is not valid hexadecimal",
              )
            Some(p) => {
              let frames : Array[@frame.CanFrame]? = attempt(fn() raise @protocol.ProtocolError {
                @fast_packet.segment(i, p, sequence)
              })
              match frames {
                None =>
                  {
                    exit_code: EXIT_PROTOCOL,
                    stdout: "",
                    stderr: envelope_err(
                      "fast-send", "FastPacketError", "payload cannot be segmented (needs 9..223 bytes, sequence 0..7)",
                    ) +
                    "\n",
                  }
                Some(fs) => {
                  let data = fast_send_json(i, p, sequence, fs)
                  if flags.contains("--json") {
                    ok_json("fast-send", data)
                  } else {
                    let lines = StringBuilder()
                    for fr in fs {
                      lines.write_string(
                        pad8(fr.id.to_raw()) +
                        " " +
                        @pgn.payload_hex(fr.data) +
                        "\n",
                      )
                    }
                    ok_text(lines.to_string())
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

///|
fn fast_send_json(
  id : @identifier.CanId,
  payload : Bytes,
  sequence : Int32,
  frames : Array[@frame.CanFrame],
) -> String {
  let out = StringBuilder()
  out.write_string(
    "{\"pgn\":" +
    id.pgn().value.to_string() +
    ",\"payload_length\":" +
    payload.length().to_string() +
    ",\"sequence_id\":" +
    sequence.to_string() +
    ",\"frame_count\":" +
    frames.length().to_string() +
    ",\"frames\":[",
  )
  for i, fr in frames {
    if i > 0 {
      out.write_string(",")
    }
    out.write_string(
      "{\"index\":" +
      i.to_string() +
      ",\"can_id\":\"" +
      pad8(fr.id.to_raw()) +
      "\",\"data_hex\":\"" +
      @pgn.payload_hex(fr.data) +
      "\"}",
    )
  }
  out.write_string("]}")
  out.to_string()
}

///|
fn parse_int(text : String) -> Int32? {
  if text.length() == 0 {
    return None
  }
  let mut value = 0
  let mut i = 0
  let neg = text.at(0) == 45
  if neg {
    i = 1
  }
  while i < text.length() {
    let c = text.at(i).to_int()
    if c < 48 || c > 57 {
      return None
    }
    value = value * 10 + (c - 48)
    i = i + 1
  }
  Some(if neg { -value } else { value })
}

///|
/// `simulate --scenario basic [--step <ms>] [--json]` (CLI-005, 25.6).
fn run_simulate(args : Array[String]) -> Output {
  let (flags, positional) = parse_flags(args, 1)
  let scenario = match flags.get("--scenario") {
    Some(s) => s
    None => if positional.length() > 0 { positional[0] } else { "basic" }
  }
  let step = match flags.get("--step") {
    Some(s) =>
      match parse_int(s) {
        Some(n) => n
        None =>
          return input_error(
            "simulate",
            "InvalidInput",
            "cannot parse --step '" + s + "'",
          )
      }
    None => 100
  }
  match @simulator.run_scenario(scenario, step_ms=step) {
    None =>
      usage_error(
        "simulate",
        "unknown scenario '" + scenario + "' (available: basic)",
      )
    Some(result) => {
      let frames : Array[@simulator.SimFrame]? = attempt(fn() raise @protocol.ProtocolError {
        result.to_frames()
      })
      match frames {
        None =>
          {
            exit_code: EXIT_PROTOCOL,
            stdout: "",
            stderr: envelope_err(
              "simulate", "SimulateError", "scenario frames could not be generated",
            ) +
            "\n",
          }
        Some(fs) => {
          let data = simulate_json(result, fs)
          if flags.contains("--json") {
            ok_json("simulate", data)
          } else {
            let lines = StringBuilder()
            for f in fs {
              lines.write_string(
                f.at_ms.to_string() +
                "ms " +
                pad8(f.frame.id.to_raw()) +
                " " +
                @pgn.payload_hex(f.frame.data) +
                "\n",
              )
            }
            ok_text(lines.to_string())
          }
        }
      }
    }
  }
}

///|
fn simulate_json(
  result : @simulator.SimResult,
  frames : Array[@simulator.SimFrame],
) -> String {
  let info = result.info()
  let last_ms = match frames.length() {
    0 => 0
    _ => frames[frames.length() - 1].at_ms
  }
  let out = StringBuilder()
  out.write_string(
    "{\"scenario\":" +
    json_string(info.name) +
    ",\"duration_ms\":" +
    last_ms.to_string() +
    ",\"frame_count\":" +
    frames.length().to_string() +
    ",\"frames\":[",
  )
  for i, f in frames {
    if i > 0 {
      out.write_string(",")
    }
    out.write_string(
      "{\"at_ms\":" +
      f.at_ms.to_string() +
      ",\"can_id\":\"" +
      pad8(f.frame.id.to_raw()) +
      "\",\"data_hex\":\"" +
      @pgn.payload_hex(f.frame.data) +
      "\"}",
    )
  }
  out.write_string("],\"messages\":[")
  for i, e in result.entries() {
    if i > 0 {
      out.write_string(",")
    }
    out.write_string(
      "{\"at_ms\":" +
      e.at_ms.to_string() +
      ",\"pgn\":" +
      e.message.pgn.value.to_string() +
      ",\"payload_hex\":\"" +
      @pgn.payload_hex(e.message.payload) +
      "\"}",
    )
  }
  out.write_string("]}")
  out.to_string()
}

///|
/// `selftest [--json]` (CLI-006): internal consistency checks only, no
/// fixtures, no I/O. Exit code 6 when a check fails (plan 25.8).
fn run_selftest(args : Array[String]) -> Output {
  let (flags, _) = parse_flags(args, 1)
  let checks : Array[(String, Bool)] = [
    ("can-id-roundtrip", selftest_can_id()),
    ("hex-roundtrip", selftest_hex()),
    ("fast-packet-roundtrip", selftest_fast_packet()),
    ("pgn-roundtrip", selftest_pgn()),
  ]
  let mut all_ok = true
  for pair in checks {
    if !pair.1 {
      all_ok = false
    }
  }
  if flags.contains("--json") {
    let out = StringBuilder()
    out.write_string("{\"checks\":[")
    for i, pair in checks {
      if i > 0 {
        out.write_string(",")
      }
      out.write_string(
        "{\"name\":" +
        json_string(pair.0) +
        ",\"ok\":" +
        pair.1.to_string() +
        "}",
      )
    }
    out.write_string("],\"ok\":" + all_ok.to_string() + "}")
    if all_ok {
      ok_json("selftest", out.to_string())
    } else {
      {
        exit_code: EXIT_SELFTEST,
        stdout: envelope_ok("selftest", out.to_string()) + "\n",
        stderr: "",
      }
    }
  } else {
    let lines = StringBuilder()
    for pair in checks {
      lines.write_string(
        pair.0 + ": " + (if pair.1 { "ok" } else { "FAIL" }) + "\n",
      )
    }
    if all_ok {
      ok_text(lines.to_string() + "selftest ok")
    } else {
      {
        exit_code: EXIT_SELFTEST,
        stdout: lines.to_string(),
        stderr: envelope_err(
          "selftest", "SelftestFailed", "one or more checks failed",
        ) +
        "\n",
      }
    }
  }
}

///|
fn selftest_can_id() -> Bool {
  let samples = [0U, 0x1FFFFFFFU, 0x18EAFFFEU, 0x19F80196U, 0x1A000055U]
  for raw in samples {
    let first = attempt(fn() raise @protocol.ProtocolError {
      @identifier.CanId::from_raw(raw)
    })
    match first {
      Some(id) => {
        let second = attempt(fn() raise @protocol.ProtocolError {
          @identifier.CanId::from_raw(id.to_raw())
        })
        match second {
          Some(id2) => if id2 != id { return false }
          None => return false
        }
      }
      None => return false
    }
  }
  true
}

///|
fn selftest_hex() -> Bool {
  let samples = ["", "00", "deadbeef", "0011223344556677"]
  for s in samples {
    let bytes = attempt(fn() raise @protocol.ProtocolError {
      @frame.hex_to_bytes(s)
    })
    match bytes {
      Some(b) => if @frame.bytes_to_hex(b) != s { return false }
      None => return false
    }
  }
  true
}

///|
fn selftest_fast_packet() -> Bool {
  let reg = @pgn.default_registry()
  match reg.lookup(@pgn.PGN_PRODUCT_INFO) {
    Some(meta) => {
      let payload = Bytes::makei(134, fn(i) { (i * 13 + 7).to_byte() })
      let seg = attempt(fn() raise @protocol.ProtocolError {
        @fast_packet.segment(meta.make_can_id(source=36), payload, 3)
      })
      match seg {
        Some(frames) => {
          let re = @fast_packet.FastPacketReassembler::new(
            @fast_packet.ReassemblyConfig::default(),
          )
          let mut completed : Bytes? = None
          let mut now = 0
          for f in frames {
            now = now + 5
            match re.ingest(f, now) {
              @fast_packet.Completed(m) => completed = Some(m.payload)
              _ => ()
            }
          }
          match completed {
            Some(p) => @pgn.payload_hex(p) == @pgn.payload_hex(payload)
            None => false
          }
        }
        None => false
      }
    }
    None => false
  }
}

///|
fn selftest_pgn() -> Bool {
  let reg = @pgn.default_registry()
  match reg.lookup(@pgn.PGN_VESSEL_HEADING) {
    Some(meta) => {
      let fields : Array[(String, @codec.FieldValue)] = [
        ("SID", @codec.Unsigned(66UL)),
        ("Heading", @codec.Unsigned(15708UL)),
        ("Deviation", @codec.Signed(0L)),
        ("Variation", @codec.Signed(25L)),
        ("Reference", @codec.Lookup(1UL, None)),
        ("Reserved (bits 58..64)", @codec.Bits(0UL)),
      ]
      let enc = attempt(fn() raise @protocol.ProtocolError {
        reg.encode_fields(meta, fields)
      })
      match enc {
        Some(payload) => {
          let id : @identifier.CanId? = attempt(fn() raise @protocol.ProtocolError {
            meta.make_can_id(source=36)
          })
          match id {
            Some(i) => {
              let msg : @message.Message? = attempt(fn() raise @protocol.ProtocolError {
                @message.Message::make(
                  i,
                  payload,
                  transport=@message.SingleFrame,
                  source_frame_count=1,
                )
              })
              match msg {
                Some(m) => {
                  let decoded : @registry.DecodedMessage? = attempt(fn() raise @protocol.ProtocolError {
                    reg.decode(m)
                  })
                  match decoded {
                    Some(Known(pgn=_, ..)) => true
                    _ => false
                  }
                }
                None => false
              }
            }
            None => false
          }
        }
        None => false
      }
    }
    None => false
  }
}
