# HikerCircle BLE SOS Button Protocol

This app listens for a BLE-only ESP32-C3 SOS button using a short advertising
burst. The recommended firmware behavior is:

1. Deep sleep until the tactile switch is pressed.
2. Start BLE advertising for 3-5 seconds.
3. Include the HikerCircle manufacturer packet below. The service UUID may also
   be included, but the manufacturer packet is required for reliable duplicate
   handling across multiple presses in the same app session.
4. Stop advertising and return to deep sleep.

## SOS Button Advertisement

- Service UUID: `7e2a1d32-8b10-4f4d-9f78-0c6f1d65cba1`
- Manufacturer id: `0x02E5`
- Manufacturer data:

| Byte(s) | Value | Meaning |
| --- | --- | --- |
| 0 | `0x48` | `H` magic |
| 1 | `0x43` | `C` magic |
| 2 | `0x01` | protocol version |
| 3 | `0x01` | packet type: SOS |
| 4 | `0x01` | mode: manual SOS |
| 5-8 | uint32 big-endian | broadcast event id: initial broadcast Unix seconds, monotonic press counter, or boot counter |

The event id must stay the same for every advertisement inside one 3-5 second
button-press burst, then change for the next button press. Recommended ESP32
implementation: set it once when advertising starts, using either Unix seconds
from RTC/NTP if available or an incrementing counter stored in RTC/NVS memory.

The Android app can still detect the SOS service UUID alone as a legacy signal,
but service-UUID-only advertisements cannot reliably distinguish a repeated
packet from a new press. Use the manufacturer packet above for production.

## App Test SOS Help Advertisement

The SOS test screen can make one phone pretend to be the physical button. This
test packet is intentionally richer than the ESP32 packet because the phone can
attach its current GPS snapshot. Nearby HikerCircle phones open a help popup
instead of triggering their own SOS workflow.

Android broadcasts this as manufacturer data. iOS cannot advertise arbitrary
manufacturer payloads from app code, so iOS advertises the SOS help service UUID
and exposes the same 22-byte payload through a short-lived readable GATT
characteristic.

- Manufacturer id: `0x02E5`
- iOS SOS help service UUID: `7e2a1d34-8b10-4f4d-9f78-0c6f1d65cba1`
- iOS SOS help characteristic UUID: `7e2a1d35-8b10-4f4d-9f78-0c6f1d65cba1`
- Manufacturer data length: 22 bytes

| Byte(s) | Type | Meaning |
| --- | --- | --- |
| 0-1 | ASCII | `HC` magic |
| 2 | uint8 | protocol version: `1` |
| 3 | uint8 | packet type: `3` SOS help test |
| 4-7 | uint32 BE | FNV-1a hash of normalized sender phone digits |
| 8-11 | int32 BE | latitude multiplied by `10,000,000` |
| 12-15 | int32 BE | longitude multiplied by `10,000,000` |
| 16-17 | uint16 BE | accuracy in decimeters |
| 18-21 | uint32 BE | captured-at Unix seconds |

## Team Location Advertisement

Phones in an active team hike advertise compact peer-location packets locally
over BLE. No network is required for these packets. Android uses
manufacturer-data-only advertisements for this packet because the 26-byte
location payload plus a 128-bit service UUID does not fit reliably in a legacy
31-byte advertisement. On iOS, the same 26-byte packet is exposed through a
readable GATT characteristic while advertising the team location service UUID.

- Service UUID reserved for future GATT/extended advertising:
  `7e2a1d33-8b10-4f4d-9f78-0c6f1d65cba1`
- iOS team location characteristic UUID:
  `7e2a1d36-8b10-4f4d-9f78-0c6f1d65cba1`
- Manufacturer id: `0x02E5`
- Manufacturer data length: 26 bytes

| Byte(s) | Type | Meaning |
| --- | --- | --- |
| 0-1 | ASCII | `HC` magic |
| 2 | uint8 | protocol version: `1` |
| 3 | uint8 | packet type: `2` team location |
| 4-7 | uint32 BE | FNV-1a hash of team session id |
| 8-11 | uint32 BE | FNV-1a hash of normalized phone digits |
| 12-15 | int32 BE | latitude multiplied by `10,000,000` |
| 16-19 | int32 BE | longitude multiplied by `10,000,000` |
| 20-21 | uint16 BE | accuracy in decimeters |
| 22-25 | uint32 BE | captured-at Unix seconds |

The app uses the hashes only to match known team participants. It does not put
phone numbers or names in BLE advertisements.
