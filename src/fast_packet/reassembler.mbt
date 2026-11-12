// Fast Packet reassembler: bounded, deterministic, injected clock
// (plan sections 3.3, 3.4, 5.7, T06/T07).
//
// Session key: (pgn, source, destination, sequence_id).
// States: AwaitingFirstFrame (later frames arrive first, bounded staging)
// and Active (first frame seen, declared length known).
//
// Fixed policies (T07):
//   identical duplicate frame      -> idempotent ignore with diagnostic
//   same frame number, other bytes -> ConflictingDuplicateFrame, no overwrite
//   new first frame on same key    -> session restart, old never completes
//   out-of-order frames            -> bounded buffer, complete when full set
//   timeout                        -> configuration, clock injected; the
//                                     default is a project choice, not a
//                                     standard constant
//   completion                     -> at most once; a bounded, expiring
//                                     tombstone suppresses late replay of
//                                     the same first frame

///|
/// Reassembler configuration (plan 3.4: every value is project policy).
#derive(@debug.Debug)
pub(all) struct ReassemblyConfig {
  /// Inactivity timeout in milliseconds. Project default 1000, NOT a
  /// standard constant (plan 3.4).
  timeout_ms : Int32
  /// Maximum concurrent sessions, including AwaitingFirstFrame staging.
  max_sessions : Int32
  /// Maximum staged later frames per AwaitingFirstFrame session (protocol
  /// maximum is 32 frames per transfer).
  max_staged_frames : Int32
  /// Maximum retained completion tombstones.
  tombstone_capacity : Int32
}

///|
pub extend ReassemblyConfig with @debug.Debug::{to_repr}

///|
/// Project-default configuration: 1000 ms timeout, 32 sessions, 32 staged
/// frames, 16 tombstones. Values are engineering choices (plan 3.4).
pub fn ReassemblyConfig::default() -> ReassemblyConfig {
  {
    timeout_ms: 1000,
    max_sessions: 32,
    max_staged_frames: 32,
    tombstone_capacity: 16,
  }
}

///|
/// Snapshot of a session's progress (also used for restart reports).
#derive(@debug.Debug)
pub(all) struct SessionInfo {
  pgn : Int32
  source : Int32
  destination : Int32?
  sequence_id : Int32
  frames_received : Int32
  /// None while the first frame has not been seen.
  expected_frames : Int32?
}

///|
pub extend SessionInfo with @debug.Debug::{to_repr}

///|
/// Report of a session removed by `expire`.
#derive(@debug.Debug)
pub(all) struct ExpiredSession {
  pgn : Int32
  source : Int32
  destination : Int32?
  sequence_id : Int32
  frames_received : Int32
  had_first_frame : Bool
  /// True when this entry is a completion tombstone ageing out.
  is_tombstone : Bool
}

///|
pub extend ExpiredSession with @debug.Debug::{to_repr}

///|
/// Outcome of ingesting one frame.
#derive(@debug.Debug)
pub enum ReassemblyEvent {
  /// Frame matched an already-received frame byte-for-byte.
  IgnoredDuplicate(@protocol.Diagnostic)
  /// Frame stored; session still incomplete.
  Accepted(SessionInfo)
  /// All frames present; payload reassembled exactly once.
  Completed(@message.Message)
  /// Frame violated a fixed policy; session state is unchanged.
  Rejected(@protocol.ProtocolError)
  /// A different first frame arrived on a live session; the old session
  /// was dropped and restarted. Carries the previous session's progress.
  Restarted(SessionInfo)
}

///|
pub extend ReassemblyEvent with @debug.Debug::{to_repr}

///|
#derive(Eq, Hash)
struct SessionKey {
  pgn : Int32
  source : Int32
  destination : Int32?
  sequence_id : Int32
}

///|
pub extend SessionKey with Eq::{not_equal, equal}

///|
pub extend SessionKey with Hash::{hash, hash_combine}

///|
struct Session {
  key : SessionKey
  /// Declared total length; -1 while awaiting the first frame.
  mut declared_length : Int32
  /// Expected frame count; -1 while awaiting the first frame.
  mut expected_frames : Int32
  /// Payload buffer; allocated once the first frame arrives.
  mut payload : FixedArray[Byte]
  /// Frame-present markers (length expected_frames when active).
  mut received : FixedArray[Bool]
  /// First frame's 6 payload bytes (kept for restart comparison).
  mut first_payload : Bytes
  /// Staged later frames while awaiting the first frame: (counter, chunk).
  staged : Array[(Int32, Bytes)]
  mut last_ms : Int32
}

