// Fast Packet sender: segment a 9..223 byte payload into CAN frames
// (plan sections 3.3, 5.8, T05).
//
// Frame layout:
//   first frame:  byte0 = seq<<5 | 0, byte1 = declared length, bytes 2..7
//                 carry the first 6 payload bytes
//   later frames: byte0 = seq<<5 | frame_counter (1..31), bytes 1..7 carry
//                 up to 7 payload bytes
//
// The final frame is padded to 8 bytes with 0xFF. Padding value is an
// engineering choice aligned with common reference implementations, NOT a
// standard mandate; receivers derive valid bytes from the declared length,
// so the padding never leaks into decoded payloads.

///|
/// Build the transport byte from sequence id (3 bits) and frame counter
/// (5 bits).
fn transport_byte(sequence_id : Int32, frame_counter : Int32) -> Byte {
  ((sequence_id << 5) | frame_counter).to_byte()
}

///|
/// Compute the Fast Packet frame count for a declared payload length
/// (9..223): one first frame (6 bytes) plus ceil((len-6)/7) later frames.
pub fn frame_count_for(declared_length : Int32) -> Int32 {
  1 + (declared_length - 6 + 6) / 7
}

///|
/// Segment a payload into Fast Packet frames.
///
/// Payloads of 0..8 bytes are rejected here by design: they belong on the
/// single-frame path and the caller decides (plan 5.8). Payloads over 223
/// bytes exceed the Fast Packet capacity. `sequence_id` must be 0..7.
pub fn segment(
  id : @identifier.CanId,
  payload : Bytes,
  sequence_id : Int32,
) -> Array[@frame.CanFrame] raise @protocol.ProtocolError {
  let len = payload.length()
  if len <= @frame.MAX_FRAME_DATA {
    raise @protocol.InvalidFastPacketLength(
      declared=len,
      reason="payload 0..8 bytes belongs on the single-frame path",
    )
  }
  if len > @message.FAST_PACKET_MAX {
    raise @protocol.PayloadTooLarge(length=len, limit=@message.FAST_PACKET_MAX)
  }
  if sequence_id < 0 || sequence_id > 7 {
    raise @protocol.InvalidFieldValue(
      pgn=id.pgn().value,
      field="sequence_id",
      reason="sequence id must be 0..7",
    )
  }
  let frames : Array[@frame.CanFrame] = []
  // First frame: seq|0, declared length, first 6 payload bytes.
  let first = Bytes::makei(8, fn(i) {
    if i == 0 {
      transport_byte(sequence_id, 0)
    } else if i == 1 {
      len.to_byte()
    } else {
      payload.at(i - 2)
    }
  })
  frames.push(@frame.CanFrame::make(id, first))
  // Later frames: seq|counter, up to 7 payload bytes, 0xFF padding.
  let later_count = frame_count_for(len) - 1
  for f in 1..<=later_count {
    let start = 6 + (f - 1) * 7
    let end = if start + 7 > len { len } else { start + 7 }
    frames.push(
      @frame.CanFrame::make(
        id,
        Bytes::makei(8, fn(i) {
          if i == 0 {
            transport_byte(sequence_id, f)
          } else if i - 1 < end - start {
            payload.at(start + i - 1)
          } else {
            b'\xff'
          }
        }),
      ),
    )
  }
  frames
}
