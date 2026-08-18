# SOS Button Firmware Update for HikerCircle App

This document is the implementation handoff for the SOS button firmware
developer. It describes the firmware change needed by the current mobile app
for an exact setup-mode countdown and clarifies the new 30-second button test
flow.

## Change summary

| Area | Firmware change | Priority |
| --- | --- | --- |
| Setup-mode countdown in the app | Emit the six-byte setup-status manufacturer payload below while advertising the existing setup service | Required for an exact countdown |
| Countdown on a button display | Render the same monotonic remaining-seconds value locally when the hardware has a screen | Required when the button has a display |
| 30-second test from the paired-button card | No protocol change is required for suppression on the owning phone | Already compatible |
| Prevent nearby phones from observing a test press | Requires a future authenticated test-arm protocol shared by firmware and both mobile clients | Not implemented; do not invent a new packet independently |

The setup-status extension is backward-compatible. Firmware must retain the
existing setup service and pairing characteristics. Older app builds ignore
the new manufacturer packet; current app builds still pair older firmware but
show only their own 30-second scan countdown.

## Required setup-mode status advertisement

Continue advertising this existing setup service UUID:

```text
7e2a1d37-8b10-4f4d-9f78-0c6f1d65cba1
```

Add manufacturer data using company/manufacturer ID `0x02E5`. The application
payload after the two company-ID bytes is exactly six bytes:

| Byte | Value/type | Meaning |
| --- | --- | --- |
| 0 | `0x48` | ASCII `H` |
| 1 | `0x43` | ASCII `C` |
| 2 | `0x01` | Setup-status protocol version |
| 3 | `0x06` | Paired-button setup-status packet type |
| 4 | `0x01` | State: setup mode is active and advertising |
| 5 | `uint8` | Actual whole seconds remaining, `0...255` |

On air, a complete manufacturer field begins with the company ID in Bluetooth
little-endian order:

```text
E5 02 48 43 01 06 01 RR
```

`RR` is the remaining-seconds byte. For example, 117 seconds is `0x75`.
Do not include the `E5 02` company bytes inside the six-byte application
payload when the BLE library API accepts the manufacturer ID separately. If
the API accepts one raw manufacturer-data buffer, prepend `E5 02` exactly
once.

### Legacy advertising-size requirement

The six-byte payload is deliberately sized to fit a legacy 31-byte BLE
advertisement with flags and the 128-bit setup service UUID:

```text
3 bytes flags
18 bytes complete 128-bit service UUID field
10 bytes manufacturer field (length/type + company ID + 6-byte payload)
= 31 bytes
```

Do not also put `HikerCircle Setup` in the same primary advertisement; it will
overflow the legacy packet. The app already falls back to that display name.
A scan-response local name is optional, but the setup service UUID and status
manufacturer payload must remain in the primary advertisement for iOS and
Android discovery.

## Countdown behavior

1. Start one monotonic setup deadline when the physical setup gesture is
   completed. Do not restart it because a phone scans, connects, disconnects,
   retries, or reads a characteristic.
2. A 120-second setup window is recommended. The app accepts any truthful
   value from 0 through 255, so existing firmware may keep a different window.
3. Rebuild the advertised status value at least once per second. If the BLE
   stack cannot update advertising data in place, update as frequently as the
   stack safely permits; the app anchors a local deadline from the latest
   received value and continues counting between packets.
4. Calculate the byte from a monotonic clock, rounding remaining partial
   seconds upward. Never use wall-clock/NTP time for this timer.
5. At zero, leave setup mode, stop advertising the setup service, reject new
   pair requests, clear uncommitted pairing material, and return to the normal
   low-power state.
6. A connected phone must not extend the setup deadline silently. If product
   requirements need an extension, define it explicitly and advertise the new
   truthful value.

Reference pseudocode:

```cpp
constexpr uint32_t kSetupWindowMs = 120000;
uint32_t setupDeadlineMs = 0;

void enterSetupMode() {
  setupDeadlineMs = millis() + kSetupWindowMs;
  publishSetupAdvertisement();
}

uint8_t setupSecondsRemaining() {
  const int32_t remainingMs =
      static_cast<int32_t>(setupDeadlineMs - millis());
  if (remainingMs <= 0) return 0;
  return static_cast<uint8_t>(min(255, (remainingMs + 999) / 1000));
}

void publishSetupAdvertisement() {
  const uint8_t payload[6] = {
      0x48, 0x43, 0x01, 0x06, 0x01, setupSecondsRemaining()};
  // Advertise company ID 0x02E5, payload, and the existing setup UUID.
}
```