///|
struct Tombstone {
  key : SessionKey
  /// Declared length and first-frame payload fingerprint: only the
  /// byte-identical transfer is suppressed by later replay.
  declared_length : Int32
  first_payload : Bytes
  completed_ms : Int32
}

///|
/// Fast Packet reassembler over injected time.
pub struct FastPacketReassembler {
  config : ReassemblyConfig
  sessions : Map[SessionKey, Session]
  tombstones : Array[Tombstone]
}

///|
/// Create a reassembler with the given configuration. Time is injected at
/// every call site (`now_ms`), never read from the system.
pub fn FastPacketReassembler::new(
  config : ReassemblyConfig,
) -> FastPacketReassembler {
  { config, sessions: Map([]), tombstones: [], }
}

///|
/// Number of live sessions (including AwaitingFirstFrame staging).
pub fn FastPacketReassembler::session_count(
  self : FastPacketReassembler,
) -> Int32 {
  self.sessions.length()
}

///|
/// Drop every session and tombstone (plan FPR-023).
pub fn FastPacketReassembler::clear(self : FastPacketReassembler) -> Unit {
  self.sessions.clear()
  self.tombstones.clear()
}

///|
/// Parse a frame's transport byte: (seq, counter), or None when the frame
/// is too short to carry one.
fn parse_transport(data : Bytes) -> (Int32, Int32)? {
  if data.length() < 1 {
    return None
  }
  let b0 = data.at(0).to_int()
  Some((b0 >> 5, b0 & 0x1F))
}

///|
fn key_of(id : @identifier.CanId, sequence_id : Int32) -> SessionKey {
  {
    pgn: id.pgn().value,
    source: id.source(),
    destination: id.destination(),
    sequence_id,
  }
}

///|
fn Session::session_info(self : Session) -> SessionInfo {
  {
    pgn: self.key.pgn,
    source: self.key.source,
    destination: self.key.destination,
    sequence_id: self.key.sequence_id,
    frames_received: self.count_received(),
    expected_frames: if self.expected_frames >= 0 {
      Some(self.expected_frames)
    } else {
      None
    },
  }
}

///|
fn Session::count_received(self : Session) -> Int32 {
  let mut n = 0
  for i in 0..<self.received.length() {
    if self.received[i] {
      n = n + 1
    }
  }
  n
}

///|
fn reject(
  reason : String,
  key : SessionKey,
  frame_index : Int32,
) -> ReassemblyEvent {
  ReassemblyEvent::Rejected(
    UnexpectedFastFrame(
      reason~,
      pgn=key.pgn,
      source=key.source,
      sequence_id=key.sequence_id,
      frame_index~,
    ),
  )
}

///|
fn fast_diagnostic(
  code : String,
  message : String,
  key : SessionKey,
  frame_index : Int32,
) -> @protocol.Diagnostic {
  @protocol.Diagnostic::make(code, Info, message, context=[
    ("pgn", key.pgn.to_string()),
    ("source", key.source.to_string()),
    ("sequence_id", key.sequence_id.to_string()),
    ("frame_index", frame_index.to_string()),
  ])
}

///|
fn Session::touch(self : Session, now_ms : Int32) -> Unit {
  self.last_ms = now_ms
}

///|
/// First-frame replay is suppressed only for the byte-identical transfer.
fn FastPacketReassembler::is_tombstoned_first(
  self : FastPacketReassembler,
  key : SessionKey,
  declared : Int32,
  first_payload : Bytes,
) -> Bool {
  for t in self.tombstones {
    if t.key == key &&
      t.declared_length == declared &&
      t.first_payload == first_payload {
      return true
    }
  }
  false
}

///|
/// Later frames carry no length fingerprint, so they are suppressed by key;
/// the tombstone's short lifetime bounds any collateral impact.
fn FastPacketReassembler::is_tombstoned_key(
  self : FastPacketReassembler,
  key : SessionKey,
) -> Bool {
  for t in self.tombstones {
    if t.key == key {
      return true
    }
  }
  false
}

///|
fn FastPacketReassembler::remember_tombstone(
  self : FastPacketReassembler,
  key : SessionKey,
  declared : Int32,
  first_payload : Bytes,
  now_ms : Int32,
) -> Unit {
  self.tombstones.push({
    key,
    declared_length: declared,
    first_payload,
    completed_ms: now_ms,
  })
  while self.tombstones.length() > self.config.tombstone_capacity {
    let _evicted = self.tombstones.remove(0)
  }
}

