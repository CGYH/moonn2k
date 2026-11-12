# Protocol scope

## What P0 includes

- Extended 29-bit CAN ID parsing and construction: priority, reserved bit,
  data page, PDU format/specific, source address, PDU1/PDU2 split, PGN
  derivation (plan 3.2).
- Classic CAN frame model with a hard 0..8 byte invariant and a canonical
  hex codec (input: any case, space/colon separators; output: lowercase,
  compact).
- Bounded bit-level reader/writer (1..64 bit windows, LSB-first, signed and
  unsigned, structured bounds errors).
- Fast Packet sender: 9..223 byte payloads, first frame 6 bytes + declared
  length, later frames 7 bytes, 0xFF padding on short final frames
  (engineering choice), sequence ids 0..7, at most 32 frames.
- Fast Packet reassembler: session table keyed by
  `(pgn, source, destination, sequence_id)`, bounded staging without a
  first frame, idempotent duplicates, conflicting-duplicate rejection,
  restart on new first frame, injected clock, expiring completion
  tombstones, session and staging caps, at-most-once completion.
- Typed codecs for exactly ten PGNs (see the support matrix in the README):
  59904, 60928, 126992, 126993, 126996, 127250, 128267, 129025, 129026,
  130306.
- Registry-based routing: unknown PGNs pass through as data; known-PGN
  failures carry PGN and field context.
- Deterministic scenario simulator ("basic") and a native CLI with six
  commands and stable JSON envelopes.

## What P0 explicitly does not include

- No hardware, socket, file or wall-clock access in the core.
- No J1939 transport protocol (TP.BAM / TP.CM) beyond the NMEA 2000 Fast
  Packet variant.
- No proprietary PGN guesses: fields that could not be verified against the
  pinned canboat revision are not implemented.
- No repeating field groups (deferred; none of the ten P0 PGNs needs them).
- No multi-pair cable / network management beyond the two system PGNs listed.
- No performance claims: nothing here has been benchmarked against other
  implementations.
- No NMEA 2000 certification conformance claims of any kind.

## Honest limits

- Field layouts come from the canboat project's reverse-engineered database
  (Apache-2.0), not from the NMEA association's official database.
- NA patterns are common practice, not standard constants (THIRD_PARTY.md).
- Fast Packet timeout default (1000 ms) is a project choice.
- The final-frame padding (0xFF) is an engineering choice; receivers never
  rely on padding bytes.