Use wrap-safe monotonic deadline comparisons appropriate to the firmware
framework; the abbreviated pseudocode is not a substitute for handling
`millis()` rollover correctly.

## Button-side visual countdown

If the physical button has a display, show the same source-of-truth value used
in byte 5. Recommended layout:

```text
SETUP MODE
01:59
Ready for phone
```

- Refresh once per second.
- Change to `CONFIRM 00:15` when pairing status becomes `0x02` and the firmware
  is waiting for the ownership-confirmation press.
- Show `PAIRED` briefly after status `0x03`, then exit setup mode.
- Show `EXPIRED` briefly when either window ends, clear uncommitted secrets,
  and exit.

For LED-only hardware, keep the documented LED sequence, but the BLE status
byte is still required for the app countdown.

## Existing secure pairing contract remains unchanged

Do not rename, remove, or alter these characteristics:

| Purpose | UUID | Contract |
| --- | --- | --- |
| Setup service | `7e2a1d37-8b10-4f4d-9f78-0c6f1d65cba1` | Advertised throughout setup |
| Pair request | `7e2a1d38-8b10-4f4d-9f78-0c6f1d65cba1` | Encrypted authenticated write with response, exactly 42 bytes |
| Pairing status | `7e2a1d39-8b10-4f4d-9f78-0c6f1d65cba1` | Encrypted read/notify with a CCCD, exactly 10 bytes |

Pairing status remains `HC 01 SS` followed by the six-byte device ID:

- `0x01`: ready
- `0x02`: awaiting the physical confirmation press
- `0x03`: paired/committed
- `0x04`: invalid request
- `0x05`: confirmation expired

The confirmation press must be consumed by the pairing state machine. It must
not increment or advertise a normal SOS event. Only commit the 32-byte secret
after that physical confirmation, and never accept it over plaintext or a
Just Works link. See `CUSTOM_SOS_BLE_PROTOCOL.md` for the complete security and
packet requirements.

## Paired-button test mode compatibility

The mobile app now has a test icon on each paired button card. When the user
starts it, the owning phone arms a 30-second local test window and waits for a
normal authenticated protocol-v2 type-`0x04` manual press from that exact
device ID. The owning phone verifies the HMAC and replay counter, records the
counter as consumed, shows success, and does not open SOS or contact emergency
recipients.

Therefore, no firmware change is needed for the current owner-phone test:

- keep emitting the existing authenticated type-`0x04` packet;
- increment the persisted event counter exactly once for the press;
- use the same event ID throughout its advertising burst;
- do not send a legacy type-`0x01` SOS packet in parallel.

The test window exists only on the owning phone. A nearby HikerCircle phone
does not possess that local state and can still observe the normal radio
packet. Fully suppressing nearby-help behavior would require a secure way for a
sleeping button to learn that the owner phone armed a test before the button
emits its first packet. That needs a jointly versioned authenticated protocol
and mobile implementation. Do not change byte 4 to an undocumented “test” mode
or emit an uncoordinated packet type: current released clients will either
ignore it or handle it inconsistently.

## Firmware acceptance checklist

- [ ] Entering setup mode starts one monotonic setup deadline.
- [ ] The primary advertisement contains the setup service UUID.
- [ ] Manufacturer ID is `0x02E5` and the application payload is exactly
      `48 43 01 06 01 RR`.
- [ ] `RR` decreases without resetting and matches any on-device display.
- [ ] The primary advertisement remains at or below 31 bytes.
- [ ] Setup exits and uncommitted pairing data is cleared at zero.
- [ ] The pair-request/status GATT attributes retain authenticated encrypted
      permissions and the existing UUIDs and payload sizes.
- [ ] The physical confirmation press never emits an SOS advertisement.
- [ ] A normal paired press emits only one authenticated type-`0x04` event and
      one persisted event-counter increment.
- [ ] Natural `uint32` counter wrap is supported; factory reset requires the
      button to be paired again.
- [ ] Verify countdown and pairing on both an Android phone and an iPhone,
      including a reconnect near expiry.

