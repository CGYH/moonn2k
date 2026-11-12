// Stable JSON rendering helpers (plan section 25).
//
// Key order is fixed at the call sites, numbers are rendered without
// locale influence, and no machine-specific data ever enters the output.

///|
/// CLI/tool version reported in every JSON envelope.
pub const VERSION : String = "0.1.0"

///|
/// Format a double with fixed 6-decimal precision and no exponent
/// notation, so output is identical across targets.
pub fn format_double(v : Double) -> String {
  let neg = v < 0.0
  let a = if neg { -v } else { v }
  let scaled = (a * 1000000.0 + 0.5).to_int64()
  let whole = scaled / 1000000L
  let frac = scaled % 1000000L
  let frac_str = if frac == 0L {
    "000000"
  } else if frac < 10L {
    "00000" + frac.to_string()
  } else if frac < 100L {
    "0000" + frac.to_string()
  } else if frac < 1000L {
    "000" + frac.to_string()
  } else if frac < 10000L {
    "00" + frac.to_string()
  } else if frac < 100000L {
    "0" + frac.to_string()
  } else {
    frac.to_string()
  }
  (if neg { "-" } else { "" }) + whole.to_string() + "." + frac_str
}

///|
/// Render an unsigned 64-bit value as a decimal string. Values that may
/// exceed JSON safe integers are rendered by the caller as strings
/// (plan 25.4).
pub fn u64_to_string(v : UInt64) -> String {
  v.to_string()
}

///|
/// JSON string escape for a String value (quotes included).
pub fn json_string(s : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for ch in s {
    if ch == '"' {
      out.write_string("\\\"")
    } else if ch == '\\' {
      out.write_string("\\\\")
    } else if ch == '\n' {
      out.write_string("\\n")
    } else {
      out.write_char(ch)
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
/// Success envelope (plan 25.1).
pub fn envelope_ok(command : String, data_json : String) -> String {
  "{\"tool\":\"moonn2k\",\"version\":\"" +
  VERSION +
  "\",\"command\":" +
  json_string(command) +
  ",\"ok\":true,\"data\":" +
  data_json +
  ",\"diagnostics\":[]}"
}

///|
/// Error envelope (plan 25.2). Context entries keep insertion order.
pub fn envelope_err(
  command : String,
  code : String,
  message : String,
  context~ : Array[(String, String)] = [],
) -> String {
  let out = StringBuilder()
  out.write_string(
    "{\"tool\":\"moonn2k\",\"version\":\"" +
    VERSION +
    "\",\"command\":" +
    json_string(command) +
    ",\"ok\":false,\"error\":{\"code\":" +
    json_string(code) +
    ",\"message\":" +
    json_string(message),
  )
  if context.length() > 0 {
    out.write_string(",\"context\":{")
    for i, pair in context {
      if i > 0 {
        out.write_string(",")
      }
      out.write_string(json_string(pair.0) + ":" + json_string(pair.1))
    }
    out.write_string("}")
  }
  out.write_string("},\"diagnostics\":[]}")
  out.to_string()
}
