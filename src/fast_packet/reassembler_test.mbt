// Fast Packet reassembler tests (plan section 8.4, FPR-001..FPR-026).

///|
/// Re-ingest helper: feed frames in order, advancing virtual time by 10 ms
/// per frame, and collect the events.
fn ingest_all(
  re : @fast_packet.FastPacketReassembler,
  frames : Array[@frame.CanFrame],
  start_ms : Int32,
) -> Array[@fast_packet.ReassemblyEvent] {
  let events : Array[@fast_packet.ReassemblyEvent] = []
  let mut now = start_ms
  for frame in frames {
    now = now + 10
    events.push(re.ingest(frame, now))
  }
  events
}

///|
fn find_completed(
  events : Array[@fast_packet.ReassemblyEvent],
) -> @message.Message? {
  for e in events {
    match e {
      Completed(m) => return Some(m)
      _ => ()
    }
  }
  None
}

///|
fn count_completed(events : Array[@fast_packet.ReassemblyEvent]) -> Int32 {
  let mut n = 0
  for e in events {
    match e {
      Completed(_) => n = n + 1
      _ => ()
    }
  }
  n
}

///|
fn is_rejected(e : @fast_packet.ReassemblyEvent) -> Bool {
  match e {
    Rejected(_) => true
    _ => false
  }
}

///|
fn is_ignored(e : @fast_packet.ReassemblyEvent) -> Bool {
  match e {
    IgnoredDuplicate(_) => true
    _ => false
  }
}

///|
fn is_accepted(e : @fast_packet.ReassemblyEvent) -> Bool {
  match e {
    Accepted(_) => true
    _ => false
  }
}

///|
/// Hand-build one Fast Packet frame from raw parts.
fn make_frame(
  id : @identifier.CanId,
  sequence_id : Int32,
  frame_counter : Int32,
  body : Bytes,
) -> @frame.CanFrame raise @protocol.ProtocolError {
  let len = 1 + body.length()
  @frame.CanFrame::make(
    id,
    Bytes::makei(len, fn(i) {
      if i == 0 {
        ((sequence_id << 5) | frame_counter).to_byte()
      } else {
        body.at(i - 1)
      }
    }),
  )
}

///|
/// FPR-001: sequential delivery completes.
test "FPR-001 sequential completion" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(13)
  let frames = @fast_packet.segment(id, payload, 3)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let events = ingest_all(re, frames, 0)
  assert_eq(count_completed(events), 1)
  match find_completed(events) {
    Some(m) => {
      assert_eq(@frame.bytes_to_hex(m.payload), @frame.bytes_to_hex(payload))
      assert_eq(m.source_frame_count, 2)
      assert_eq(m.transport, @message.FastPacket)
    }
    None => fail("FPR-001: no completion")
  }
  assert_eq(re.session_count(), 0)
}

///|
/// FPR-002: reverse order (later frames first) still completes.
test "FPR-002 reverse order completion" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(13)
  let frames = @fast_packet.segment(id, payload, 3)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let reversed : Array[@frame.CanFrame] = []
  for i in 0..<frames.length() {
    reversed.push(frames[frames.length() - 1 - i])
  }
  let events = ingest_all(re, reversed, 0)
  assert_eq(count_completed(events), 1)
}

///|
/// FPR-003: middle frame last completes (3-frame transfer).
test "FPR-003 middle frame out of order" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(20)
  let frames = @fast_packet.segment(id, payload, 1)
  assert_eq(frames.length(), 3)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let order = [frames[0], frames[2], frames[1]]
  let events = ingest_all(re, order, 0)
  assert_eq(count_completed(events), 1)
}

///|
/// FPR-004: byte-identical duplicate frames are idempotent (no second
/// completion, no state corruption).
test "FPR-004 identical duplicates idempotent" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(13)
  let frames = @fast_packet.segment(id, payload, 3)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let events = ingest_all(re, frames, 0)
  assert_eq(count_completed(events), 1)
  let events2 = ingest_all(re, frames, 1000)
  assert_eq(count_completed(events2), 0)
  for e in events2 {
    assert_true(is_ignored(e))
  }
}