///|
fn expected_frames_for(declared : Int32) -> Int32 {
  frame_count_for(declared)
}

///|
/// Payload chunk carried by a later frame: data[1..], length 1..7.
fn later_chunk(data : Bytes) -> Bytes {
  Bytes::makei(data.length() - 1, fn(i) { data.at(i + 1) })
}

///|
/// Apply a later frame's payload into an active session buffer with
/// conflict detection. Returns Err(reason) on policy violation.
fn Session::store_later_payload(
  self : Session,
  frame_counter : Int32,
  chunk : Bytes,
) -> Result[Unit, String] {
  let fc = frame_counter
  if fc < 1 || fc >= self.expected_frames {
    return Err("frame counter out of range")
  }
  let is_last = fc == self.expected_frames - 1
  let expect_last = self.declared_length - 6 - (self.expected_frames - 2) * 7
  let chunk_len = if is_last { expect_last } else { 7 }
  if !is_last && chunk.length() != 7 {
    return Err("non-final frame must carry 7 payload bytes")
  }
  if chunk.length() < chunk_len {
    return Err("final frame shorter than declared remainder")
  }
  let start = 6 + (fc - 1) * 7
  for i in 0..<chunk_len {
    let b = chunk.at(i)
    if self.received[fc] && self.payload[start + i] != b {
      return Err("conflicting payload for stored frame")
    }
    self.payload[start + i] = b
  }
  self.received[fc] = true
  Ok(())
}

///|
/// Allocate a fresh AwaitingFirstFrame session.
fn new_session(key : SessionKey, now_ms : Int32) -> Session {
  {
    key,
    declared_length: -1,
    expected_frames: -1,
    payload: FixedArray::make(0, b'\x00'),
    received: FixedArray::make(0, false),
    first_payload: b"",
    staged: [],
    last_ms: now_ms,
  }
}

///|
/// Assemble and complete a session exactly once: remove the session and
/// record a tombstone (plan FPR-020/022/026).
fn FastPacketReassembler::complete_session(
  self : FastPacketReassembler,
  s : Session,
  id : @identifier.CanId,
  now_ms : Int32,
) -> ReassemblyEvent {
  let payload = Bytes::makei(s.declared_length, fn(i) { s.payload[i] })
  self.sessions.remove(s.key)
  self.remember_tombstone(s.key, s.declared_length, s.first_payload, now_ms)
  ReassemblyEvent::Completed({
    id,
    pgn: id.pgn(),
    payload,
    transport: @message.FastPacket,
    source_frame_count: s.expected_frames,
  })
}

///|
/// Transition a session into Active using a first frame, then fold in any
/// staged later frames. May complete immediately.
fn FastPacketReassembler::activate_session(
  self : FastPacketReassembler,
  s : Session,
  id : @identifier.CanId,
  declared : Int32,
  first_payload : Bytes,
  now_ms : Int32,
) -> ReassemblyEvent {
  let key = s.key
  if declared < @message.FAST_PACKET_MIN || declared > @message.FAST_PACKET_MAX {
    return reject("declared length outside 9..223", key, 0)
  }
  if first_payload.length() < 6 {
    return reject("first frame must carry 6 payload bytes", key, 0)
  }
  s.declared_length = declared
  s.expected_frames = expected_frames_for(declared)
  s.payload = FixedArray::make(declared, b'\xff')
  s.received = FixedArray::make(s.expected_frames, false)
  s.first_payload = first_payload
  s.received[0] = true
  for i in 0..<6 {
    s.payload[i] = first_payload.at(i)
  }
  // Fold staged frames in ascending frame counter order; invalid staged
  // frames are dropped (they were bounded while staging).
  let sorted = s.staged.copy()
  s.staged.clear()
  sorted.sort_by(fn(a, b) { a.0 - b.0 })
  for pair in sorted {
    let _r = s.store_later_payload(pair.0, pair.1)
  }
  s.touch(now_ms)
  if s.count_received() == s.expected_frames {
    return self.complete_session(s, id, now_ms)
  }
  ReassemblyEvent::Accepted(s.session_info())
}

