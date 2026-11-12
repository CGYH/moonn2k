// Non-fatal diagnostics (plan sections 5.6, 25.7).
//
// Lenient parsing and reassembly keep processing and attach findings here
// instead of failing. Diagnostics are structured so the CLI can render them
// deterministically (stable field order, no wall-clock or machine data).

///|
/// Severity of a non-fatal diagnostic finding.
#derive(@debug.Debug, Eq)
pub(all) enum DiagnosticSeverity {
  /// Purely informational (e.g. a note about the input form).
  Info
  /// Suspicious but accepted (e.g. reserved bit set in lenient mode).
  Warning
  /// Contradictory input was discarded, processing continued.
  Error
}

///|
/// Promote derived trait methods to regular methods (toolchain deprecates
/// implicit promotion).
pub extend DiagnosticSeverity with @debug.Debug::{to_repr}

///|
pub extend DiagnosticSeverity with Eq::{not_equal, equal}

///|
/// A single non-fatal finding.
#derive(@debug.Debug)
pub struct Diagnostic {
  /// Stable machine-readable code, e.g. "ReservedBitSet".
  code : String
  /// Severity of the finding.
  severity : DiagnosticSeverity
  /// Human-readable description without machine-specific data.
  message : String
  /// Ordered key/value context; constructors keep keys stable.
  context : Array[(String, String)]
}

///|
/// Promote the derived debug rendering to a regular method.
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
/// Construct a diagnostic.
pub fn Diagnostic::make(
  code : String,
  severity : DiagnosticSeverity,
  message : String,
  context~ : Array[(String, String)] = [],
) -> Diagnostic {
  { code, severity, message, context, }
}

///|
/// Render the context as a stable "k=v" list (used by tests and CLI output).
pub fn Diagnostic::context_string(self : Diagnostic) -> String {
  let parts : Array[String] = []
  for pair in self.context {
    parts.push(pair.0 + "=" + pair.1)
  }
  join_pairs(parts, "; ")
}

///|
/// Join strings with a separator (internal helper; core's String::from_array
/// has a different signature, so this is intentionally named differently).
fn join_pairs(items : Array[String], sep : String) -> String {
  let out = StringBuilder()
  for i, item in items {
    if i > 0 {
      out.write_string(sep)
    }
    out.write_string(item)
  }
  out.to_string()
}