///|
/// FPR-005: same frame number with different payload conflicts and the
/// original data is not overwritten.
test "FPR-005 conflicting duplicate rejected" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(20)
  let frames = @fast_packet.segment(id, payload, 1)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let _ = ingest_all(re, [frames[0], frames[1]], 0)
  // Replay frame counter=1 with one payload byte changed.
  let corrupted = @frame.CanFrame::make(
    id,
    Bytes::makei(8, fn(i) {
      if i == 3 {
        b'\x7e'
      } else {
        frames[1].data.at(i)
      }
    }),
  )
  let mut conflict = false
  match re.ingest(corrupted, 20) {
    Rejected(ConflictingDuplicateFrame(..)) => conflict = true
    _ => fail("FPR-005: expected ConflictingDuplicateFrame")
  }
  assert_true(conflict)
  // The genuine final frame still completes with the original payload.
  let events = ingest_all(re, [frames[2]], 30)
  match find_completed(events) {
    Some(m) =>
      assert_eq(@frame.bytes_to_hex(m.payload), @frame.bytes_to_hex(payload))
    None => fail("FPR-005: original data lost after conflict")
  }
}

///|
/// FPR-006: later frames before the first frame are staged, then the first
/// frame completes the session.
test "FPR-006 missing first frame staging" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(13)
  let frames = @fast_packet.segment(id, payload, 3)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  // Later frame arrives first.
  let e1 = re.ingest(frames[1], 10)
  assert_true(is_accepted(e1))
  assert_eq(re.session_count(), 1)
  // First frame arrives and completes immediately.
  let e2 = re.ingest(frames[0], 20)
  match e2 {
    Completed(m) =>
      assert_eq(@frame.bytes_to_hex(m.payload), @frame.bytes_to_hex(payload))
    _ => fail("FPR-006: expected immediate completion after first frame")
  }
}

///|
/// FPR-007: a missing middle frame prevents completion until it arrives.
test "FPR-007 missing middle frame blocks completion" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(20)
  let frames = @fast_packet.segment(id, payload, 1)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let _ = ingest_all(re, [frames[0], frames[1]], 0)
  assert_eq(re.session_count(), 1)
  let events = ingest_all(re, [frames[2]], 100)
  assert_eq(count_completed(events), 1)
}

///|
/// FPR-008: extra frames beyond the declared geometry are rejected.
test "FPR-008 extra frame rejected" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(20)
  let frames = @fast_packet.segment(id, payload, 1)
  assert_eq(frames.length(), 3)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let _ = ingest_all(re, [frames[0], frames[1]], 0)
  // A fourth frame (counter 3) exceeds the declared geometry.
  let extra = make_frame(id, 1, 3, b"\x01\x02\x03\x04\x05\x06\x07")
  let event = re.ingest(extra, 100)
  assert_true(is_rejected(event))
}

///|
/// FPR-009: frame counter beyond the expected count is rejected.
test "FPR-009 frame counter out of range" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(13)
  let frames = @fast_packet.segment(id, payload, 3)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let _ = re.ingest(frames[0], 0)
  // Expected frames = 2, so counter 2 is out of range.
  let wild = make_frame(id, 3, 2, b"\x01\x02\x03\x04\x05\x06\x07")
  let event = re.ingest(wild, 10)
  assert_true(is_rejected(event))
}

///|
/// FPR-010: declared length 8 is rejected.
test "FPR-010 declared length 8 rejected" {
  let id = id_for(126996, 150)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let body = Bytes::makei(7, fn(i) { i.to_byte() })
  let frame = @frame.CanFrame::make(
    id,
    Bytes::makei(8, fn(i) {
      if i == 0 {
        b'\x00'
      } else if i == 1 {
        b'\x08'
      } else {
        body.at(i - 2)
      }
    }),
  )
  let event = re.ingest(frame, 0)
  assert_true(is_rejected(event))
}