///|
/// Handle a first frame (frame counter 0).
fn FastPacketReassembler::ingest_first(
  self : FastPacketReassembler,
  key : SessionKey,
  id : @identifier.CanId,
  data : Bytes,
  now_ms : Int32,
) -> ReassemblyEvent {
  if data.length() < 8 {
    return reject("first frame must be 8 bytes", key, 0)
  }
  let declared = data.at(1).to_int()
  let first_payload = Bytes::makei(6, fn(i) { data.at(2 + i) })
  // Late replay of a completed transfer: suppress via tombstone (FPR-026).
  if self.is_tombstoned_first(key, declared, first_payload) {
    return ReassemblyEvent::IgnoredDuplicate(
      fast_diagnostic(
        "TombstonedTransfer", "first frame matches a recently completed transfer",
        key, 0,
      ),
    )
  }
  match self.sessions.get(key) {
    Some(s) =>
      if s.expected_frames >= 0 {
        // Live active session: identical -> idempotent, else restart.
        if declared == s.declared_length && first_payload == s.first_payload {
          return ReassemblyEvent::IgnoredDuplicate(
            fast_diagnostic(
              "IgnoredDuplicate", "identical first frame ignored", key, 0,
            ),
          )
        }
        let previous = s.session_info()
        self.sessions.remove(key)
        let fresh = new_session(key, now_ms)
        let event = self.activate_session(
          fresh, id, declared, first_payload, now_ms,
        )
        match event {
          ReassemblyEvent::Rejected(_) => event
          _ => {
            let _ = self.sessions.set(key, fresh)
            ReassemblyEvent::Restarted(previous)
          }
        }
      } else {
        // AwaitingFirstFrame: this first frame activates the session.
        let event = self.activate_session(
          s, id, declared, first_payload, now_ms,
        )
        match event {
          ReassemblyEvent::Rejected(_) => {
            let _ = self.sessions.remove(key)
            event
          }
          ReassemblyEvent::Completed(_) => event
          _ => event
        }
      }
    None => {
      if self.sessions.length() >= self.config.max_sessions {
        return ReassemblyEvent::Rejected(
          SessionLimitExceeded(limit=self.config.max_sessions),
        )
      }
      let s = new_session(key, now_ms)
      let event = self.activate_session(s, id, declared, first_payload, now_ms)
      match event {
        ReassemblyEvent::Rejected(_) => event
        _ => {
          let _ = self.sessions.set(key, s)
          event
        }
      }
    }
  }
}

///|
/// Handle a later frame (frame counter >= 1).
fn FastPacketReassembler::ingest_later(
  self : FastPacketReassembler,
  key : SessionKey,
  id : @identifier.CanId,
  frame_counter : Int32,
  data : Bytes,
  now_ms : Int32,
) -> ReassemblyEvent {
  match self.sessions.get(key) {
    Some(s) =>
      if s.expected_frames >= 0 {
        return self.ingest_later_active(s, id, frame_counter, data, now_ms)
      } else {
        return self.ingest_later_staging(s, frame_counter, data, now_ms)
      }
    None => {
      // Tombstoned transfers swallow their own late frames (FPR-026).
      if self.is_tombstoned_key(key) {
        return ReassemblyEvent::IgnoredDuplicate(
          fast_diagnostic(
            "TombstonedTransfer", "later frame matches a recently completed transfer",
            key, frame_counter,
          ),
        )
      }
      if self.sessions.length() >= self.config.max_sessions {
        return ReassemblyEvent::Rejected(
          SessionLimitExceeded(limit=self.config.max_sessions),
        )
      }
      let s = new_session(key, now_ms)
      let _ = self.sessions.set(key, s)
      self.ingest_later_staging(s, frame_counter, data, now_ms)
    }
  }
}

