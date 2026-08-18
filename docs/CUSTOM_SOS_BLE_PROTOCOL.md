# HikerCircle BLE SOS Button Protocol

This app listens for a BLE-only ESP32-C3 SOS button using a short advertising
burst. The recommended firmware behavior is:

1. Deep sleep until the tactile switch is pressed.
2. Start BLE advertising for 3-5 seconds.
3. Include both the HikerCircle manufacturer packet and SOS service UUID below.
   The manufacturer packet is required for authentication/duplicate handling;
   the service UUID is required for reliable iOS background and locked-screen
   discovery. A manufacturer-only button is foreground-only on iOS.
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
The paired-v2 counter is compared with uint32 serial arithmetic, so natural
`0xffffffff` to `0` wrap is accepted. A firmware/factory reset to a lower
counter is deliberately rejected as a possible replay; physically re-pair the
button after any reset that clears its counter or pairing state.

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

During setup, Android and iOS scan service
`7e2a1d37-8b10-4f4d-9f78-0c6f1d65cba1`. It writes exactly 42 bytes to
`7e2a1d38-8b10-4f4d-9f78-0c6f1d65cba1`: `48 43 01 01` (`HC`, version 1,
pair-request type 1), six device-ID bytes,
then 32 secret bytes. The status characteristic
`7e2a1d39-8b10-4f4d-9f78-0c6f1d65cba1` returns 10 bytes: `HC 01 SS` followed by
the six-byte device ID. Status `02` means the app must wait for the final
physical confirmation; status `03` commits the encrypted local registry.

The setup peripheral must support a write-with-response payload of at least 42
bytes (ATT MTU of at least 45, or a standards-compliant long write) and expose a
CCCD-backed notifying status characteristic. Android requests MTU 247 before
the write; both mobile clients wait for the asynchronous write result before
reporting that pairing data was accepted.

Current firmware should also advertise the compact protocol-v1 type-`0x06`
setup-status manufacturer payload so Android and iOS can display the button's
actual setup-mode countdown. The extension is backward-compatible and sized to
coexist with the 128-bit setup UUID in a legacy advertisement. See
[`SOS_BUTTON_FIRMWARE_UPDATE_FOR_APP.md`](SOS_BUTTON_FIRMWARE_UPDATE_FOR_APP.md)
for the exact six-byte layout, advertising budget, state behavior, and firmware
acceptance checklist.

The 32-byte value in this request is a long-lived authentication secret, not an
application-layer encrypted payload. Production firmware **must** configure the
pair-request characteristic to require an encrypted, authenticated,
MITM-protected BLE link (LE Secure Connections with passkey or numeric
comparison) before accepting any read/write, and should protect pairing-status
notifications the same way. Reject unauthenticated and Just Works writes. A
physical confirmation press proves local presence but does not stop a wireless
sniffer or active MITM from learning a secret sent over an unprotected GATT
link.

Android requires an OS bond before it connects to write pairing material. The
first pairing attempt may therefore open the system Bluetooth pairing prompt;
after approving it, retry in HikerCircle. Bonding alone cannot prove that the
peripheral selected a MITM-resistant association model, so the firmware
attribute permissions above remain mandatory. iOS does not expose a public
bond-state API; CoreBluetooth will request system pairing only when the
firmware characteristic requires protected access. There is currently no
ECDH/PAKE envelope in this protocol, so firmware must never accept the 42-byte
request over plaintext GATT.

Pairings are scoped to the signed-in HikerCircle account. Re-pairing the same
physical BLE address/peripheral identifier replaces the older local record,
including a record owned by another account, because the firmware can retain
only the current secret. Existing pre-scope registry entries must be re-paired.
Device-local Android pairing preferences are excluded from cloud backup and
device transfer because their non-exportable Keystore key cannot be restored.
If secure storage is nevertheless unreadable, the settings screen can discard
only local pairing material; the physical button must then be placed back into
setup/factory-reset mode and paired again.

The Android app can still detect the SOS service UUID alone as a legacy signal,
but service-UUID-only advertisements cannot reliably distinguish a repeated
packet from a new press. The clients therefore apply a 10-second debounce to
counterless legacy packets; use the manufacturer packet above for production.

Authenticated owner presses are queued by native mobile code when Flutter is
not ready, tagged with the active account scope, and delivered later through
the trusted BLE event channel. Custom `hikercircle://sos/paired` URLs are not a
trusted substitute for this queue. Pending presses older than five minutes (or
implausibly future-dated) are discarded instead of starting a new, stale SOS.

## Mobile background prerequisites

Android uses a connected-device foreground service, controller-side
manufacturer/service scan filters, and a boot receiver. Notification permission
is strongly recommended for visible SOS and monitor alerts, but Android 13+
notification denial does not prevent the foreground BLE monitor from starting.
Users
on Android 11 and later must separately allow background location in system
settings if they expect a fresh location handoff while HikerCircle is not in
the foreground. iOS requires the Bluetooth central/peripheral and location
background modes, notification permission, and the Always location upgrade.
The app keeps only a recent emergency snapshot (maximum age five minutes).

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

The version-1 team-location packet format is retained for protocol migration,
but the mobile app does not currently advertise or trust it. Its public hashes
do not authenticate the sender, so accepting it as safety evidence would allow
nearby replay or coordinate injection. Cloud-authorized team locations remain
active. A future BLE version must add a per-session MAC and replay protection
before this transport can be enabled again. Android uses
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

The packet does not put phone numbers or names in BLE advertisements, but the
hashes are identifiers rather than security credentials.

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
The GATT write payload is exactly 30 bytes; values of any other size must be
rejected by firmware.

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

## Authenticated event-log maintenance

The owner can download the button's 32-record NVS event log without entering
pairing setup. The app begins waiting, then the user presses the external button
five times within three seconds. The first press wakes a button in deep sleep;
a completed sequence suppresses SOS and advertises read-only maintenance service
`7e2a1d40-8b10-4f4d-9f78-0c6f1d65cba1` for 30 seconds. The service cannot
change button ownership.

The pairing service retains the same characteristics for compatibility. The
pairing secret remains in the Android encrypted registry or iOS Keychain and
never crosses the Flutter channel.

The maintenance service exposes these characteristics:

| Characteristic | UUID | Operation |
| --- | --- | --- |
| Challenge | `7e2a1d3c-8b10-4f4d-9f78-0c6f1d65cba1` | Read |
| Authentication | `7e2a1d3d-8b10-4f4d-9f78-0c6f1d65cba1` | Write |
| Log data | `7e2a1d3e-8b10-4f4d-9f78-0c6f1d65cba1` | Read |
| Page selection | `7e2a1d3f-8b10-4f4d-9f78-0c6f1d65cba1` | Write |

The 26-byte challenge is `HC 01 10`, followed by the six-byte button device ID
and a fresh 16-byte random nonce. The authentication write repeats those 26
bytes and appends the first eight bytes of HMAC-SHA-256 over the challenge,
keyed by the pairing secret.

Successful authentication is bound to the current BLE connection for 30
seconds. The firmware immediately rotates the nonce, preventing the accepted
response from being replayed by another connection. Page writes are one
zero-based page-index byte and are ignored for unauthenticated connections.

Each log page starts with this eight-byte header:

```text
HC 01 12 record-size total-count page-index page-record-count
```

`record-size` is 20. Each record contains four big-endian uint32 fields
(`sequence`, `uptimeMillis`, `epochSeconds`, and `eventId`), followed by
`type` uint8, `resetReason` uint8, and `detail` uint16 big-endian. Pages contain
at most eight records and are returned oldest first.
