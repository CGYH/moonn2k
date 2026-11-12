///|
/// Minimal decode example: explain one CAN ID and point at the payload
/// decode path.
fn main raise {
  let id = @identifier.CanId::from_raw(0x19F80196U)
  let pgn = id.pgn()
  println(
    "id 0x19F80196 -> pgn \{pgn.value} (PDU\{if id.is_pdu1() { 1 } else { 2 }}) source \{id.source()} priority \{id.priority()}",
  )
  println(
    "decode: moon run cmd/n2k --target native -- decode --pgn 129025 --hex 40a13120fa0cfbf9",
  )
}