///|
/// FPR-011: declared length 224 is rejected.
test "FPR-011 declared length 224 rejected" {
  let id = id_for(126996, 150)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let frame = @frame.CanFrame::make(
    id,
    Bytes::makei(8, fn(i) {
      if i == 0 {
        b'\x00'
      } else if i == 1 {
        b'\xe0'
      } else {
        b'\x11'
      }
    }),
  )
  let event = re.ingest(frame, 0)
  assert_true(is_rejected(event))
}

///|
/// FPR-012: a short first frame is rejected.
test "FPR-012 short first frame rejected" {
  let id = id_for(126996, 150)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let short = make_frame(id, 0, 0, b"\x09\x11\x22\x33")
  let event = re.ingest(short, 0)
  assert_true(is_rejected(event))
}

///|
/// FPR-013: a non-final frame carrying fewer than 7 payload bytes.
test "FPR-013 short non-final frame rejected" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(20)
  let frames = @fast_packet.segment(id, payload, 1)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let _ = re.ingest(frames[0], 0)
  // Frame 1 of 3 must carry 7 bytes; give it 4.
  let short = make_frame(id, 1, 1, b"\xaa\xbb\xcc\xdd")
  let event = re.ingest(short, 10)
  assert_true(is_rejected(event))
}

///|
/// FPR-014: a final frame shorter than the declared remainder is rejected.
test "FPR-014 short final frame rejected" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(20)
  let frames = @fast_packet.segment(id, payload, 1)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let _ = ingest_all(re, [frames[0], frames[1]], 0)
  // Final frame must carry 20 - 6 - 7 = 7 bytes; give it 3.
  let short = make_frame(id, 1, 2, b"\xaa\xbb\xcc")
  let event = re.ingest(short, 20)
  assert_true(is_rejected(event))
}

///|
/// FPR-015: sessions with different sources are isolated.
test "FPR-015 different sources isolated" {
  let id_a = id_for(126996, 10)
  let id_b = id_for(126996, 20)
  let payload = pattern_payload(13)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let frames_a = @fast_packet.segment(id_a, payload, 0)
  let frames_b = @fast_packet.segment(id_b, payload, 0)
  // Interleave: A first frame, B first frame, A last, B last.
  let e1 = re.ingest(frames_a[0], 10)
  assert_true(is_accepted(e1))
  let e2 = re.ingest(frames_b[0], 20)
  assert_true(is_accepted(e2))
  assert_eq(re.session_count(), 2)
  let events = ingest_all(re, [frames_a[1], frames_b[1]], 30)
  assert_eq(count_completed(events), 2)
}

///|
/// FPR-016: sessions with different PGNs are isolated.
test "FPR-016 different PGNs isolated" {
  let id_p1 = id_for(126996, 150)
  let id_p2 = id_for(130306, 150)
  let payload = pattern_payload(13)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let frames_p1 = @fast_packet.segment(id_p1, payload, 0)
  let frames_p2 = @fast_packet.segment(id_p2, payload, 0)
  let _ = re.ingest(frames_p1[0], 10)
  let _ = re.ingest(frames_p2[0], 20)
  assert_eq(re.session_count(), 2)
  let events = ingest_all(re, [frames_p1[1], frames_p2[1]], 30)
  assert_eq(count_completed(events), 2)
}

///|
/// FPR-017: sessions with different sequence ids are isolated.
test "FPR-017 different sequence ids isolated" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(13)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let frames_a = @fast_packet.segment(id, payload, 0)
  let frames_b = @fast_packet.segment(id, payload, 1)
  let _ = re.ingest(frames_a[0], 10)
  let _ = re.ingest(frames_b[0], 20)
  assert_eq(re.session_count(), 2)
  let events = ingest_all(re, [frames_a[1], frames_b[1]], 30)
  assert_eq(count_completed(events), 2)
}

