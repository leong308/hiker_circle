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

## Paired SOS remote advertisement (protocol v2)

The paired-button plan uses a separate authenticated packet and must not fall
through the legacy type-1 workflow. Keep manufacturer ID `0x02E5`; the
manufacturer payload (after Android removes the two company-ID bytes) is 23
bytes:

| Byte(s) | Value | Meaning |
| --- | --- | --- |
| 0-1 | `HC` | Magic |
| 2 | `0x02` | Protocol version |
| 3 | `0x04` | Paired SOS remote packet |
| 4 | `0x01` | Manual SOS mode |
| 5-10 | 6 bytes | Stable random button device ID |
| 11-14 | uint32 BE | Persisted press/event counter |
| 15-22 | 8 bytes | First 8 bytes of HMAC-SHA-256 over bytes 0-14 |

The HMAC key is the pairing secret stored only in the paired-button registry
and the button. The owner phone starts Manual SOS only after verification. A
phone without that device ID shows a nearby-button popup and never starts its
own SOS workflow. Legacy v1/type-1 packets are disabled by default and are
available only through the explicit migration setting.

### Pairing GATT payloads

During setup, Android scans service
`7e2a1d37-8b10-4f4d-9f78-0c6f1d65cba1`. It writes exactly 42 bytes to
`7e2a1d38-8b10-4f4d-9f78-0c6f1d65cba1`: `HC 01 01 01`, six device-ID bytes,
then 32 secret bytes. The status characteristic
`7e2a1d39-8b10-4f4d-9f78-0c6f1d65cba1` returns 10 bytes: `HC 01 SS` followed by
the six-byte device ID. Status `02` means the app must wait for the final
physical confirmation; status `03` commits the encrypted local registry.

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

## Owner location handoff and type-5 relay

After an owner phone accepts a type-4 event, it keeps the button awake by
connecting to the temporary active-SOS service
`7e2a1d3a-8b10-4f4d-9f78-0c6f1d65cba1` and writing 30 bytes to
`7e2a1d3b-8b10-4f4d-9f78-0c6f1d65cba1`:

```text
HC v2 type-5 event-id latitude-E7 longitude-E7 accuracy-dm captured-at-seconds HMAC8
```

The first 22 bytes are HMAC-SHA-256 input, keyed by the existing pairing
secret; the final 8 bytes are the truncated tag. The button accepts the write
only for the currently active event and only inside its 30-second handoff
window. It then broadcasts a type-5 location relay for 15 seconds.

The type-5 advertisement is exactly 24 bytes so it fits a legacy BLE
advertisement:

| Byte(s) | Value | Meaning |
| --- | --- | --- |
| 0-3 | `HC 02 05` header | Bytes 0-3 are `48 43 02 05` |
| 4-9 | 6 bytes | Stable button device ID |
| 10-13 | uint32 BE | Press/event counter |
| 14-17 | int32 BE | Latitude multiplied by `10,000,000` |
| 18-21 | int32 BE | Longitude multiplied by `10,000,000` |
| 22-23 | uint16 BE | Owner-phone GPS accuracy in decimeters |

The captured timestamp is authenticated in the GATT handoff but omitted from
the relay advertisement to stay within the 31-byte legacy BLE limit; receivers
use their reception time. Nearby phones do not hold the pairing secret, so they
must label this as an unverified proximity/location signal and must not start
their own SOS workflow. They should display the relayed coordinate and reported
GPS accuracy, not an RSSI-derived distance or radius.
