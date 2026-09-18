# Hike completion confirmation

## Investigation: 18 September 2026

The iPhone's pending-completion records contained `TimeoutException after 0:00:08.000000` for two hikes. Read-only checks of the corresponding Firebase session documents showed both were already `completed`, with the original end times intact.

Cloud Run request logs showed successful HTTP 200 responses:

| Hike | Server response time | Previous app deadline |
| --- | ---: | ---: |
| Pintu Wang Gunung | 19.614 seconds | 8 seconds |
| The Habitat Penang Hill Route | 12.553 seconds | 8 seconds |

Later retries also succeeded on the server in roughly 12–18 seconds. This was a deadline mismatch, not evidence of a poor phone connection. The completion callable waits for achievement work after committing the completion transaction, so a committed session can precede the response by several seconds.

## Correction

- `lib/app/Data/hike_completion_request.dart` gives completion a dedicated 45-second deadline. Ordinary write deadlines are unchanged.
- `_completeActiveHikeSession` in `lib/app/Data/hiker_circle_firebase_repository.dart` applies this deadline to both the Firebase callable and the Dart wait.
- `HikerHomePage` describes unresolved confirmation as pending instead of asserting that the hike ended offline.
- Community sharing can retry pending completion and preserves the original end time and canonical Firebase session ID.
- Pending completion remains queued if the bounded request still fails. It is not treated as proof that the server rejected or failed to save the hike.

Regression tests in `test/app/hike_completion_request_test.dart` simulate both observed response delays, an unresponsive server, and immediate rejection. Related sharing tests verify that retrying retains the original hike and caption.