///|
/// FPR-018: a different first frame on a live session restarts it; the old
/// transfer never completes with mixed data.
test "FPR-018 new first frame restarts session" {
  let id = id_for(126996, 150)
  let payload_a = pattern_payload(20)
  let payload_b = pattern_payload(13)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let frames_a = @fast_packet.segment(id, payload_a, 0)
  let frames_b = @fast_packet.segment(id, payload_b, 0)
  // Old transfer still incomplete: 2 of 3 frames received.
  let _ = ingest_all(re, [frames_a[0], frames_a[1]], 0)
  // Different declared length -> restart.
  let mut restarted = false
  match re.ingest(frames_b[0], 100) {
    Restarted(info) => {
      restarted = true
      assert_eq(info.frames_received, 2)
    }
    _ => fail("FPR-018: expected Restarted event")
  }
  assert_true(restarted)
  assert_eq(re.session_count(), 1)
  let events = ingest_all(re, [frames_b[1]], 110)
  match find_completed(events) {
    Some(m) =>
      assert_eq(@frame.bytes_to_hex(m.payload), @frame.bytes_to_hex(payload_b))
    None => fail("FPR-018: restarted session did not complete")
  }
}

///|
/// FPR-019: sessions expire exactly at the configured timeout, not before.
test "FPR-019 timeout expiry" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(13)
  let frames = @fast_packet.segment(id, payload, 3)
  let config : @fast_packet.ReassemblyConfig = {
    timeout_ms: 100,
    max_sessions: 32,
    max_staged_frames: 32,
    tombstone_capacity: 16,
  }
  let re = @fast_packet.FastPacketReassembler::new(config)
  let _ = re.ingest(frames[0], 1000)
  // At timeout-1 nothing expires.
  assert_eq(re.expire(1099).length(), 0)
  assert_eq(re.session_count(), 1)
  // At the timeout boundary the session expires.
  let expired = re.expire(1100)
  assert_eq(expired.length(), 1)
  assert_eq(expired[0].had_first_frame, true)
  assert_eq(expired[0].frames_received, 1)
  assert_eq(re.session_count(), 0)
}

///|
/// FPR-020: completion is reported at most once; replaying all frames after
/// completion yields no second Completed event.
test "FPR-020 completion at most once" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(13)
  let frames = @fast_packet.segment(id, payload, 3)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let events = ingest_all(re, frames, 0)
  assert_eq(count_completed(events), 1)
  let replay = ingest_all(re, frames, 1000)
  assert_eq(count_completed(replay), 0)
}

///|
/// FPR-021: hitting the session cap rejects new sessions without evicting
/// healthy ones.
test "FPR-021 session limit enforced" {
  let id_a = id_for(126996, 10)
  let id_b = id_for(126996, 20)
  let config : @fast_packet.ReassemblyConfig = {
    timeout_ms: 1000,
    max_sessions: 1,
    max_staged_frames: 32,
    tombstone_capacity: 16,
  }
  let re = @fast_packet.FastPacketReassembler::new(config)
  let frames_a = @fast_packet.segment(id_a, pattern_payload(13), 0)
  let frames_b = @fast_packet.segment(id_b, pattern_payload(13), 0)
  let _ = re.ingest(frames_a[0], 0)
  match re.ingest(frames_b[0], 10) {
    Rejected(SessionLimitExceeded(limit=1)) => ()
    _ => fail("FPR-021: expected SessionLimitExceeded")
  }
  // Original session survives.
  let events = ingest_all(re, [frames_a[1]], 20)
  assert_eq(count_completed(events), 1)
}

