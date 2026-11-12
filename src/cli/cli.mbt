// Command implementations (plan sections 7.8, 25; T12).
//
// Everything here is pure: argv-style arguments in, an Output value out.
// The cmd/n2k main only maps Output to stdout/stderr/exit-code.

///|
/// Exit codes (plan 25.8).
pub const EXIT_OK : Int32 = 0

///|
pub const EXIT_USAGE : Int32 = 2

///|
pub const EXIT_INPUT : Int32 = 3

///|
pub const EXIT_PROTOCOL : Int32 = 4

///|
pub const EXIT_SELFTEST : Int32 = 6

///|
/// Result of one command execution.
pub(all) struct Output {
  exit_code : Int32
  stdout : String
  stderr : String
}

///|
/// Output accessors.
pub fn Output::exit_code(self : Output) -> Int32 {
  self.exit_code
}

///|
pub fn Output::stdout(self : Output) -> String {
  self.stdout
}

///|
pub fn Output::stderr(self : Output) -> String {
  self.stderr
}

///|
fn ok_json(command : String, data : String) -> Output {
  { exit_code: EXIT_OK, stdout: envelope_ok(command, data) + "\n", stderr: "", }
}

///|
fn ok_text(text : String) -> Output {
  { exit_code: EXIT_OK, stdout: text + "\n", stderr: "", }
}

///|
fn usage_error(command : String, message : String) -> Output {
  {
    exit_code: EXIT_USAGE,
    stdout: "",
    stderr: envelope_err(command, "UsageError", message) + "\n",
  }
}

///|
fn input_error(command : String, code : String, message : String) -> Output {
  {
    exit_code: EXIT_INPUT,
    stdout: "",
    stderr: envelope_err(command, code, message) + "\n",
  }
}

///|
/// Run a protocol-raising operation, converting failure to None.
fn[T] attempt(f : () -> T raise @protocol.ProtocolError) -> T? {
  Some(f()) catch {
    _ => None
  }
}

///|
/// Run one command from argv-style words (without the program name).
pub fn run(args : Array[String]) -> Output {
  if args.length() == 0 {
    return usage_error("", "missing command; try: help")
  }
  match args[0] {
    "id" => run_id(args)
    "decode" => run_decode(args)
    "decode-frame" => run_decode_frame(args)
    "fast-send" => run_fast_send(args)
    "simulate" => run_simulate(args)
    "selftest" => run_selftest(args)
    "help" | "--help" | "-h" => ok_text(help_text())
    other => usage_error(other, "unknown command '" + other + "'; try: help")
  }
}

///|
/// P0 command list (plan 7.8).
pub fn help_text() -> String {
  "moonn2k - NMEA 2000 protocol toolkit (P0 commands)\n" +
  "  id <hex>                                  explain a 29-bit CAN ID\n" +
  "  decode --pgn <n> --hex <hex> [--json]     decode a PGN payload\n" +
  "  decode-frame --id <hex> --data <hex>      decode one CAN frame\n" +
  "  fast-send --id <hex> --hex <hex> [--sequence <n>] [--json]\n" +
  "                                            segment a payload into Fast Packet frames\n" +
  "  simulate --scenario basic [--step <ms>] [--json]\n" +
  "                                            run the deterministic scenario\n" +
  "  selftest [--json]                         run internal consistency checks\n" +
  "  help                                      show this text"
}

///|
/// Flags: --name value pairs; positional arguments keep their order.
fn parse_flags(
  args : Array[String],
  start : Int32,
) -> (Map[String, String], Array[String]) {
  let flags : Map[String, String] = Map([])
  let positional : Array[String] = []
  let mut i = start
  while i < args.length() {
    let a = args[i]
    if a.length() > 2 && a.at(0) == 45 && a.at(1) == 45 {
      // --flag value
      if i + 1 < args.length() {
        let _ = flags.set(a, args[i + 1])
        i = i + 2
      } else {
        let _ = flags.set(a, "")
        i = i + 1
      }
    } else {
      positional.push(a)
      i = i + 1
    }
  }
  (flags, positional)
}

