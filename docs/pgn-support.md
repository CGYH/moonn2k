# PGN support matrix

All layouts verified against `canboat/canboat@6ce848c6048ae81414c90dd3cee57699f98c6738`
(`docs/canboat.json`, SchemaVersion 2.8.0). "NA pattern" values are common
NMEA 2000 practice, not canboat data (see THIRD_PARTY.md).

| PGN | Name | Transport | Length | Fields (offset/bits) | NA patterns |
|---:|---|---|---:|---|---|
| 59904 | ISO Request | single | 3 | PGN requested 0/24 | — |
| 60928 | ISO Address Claim | single | 8 | Unique Number 0/21, Manufacturer Code 21/11, Device Instance Lower 32/3, Device Instance Upper 35/5, Device Function 40/8, Spare 48/1, Device Class 49/7, System Instance 56/4, Industry Group 60/3, Arbitrary-address-capable 63/1 | — |
| 126992 | System Time | single | 8 | SID 0/8, Source 8/4, Reserved 12/4, Date 16/16 (d), Time 32/32 (0.0001 s) | Date 0xFFFF, Time 0xFFFFFFFF |
| 126993 | Heartbeat | single | 8 | Data transmit offset 0/16 (0.001 s), Sequence Counter 16/8, Controller 1 State 24/2, Controller 2 State 26/2, Equipment Status 28/2, Reserved 30/34 | — |
| 126996 | Product Information | fast packet | 134 | NMEA 2000 Version 0/16 (0.001), Product Code 16/16, Model ID 32/256 (text), Software Version Code 288/256 (text), Model Version 544/256 (text), Model Serial Code 800/256 (text), Certification Level 1056/8, Load Equivalency 1064/8 | — |
| 127250 | Vessel Heading | single | 8 | SID 0/8, Heading 8/16 (0.0001 rad), Deviation 24/16 (0.0001 rad, signed), Variation 40/16 (0.0001 rad, signed), Reference 56/2 (lookup), Reserved 58/6 | Heading 0xFFFF, Deviation 0x7FFF, Variation 0x7FFF |
| 128267 | Water Depth | single | 8 | SID 0/8, Depth 8/32 (0.01 m), Offset 40/16 (0.001 m, signed), Range 56/8 (10 m) | Depth 0xFFFFFFFF, Offset 0x7FFF |
| 129025 | Position, Rapid Update | single | 8 | Latitude 0/32 (1e-7 deg, signed), Longitude 32/32 (1e-7 deg, signed) | both 0x7FFFFFFF |
| 129026 | COG & SOG, Rapid Update | single | 8 | SID 0/8, COG Reference 8/2 (lookup), Reserved 10/6, COG 16/16 (0.0001 rad), SOG 32/16 (0.01 m/s), Reserved 48/16 | COG 0xFFFF, SOG 0xFFFF |
| 130306 | Wind Data | single | 8 | SID 0/8, Wind Speed 8/16 (0.01 m/s), Wind Angle 24/16 (0.0001 rad), Reference 40/3 (lookup), Reserved 43/21 | Wind Speed 0xFFFF, Wind Angle 0xFFFF |

Lookup tables:

- 127250 Reference: 0 True, 1 Magnetic, 2 Error, 3 Simulator.
- 129026 COG Reference: 0 True, 1 Magnetic, 2 Error, 3 Simulator.
- 130306 Reference: 0 True (North referenced), 1 Magnetic (North
  referenced), 2 Apparent (relative to vessel centerline), 3 True
  (historical), 4 Apparent (historical).

Unknown PGNs are never an error: the registry router returns them as
`Unknown` messages with the payload untouched. Known-PGN decode failures
always name the PGN and the field (TruncatedField / InvalidFieldValue).

Test coverage per PGN (plan 7.6): normal sample, min/max bounds, NA sample
where defined, truncated payload rejection, encode/decode round-trip, and a
reference vector from `fixtures/pgn-vectors.json`. Product Information
additionally runs the Fast Packet end-to-end path (typed encode → segment →
shuffled ingest → reassemble → typed decode).