///|
/// FPR-022: a completed session releases its slot.
test "FPR-022 completed session released" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(13)
  let frames = @fast_packet.segment(id, payload, 3)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let _ = ingest_all(re, frames, 0)
  assert_eq(re.session_count(), 0)
  // A new transfer on the same key works after completion (tombstone only
  // suppresses byte-identical replay).
  let payload2 = pattern_payload(20)
  let frames2 = @fast_packet.segment(id, payload2, 3)
  let events = ingest_all(re, frames2, 100)
  assert_eq(count_completed(events), 1)
}

///|
/// FPR-023: clear() drops sessions and tombstones.
test "FPR-023 clear state" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(13)
  let frames = @fast_packet.segment(id, payload, 3)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let _ = ingest_all(re, frames, 0)
  re.clear()
  assert_eq(re.session_count(), 0)
  // After clear the tombstone is gone: identical replay starts a new
  // session (and completes again).
  let events = ingest_all(re, frames, 100)
  assert_eq(count_completed(events), 1)
}

///|
/// FPR-024: 223-byte boundary transfer end-to-end.
test "FPR-024 223-byte boundary" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(223)
  let frames = @fast_packet.segment(id, payload, 7)
  assert_eq(frames.length(), 32)
  let re = @fast_packet.FastPacketReassembler::new(
    @fast_packet.ReassemblyConfig::default(),
  )
  let events = ingest_all(re, frames, 0)
  match find_completed(events) {
    Some(m) =>
      assert_eq(@frame.bytes_to_hex(m.payload), @frame.bytes_to_hex(payload))
    None => fail("FPR-024: no completion")
  }
}

///|
/// FPR-025: staging without a first frame is bounded and rejected beyond
/// the cap.
test "FPR-025 bounded staging" {
  let id = id_for(126996, 150)
  let config : @fast_packet.ReassemblyConfig = {
    timeout_ms: 1000,
    max_sessions: 32,
    max_staged_frames: 2,
    tombstone_capacity: 16,
  }
  let re = @fast_packet.FastPacketReassembler::new(config)
  let _ = re.ingest(make_frame(id, 0, 1, b"\x01\x02\x03\x04\x05\x06\x07"), 10)
  let _ = re.ingest(make_frame(id, 0, 2, b"\x11\x12\x13\x14\x15\x16\x17"), 20)
  assert_eq(re.session_count(), 1)
  match re.ingest(make_frame(id, 0, 3, b"\x21\x22\x23\x24\x25\x26\x27"), 30) {
    Rejected(UnexpectedFastFrame(..)) => ()
    _ => fail("FPR-025: expected staging overflow rejection")
  }
}

///|
/// FPR-026: a completed transfer leaves a tombstone that suppresses the
/// identical first frame and its own late frames; the tombstone ages out.
test "FPR-026 tombstone suppresses late replay" {
  let id = id_for(126996, 150)
  let payload = pattern_payload(13)
  let frames = @fast_packet.segment(id, payload, 3)
  let config : @fast_packet.ReassemblyConfig = {
    timeout_ms: 100,
    max_sessions: 32,
    max_staged_frames: 32,
    tombstone_capacity: 16,
  }
  let re = @fast_packet.FastPacketReassembler::new(config)
  let _ = ingest_all(re, frames, 0)
  // Identical late replay: suppressed, no new session, no completion.
  let replay = ingest_all(re, frames, 50)
  assert_eq(count_completed(replay), 0)
  for e in replay {
    assert_true(is_ignored(e))
  }
  assert_eq(re.session_count(), 0)
  // Tombstone ages out at completed_ms + timeout.
  let expired = re.expire(120)
  let mut tombstone_gone = false
  for e in expired {
    if e.is_tombstone {
      tombstone_gone = true
    }
  }
  assert_true(tombstone_gone)
  // After the tombstone expires, the same transfer can complete again.
  let replay2 = ingest_all(re, frames, 200)
  assert_eq(count_completed(replay2), 1)
}
