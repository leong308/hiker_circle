# Button Debugging — firmware compatibility and usage

## Firmware decision

**No button firmware changes are required for the new passive Button Debugging recorder.**
No button source, advertising format, service UUID, authentication algorithm,
or production SOS behavior was changed for this feature. Debug sessions and
their exported files are implemented entirely on the phone.

“Ping pong” here means observing the existing request/response exchanges; it
does **not** introduce a new `PING`/`PONG` opcode or send periodic packets.

## Where to find it

1. Sign in as an administrator and open **Admin → Button Debugging**.
2. Press **Start debug session**. Simply opening the page does not record.
3. Expand **Device commands** and choose a button paired to the active account, if available.
4. Optionally use **Read device log** to exercise the existing authenticated
   challenge → authentication → page selection → data response flow.
5. Optionally use **Arm safe test (30s)**. Wait for the successful armed message
   before pressing the physical button. A normal press outside the successful
   test window remains a real SOS; the recorder does not suppress emergencies.
6. Press **Stop and save session** or close the debugging page (dispose it).
   Popups, covering routes, and app lifecycle changes do not stop the recorder.
   On disposal, capture closes immediately and accepted entries drain into SQLite
   asynchronously before the session is finalized. Normal SOS monitoring remains enabled.
   If the OS terminates the app, committed entries are recovered on the next opening.
7. Open the **Saved sessions** tab to read the complete log offline. Use the export icon
   in the log viewer to export a `.log` file through the system file picker.

## Capture workspace

The Start/Stop control remains at the bottom while scrolling. **Live capture**
shows the newest 300 entries; **All / RX / TX / Local** filters only the displayed
list. All accepted entries are saved, including entries hidden by a filter.
Changing tabs, opening a saved log, expanding controls, and showing popups do not
stop recording. Closing the debugging page or pressing Stop ends the session.

Each packet includes a selectable HEX block with **Copy HEX**, a byte-by-byte
field table, expandable connection details, and capture notes / decimal bytes.
Pairing-key placeholders remain redacted in the table, clipboard, and exports.
Saved sessions use local dates and retain their complete original captures.

## Existing firmware capabilities used by optional actions

The recorder itself works without these capabilities. Only update older
firmware if an optional action is actually needed and that capability is
missing. Do not add a second debugging-specific protocol.

| Optional action | Existing protocol requirement | If absent |
| --- | --- | --- |
| Safe physical-button test | Test control characteristic `7e2a1d41-8b10-4f4d-9f78-0c6f1d65cba1`; authenticated 22-byte challenge / 30-byte arm request | App reports incompatibility; passive recording remains available. Do not simulate a test with a real SOS packet. |
| Read device event log | Existing log challenge, authentication, data, and page selector characteristics (UUID prefixes `7e2a1d3c` through `7e2a1d3f`) | App reports unavailable/incompatible log service; received advertisements and attempted commands can still be recorded. |

The maintenance service has UUID
`7e2a1d40-8b10-4f4d-9f78-0c6f1d65cba1`; clients also support the existing setup
service fallback where appropriate. Keep existing encrypted/authenticated
access requirements intact.

### Safe-test format (already supported by the app)

Read challenge:

```text
HC 01 13 device-id[6] next-event-id[4] nonce[8]       # 22 bytes
```

Write the same challenge followed by the first eight bytes of
`HMAC-SHA-256(pairing-secret, challenge)` (30 bytes total). After accepting the
single-use challenge, the button arms the next event for 30 seconds. A test
press advertises paired-SOS type `4`, mode `2`; ordinary SOS uses mode `1`.
The app only announces a successfully armed test after the write succeeds.

### Device-log format (already supported by the app)

The log challenge is `HC 01 10`, device ID (6 bytes), and nonce (16 bytes).
Android can use the existing short 8-byte authentication tag and chunked
transfer. The existing iOS implementation uses its current authentication and
page-read flow unchanged. Preserve support for the existing clients rather
than replacing either transfer format for this screen.

For the complete protocol, see [CUSTOM_SOS_BLE_PROTOCOL.md](CUSTOM_SOS_BLE_PROTOCOL.md).
The older [SOS_BUTTON_FIRMWARE_UPDATE_FOR_APP.md](SOS_BUTTON_FIRMWARE_UPDATE_FOR_APP.md)
contains historical setup-countdown work and describes authenticated safe
tests as future work; that historical description is superseded by the
authenticated-test section in the current protocol document and native code.
It is **not** a list of new requirements for Button Debugging.