///|
/// Canonical hex rendering of the ID: 0x + 8 uppercase-free lowercase hex.
fn id_json(id : @identifier.CanId) -> String {
  let pgn = id.pgn()
  let dest = match id.destination() {
    Some(d) => d.to_string()
    None => "null"
  }
  let pdu = if id.is_pdu1() { "PDU1" } else { "PDU2" }
  "{\"raw\":\"" +
  pad8(id.to_raw()) +
  "\",\"priority\":" +
  id.priority().to_string() +
  ",\"reserved\":" +
  (id.reserved_bit() == 1).to_string() +
  ",\"data_page\":" +
  id.data_page().to_string() +
  ",\"pdu_format\":" +
  id.pdu_format().to_string() +
  ",\"pdu_specific\":" +
  id.pdu_specific().to_string() +
  ",\"source\":" +
  id.source().to_string() +
  ",\"pgn\":" +
  pgn.value.to_string() +
  ",\"pdu\":\"" +
  pdu +
  "\",\"destination\":" +
  dest +
  "}"
}

///|
/// Zero-pad a UInt to 8 hex digits (lowercase, 0x prefix).
fn pad8(v : UInt32) -> String {
  let hex_chars = "0123456789abcdef"
  let out = StringBuilder()
  out.write_string("0x")
  for shift in [28, 24, 20, 16, 12, 8, 4, 0] {
    let nib = (v >> shift) & 0xFU
    match hex_chars.get_char(nib.reinterpret_as_int()) {
      Some(c) => out.write_char(c)
      None => out.write_char('?')
    }
  }
  out.to_string()
}

///|
/// `id <hex> [--json]` (plan CLI-001, 25.3).
fn run_id(args : Array[String]) -> Output {
  let (flags, positional) = parse_flags(args, 1)
  if positional.length() < 1 {
    return usage_error("id", "missing CAN ID argument")
  }
  let text = positional[0]
  let value : UInt32? = parse_hex_uint(text)
  match value {
    None =>
      return input_error(
        "id",
        "InvalidHex",
        "cannot parse '" + text + "' as a hexadecimal CAN ID",
      )
    Some(raw) => {
      let id : @identifier.CanId? = attempt(fn() raise @protocol.ProtocolError {
        @identifier.CanId::from_raw(raw)
      })
      match id {
        Some(parsed) =>
          if flags.contains("--json") {
            ok_json("id", id_json(parsed))
          } else {
            let pgn = parsed.pgn()
            let dest = match parsed.destination() {
              Some(d) => " destination=" + d.to_string()
              None => ""
            }
            ok_text(
              "raw=" +
              pad8(parsed.to_raw()) +
              " priority=" +
              parsed.priority().to_string() +
              " data_page=" +
              parsed.data_page().to_string() +
              " pdu_format=" +
              parsed.pdu_format().to_string() +
              " pdu_specific=" +
              parsed.pdu_specific().to_string() +
              " source=" +
              parsed.source().to_string() +
              " pgn=" +
              pgn.value.to_string() +
              " pdu=" +
              (if parsed.is_pdu1() { "PDU1" } else { "PDU2" }) +
              dest,
            )
          }
        None =>
          return {
            exit_code: EXIT_PROTOCOL,
            stdout: "",
            stderr: envelope_err(
              "id",
              "InvalidCanId",
              "value outside the 29-bit extended identifier range",
              context=[("raw", text)],
            ) +
            "\n",
          }
      }
    }
  }
}

///|
/// Parse an optionally 0x-prefixed hex string into a UInt.
fn parse_hex_uint(text : String) -> UInt32? {
  let body = if text.length() > 2 && text.at(0) == 48 && text.at(1) == 120 {
    // strip 0x / 0X
    let mut sub = ""
    for i in 2..<text.length() {
      sub = sub + text.at(i).to_int().unsafe_to_char().to_string()
    }
    sub
  } else {
    text
  }
  let mut value : UInt32 = 0U
  let mut count = 0
  for ch in body {
    match hex_value(ch) {
      Some(v) => {
        value = (value << 4).lor(v.reinterpret_as_uint())
        count = count + 1
      }
      None => return None
    }
  }
  if count == 0 || count > 8 {
    None
  } else {
    Some(value)
  }
}

///|
fn hex_value(ch : Char) -> Int32? {
  if ch >= '0' && ch <= '9' {
    Some(ch.to_int() - 0x30)
  } else if ch >= 'a' && ch <= 'f' {
    Some(ch.to_int() - 0x57)
  } else if ch >= 'A' && ch <= 'F' {
    Some(ch.to_int() - 0x37)
  } else {
    None
  }
}
