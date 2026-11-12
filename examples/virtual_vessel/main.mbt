///|
/// Deterministic virtual vessel: emit the basic scenario as scheduled
/// frames. Two runs print byte-identical output.
fn main raise {
  let result = @simulator.simulate_basic(step_ms=100)
  let frames = result.to_frames()
  println("scenario \{result.info().name}: \{frames.length()} frames")
  for f in frames {
    println(
      "\{f.at_ms}ms \{f.frame.id.to_raw()} \{@pgn.payload_hex(f.frame.data)}",
    )
  }
}
