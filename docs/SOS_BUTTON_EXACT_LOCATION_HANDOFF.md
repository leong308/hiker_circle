# SOS button exact-location handoff

This document is for the SOS-button firmware team. The mobile app now explicitly requests a fresh high-accuracy phone fix after an authenticated type-4 SOS press. The button must accept that fix and rebroadcast it; otherwise nearby phones can only show the detector phone's approximate area.

## Required BLE flow

1. The paired button advertises the authenticated type-4 SOS event with its device ID and event ID.
2. The owner phone connects to active SOS service `7e2a1d3a-8b10-4f4d-9f78-0c6f1d65cba1`.
3. The phone writes exactly 30 bytes, with response, to location characteristic `7e2a1d3b-8b10-4f4d-9f78-0c6f1d65cba1`.
4. Firmware verifies the event ID is the currently active SOS event, validates the timestamp and truncated HMAC-SHA256 tag using the stored 32-byte pairing secret, and rejects replayed or stale writes.
5. On success, firmware logs `Location accepted`, then continuously advertises a type-5 location relay for the active SOS window.
6. Nearby phones decode the type-5 packet and display the relayed coordinates and accuracy. When the SOS session ends, firmware stops the relay.

## 30-byte GATT payload

All integers are big-endian.

| Offset | Bytes | Value |
|---:|---:|---|
| 0 | 2 | ASCII `HC` |
| 2 | 1 | Protocol version `2` |
| 3 | 1 | Type `5` |
| 4 | 4 | Active SOS event ID, unsigned 32-bit |
| 8 | 4 | Latitude × 10,000,000, signed 32-bit |
| 12 | 4 | Longitude × 10,000,000, signed 32-bit |
| 16 | 2 | Accuracy in decimetres, unsigned 16-bit |
| 18 | 4 | Captured-at Unix seconds, unsigned 32-bit |
| 22 | 8 | First 8 bytes of HMAC-SHA256 over bytes 0–21 |

## Type-5 advertising payload

Use manufacturer ID `0x02E5`. The 24-byte manufacturer data is: `HC`, version `2`, type `5`, six-byte device ID, four-byte event ID, latitude E7, longitude E7, and accuracy decimetres. Do not substitute a geohash, cell area, previous button position, or detector RSSI estimate for the phone-provided coordinates.

## Acceptance checks

- A valid handoff produces `Location accepted` followed by `Location relay started` in the button log.
- A bad HMAC, stale timestamp, wrong event ID, invalid coordinate, or inactive SOS produces `Location rejected` and must not change the advertised position.
- Test outdoors with phone precise-location permission enabled. A nearby second phone should show the same latitude/longitude and reported accuracy as the owner phone, within E7 encoding precision.