## What the phone records

- Direction (`TX`, `RX`, or phone-local `LOCAL`), ordered sequence number,
  UTC timestamp, device identifier, operation, characteristic, and result.
- GATT write attempts, write completion callbacks, read requests, read results,
  notifications, and relevant HikerCircle advertisement payloads. Android's
  background SOS service feeds the same recorder before normal duplicate
  suppression, so repeated advertisements remain visible when Android delivers them.
- Hexadecimal bytes, unsigned decimal byte values, and interpretations of
  known packet fields: IDs, event counters, modes, coordinates, accuracy,
  timestamps, page selectors, challenge/authentication fields, and log records.
- Unknown, malformed, or partial packets are retained as raw entries. Partial
  log chunks are not falsely presented as complete decoded pages.

### Deliberate limits

- This is an **application-level BLE trace**, not a Bluetooth radio sniffer.
  The phone OS does not expose every on-air frame, encrypted link-layer byte,
  controller ACK, dropped packet, or button-internal command. OS scanning
  filters/coalescing still apply. No firmware update can make the app see radio
  packets the OS does not deliver; use appropriate external capture hardware
  if that level of diagnosis is necessary.
- `TX write_request` means a write was attempted, not that the device accepted
  it. Consult the corresponding `write_complete` result. Android GATT status
  `0` means success; local `write_queued` means only the OS accepted the request.
- The permanent pairing key (pair-request bytes 10–41) is redacted **in native
  code before crossing into Dart**. Zero placeholders retain offsets and are
  explicitly labelled as redacted, not interpreted as real zero key bytes.
  Authentication tags/nonces are visible, but the viewer does not itself
  authenticate raw received advertisements.
- Logs may contain device identifiers and locations. They remain local unless
  an admin explicitly exports/shares them. Only the active account's history
  is shown. There is no Firebase upload or new network requirement.
- A session ends on leaving the page or leaving the foreground. Capture does
  not automatically resume on return. An already-issued BLE operation may
  finish normally, but further bytes are not appended to the closed session.
- Normal app termination cannot run cleanup. On the next debugger opening,
  previously committed entries are recovered and the session is marked
  **interrupted**, not presented as a cleanly stopped recording. The recorded
  recovery time is not a fabricated crash timestamp.

## Local storage additions

SQLite schema version is upgraded from **26 → 27**; existing data is preserved.

| Table | Purpose | Key |
| --- | --- | --- |
| `button_debug_sessions` | Owner, start/end timestamps, recording/concluded status, end reason, complete finalized text, optional local file path | `id` |
| `button_debug_entries` | Individual captured entries, raw payload BLOB, decoded interpretation and metadata | `(session_id, sequence)` |

One session has many ordered entries. The owner/start-time index supports
account-local history; the entry primary key supports ordered session reads.
Entries cannot be appended through the repository after the session closes or
from a different account.

The live view keeps the latest **300 entries** in memory; this is not a storage
limit. All successfully persisted entries are included in the finalized log.
Files are created under the app documents directory:

```text
button_debug_logs/button_debug_<session-id>.log
```

The complete finalized text is saved in SQLite first, so file creation failure
does not lose the log; it can be exported again from history. Storage failures
stop recording and are reported rather than silently claiming a complete log.

## Hardware verification checklist (not executed on your phone)

- Open/leave without starting: no new recorded session.
- Start with a paired button nearby: existing delivered packets show byte values.
- Read device log: inspect challenge RX, authentication TX, write result, page
  selection TX, page/chunk RX, and decoded fields where complete.
- Arm a safe test: verify successful arm acknowledgement before pressing;
  observe mode `2` rather than a production SOS.
- Disable Bluetooth or move out of range: failure/timeout is reported; captured
  traffic remains locally available.
- Leave while a command is pending: session concludes and stops accepting bytes.
- Repeat in airplane mode with Bluetooth re-enabled: capture/history work
  without internet. Bluetooth itself must remain available for device traffic.
- Relaunch, open history, and export the log; test separately on Android and iOS.