///|
fn FastPacketReassembler::ingest_later_active(
  self : FastPacketReassembler,
  s : Session,
  id : @identifier.CanId,
  frame_counter : Int32,
  data : Bytes,
  now_ms : Int32,
) -> ReassemblyEvent {
  let key = s.key
  if frame_counter >= s.expected_frames {
    return reject(
      "frame counter beyond expected frame count", key, frame_counter,
    )
  }
  let chunk = later_chunk(data)
  let is_last = frame_counter == s.expected_frames - 1
  let expect_last = s.declared_length - 6 - (s.expected_frames - 2) * 7
  // Idempotency and conflict checks before any write.
  if s.received[frame_counter] {
    let start = 6 + (frame_counter - 1) * 7
    let len = if is_last { expect_last } else { 7 }
    let mut same = chunk.length() >= len
    if same {
      for i in 0..<len {
        if s.payload[start + i] != chunk.at(i) {
          same = false
          break
        }
      }
    }
    if same {
      return ReassemblyEvent::IgnoredDuplicate(
        fast_diagnostic(
          "IgnoredDuplicate", "identical frame ignored", key, frame_counter,
        ),
      )
    }
    return ReassemblyEvent::Rejected(
      ConflictingDuplicateFrame(
        pgn=key.pgn,
        source=key.source,
        sequence_id=key.sequence_id,
        frame_index=frame_counter,
      ),
    )
  }
  match s.store_later_payload(frame_counter, chunk) {
    Err(reason) => reject(reason, key, frame_counter)
    Ok(_) => {
      s.touch(now_ms)
      if s.count_received() == s.expected_frames {
        self.complete_session(s, id, now_ms)
      } else {
        ReassemblyEvent::Accepted(s.session_info())
      }
    }
  }
}

///|
fn FastPacketReassembler::ingest_later_staging(
  self : FastPacketReassembler,
  s : Session,
  frame_counter : Int32,
  data : Bytes,
  now_ms : Int32,
) -> ReassemblyEvent {
  let key = s.key
  // Bounded staging (plan FPR-025).
  if s.staged.length() >= self.config.max_staged_frames {
    return reject("staging buffer full", key, frame_counter)
  }
  let chunk = later_chunk(data)
  for pair in s.staged {
    if pair.0 == frame_counter {
      if pair.1 == chunk {
        return ReassemblyEvent::IgnoredDuplicate(
          fast_diagnostic(
            "IgnoredDuplicate", "identical staged frame ignored", key, frame_counter,
          ),
        )
      }
      return ReassemblyEvent::Rejected(
        ConflictingDuplicateFrame(
          pgn=key.pgn,
          source=key.source,
          sequence_id=key.sequence_id,
          frame_index=frame_counter,
        ),
      )
    }
  }
  s.staged.push((frame_counter, chunk))
  s.touch(now_ms)
  ReassemblyEvent::Accepted(s.session_info())
}

///|
/// Ingest one CAN frame at virtual time `now_ms`.
pub fn FastPacketReassembler::ingest(
  self : FastPacketReassembler,
  frame : @frame.CanFrame,
  now_ms : Int32,
) -> ReassemblyEvent {
  let data = frame.data
  match parse_transport(data) {
    None =>
      reject(
        "frame has no transport byte",
        SessionKey::make(pgn=0, source=0, destination=None, sequence_id=0),
        0,
      )
    Some((sequence_id, frame_counter)) => {
      let id = frame.id
      let key = key_of(id, sequence_id)
      if frame_counter == 0 {
        self.ingest_first(key, id, data, now_ms)
      } else {
        self.ingest_later(key, id, frame_counter, data, now_ms)
      }
    }
  }
}

///|
/// Expire sessions and tombstones whose inactivity age reached the
/// configured timeout, at virtual time `now_ms`. Returns what was removed.
pub fn FastPacketReassembler::expire(
  self : FastPacketReassembler,
  now_ms : Int32,
) -> Array[ExpiredSession] {
  let expired : Array[ExpiredSession] = []
  let dead_keys : Array[SessionKey] = []
  for key, s in self.sessions {
    if now_ms - s.last_ms >= self.config.timeout_ms {
      dead_keys.push(key)
      expired.push({
        pgn: key.pgn,
        source: key.source,
        destination: key.destination,
        sequence_id: key.sequence_id,
        frames_received: s.count_received(),
        had_first_frame: s.expected_frames >= 0,
        is_tombstone: false,
      })
    }
  }
  for key in dead_keys {
    let _ = self.sessions.remove(key)
  }
  let keep : Array[Tombstone] = []
  for t in self.tombstones {
    if now_ms - t.completed_ms >= self.config.timeout_ms {
      expired.push({
        pgn: t.key.pgn,
        source: t.key.source,
        destination: t.key.destination,
        sequence_id: t.key.sequence_id,
        frames_received: 0,
        had_first_frame: true,
        is_tombstone: true,
      })
    } else {
      keep.push(t)
    }
  }
  self.tombstones.clear()
  for t in keep {
    self.tombstones.push(t)
  }
  expired
}

///|
fn SessionKey::make(
  pgn~ : Int32,
  source~ : Int32,
  destination~ : Int32?,
  sequence_id~ : Int32,
) -> SessionKey {
  { pgn, source, destination, sequence_id, }
}
