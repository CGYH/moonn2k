// Message model tests.

///|
/// Transport enum is a plain value; Message bounds constants match plan 3.3.
test "message constants and transport" {
  assert_eq(@message.FAST_PACKET_MIN, 9)
  assert_eq(@message.FAST_PACKET_MAX, 223)
  assert_eq(@message.FAST_PACKET_MAX_FRAMES, 32)
  let t : @message.Transport = @message.SingleFrame
  assert_eq(t, @message.SingleFrame)
  let t2 : @message.Transport = @message.FastPacket
  assert_eq(t2, @message.FastPacket)
}

///|
/// Message::make validates payload bounds per transport and derives the PGN.
test "message make validates bounds" {
  let id = @identifier.CanId::from_raw(0x19F80196U)
  let payload9 = Bytes::makei(9, fn(_i) { b'\x01' })
  let m = @message.Message::make(
    id,
    payload9,
    transport=@message.FastPacket,
    source_frame_count=2,
  )
  assert_eq(m.pgn.value, 129025)
  assert_eq(m.payload.length(), 9)
  let single = @message.Message::make(
    id,
    b"\x01\x02",
    transport=@message.SingleFrame,
    source_frame_count=1,
  )
  assert_eq(single.source_frame_count, 1)
  // Out-of-bounds payloads are rejected per transport.
  let mut rejected = 0
  try {
    let _ignored = @message.Message::make(
      id,
      b"\x01",
      transport=@message.FastPacket,
      source_frame_count=1,
    )
  } catch {
    @protocol.InvalidFrameLength(..) => rejected = rejected + 1
    _ => ()
  }
  try {
    let _ignored = @message.Message::make(
      id,
      payload9,
      transport=@message.SingleFrame,
      source_frame_count=1,
    )
  } catch {
    @protocol.InvalidFrameLength(..) => rejected = rejected + 1
    _ => ()
  }
  assert_eq(rejected, 2)
}
