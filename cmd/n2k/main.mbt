///|
/// Native CLI entry: maps Output to stdout/stderr/exit-code (plan 7.8).
/// All logic lives in src/cli so it stays testable without spawning
/// processes.
fn main {
  let all = @env.args()
  let args : Array[String] = []
  // Drop the program name (argv[0]) when present.
  let start = if all.length() > 0 { 1 } else { 0 }
  for i in start..<all.length() {
    args.push(all[i])
  }
  let out = @cli.run(args)
  if out.stdout() != "" {
    println(out.stdout())
  }
  if out.stderr() != "" {
    eprintln(out.stderr())
  }
  if out.exit_code() != 0 {
    @env.exit(out.exit_code())
  }
}
