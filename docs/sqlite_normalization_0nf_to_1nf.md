# HikerCircle SQLite Normalization: 0NF to 1NF

## Purpose

This document explains how HikerCircle's local data progresses from an
unnormalized form (0NF) to first normal form (1NF). It focuses on the local
SQLite schema version 26.

The objective of 1NF is to ensure that:

1. Every table has identifiable rows.
2. Every column contains one atomic SQLite value.
3. A column does not contain repeating groups of the same attribute.
4. Values stored in a column have a consistent meaning and data type.

## 1. Starting point: 0NF

In 0NF, one large user record could contain nested objects and repeating
collections such as contacts, messages, trails, map downloads, check-ins, and
notifications.

### Example 0NF record

```text
USER_RECORD
------------------------------------------------------------
phone_number: +60111111111
username: Aina
emergency_contacts:
  - [Ali, Brother, +60122222222]
  - [Mei, Friend, +60133333333]
active_hike:
  session_id: hike-101
  trail: Broga Hill
  check_ins:
    - [2026-09-11T08:00:00Z, 2.9401, 101.9012]
    - [2026-09-11T08:30:00Z, 2.9410, 101.9020]
messages:
  - [chat-1, msg-1, "Reached checkpoint", pending]
  - [chat-1, msg-2, "All safe", sent]
downloaded_maps:
  - [country:MY, outdoors-v12, complete, 42800000 bytes]
static_hazards:
  - [trail_broga_001, river, 2.9402, 101.9014, possible_crossing, 5 m]
preferences:
  - [sos_whatsapp_note_manual, "I need assistance"]
notifications:
  - [notif-1, "Weather warning", unread]
```

This is 0NF because several fields contain lists of repeated values and nested
records. It is difficult to query, update, retry, or isolate individual items.

For example:

- Updating one emergency contact requires rewriting the complete user record.
- One failed message cannot be retried independently.
- Check-ins cannot be indexed by time.
- Map download progress cannot be updated without replacing the map list.
- Data belonging to different signed-in accounts can be mixed accidentally.

## 2. Identify entities and repeating groups

The large record is divided according to the responsibility of each piece of
data.

| 0NF data group | 1NF destination |
|---|---|
| User identity and local session | `users` |
| Device installation identity | `app_device` |
| Repeated emergency contacts | `emergency_contacts` |
| Current hike | `active_hike_session` |
| Planned hikes and checklist state | `planned_hike_state` |
| Completed hikes awaiting upload | `pending_hike_ends` |
| Repeated GPS samples | `local_location_points` |
| Repeated network samples | `network_observations` |
| SOS alerts awaiting delivery | `queued_alerts` |
| Chat messages | `pending_messages` |
| Chat read positions | `chat_read_receipts` |
| Cached cloud documents | `cached_entities` |
| Mutations awaiting synchronization | `sync_outbox` |
| Per-user settings | `local_preferences` |
| Achievement snapshot | `achievement_progress_cache` |
| Legacy downloaded-map metadata | `downloaded_maps` |
| Mapbox tile-region state | `offline_map_regions` |
| Downloaded static hazard points | `hazard_features` |
| Trail-to-hazard relationships | `trail_hazard_matches` |
| Hazard bounding-box search entries | `hazard_feature_rtree` |
| Calculated route geometry | `route_cache` |
| Notification history | `device_notifications` |
| Nearby SOS detections | `nearby_sos_events` |

## 3. Remove repeating groups

Each item from a repeating collection becomes an independent row.

### Emergency contacts

#### 0NF

```text
contacts = [
  [Ali, Brother, +60122222222],
  [Mei, Friend, +60133333333]
]
```

#### 1NF

| id | owner_phone_number | contact_phone_number | name | relationship | position |
|---:|---|---|---|---|---:|
| 1 | +60111111111 | +60122222222 | Ali | Brother | 0 |
| 2 | +60111111111 | +60133333333 | Mei | Friend | 1 |

The combination of `owner_phone_number` and `contact_phone_number` is unique,
so the same contact is not duplicated for one owner.

### Location points

#### 0NF

```text
check_ins = [
  [2026-09-11T08:00:00Z, 2.9401, 101.9012],
  [2026-09-11T08:30:00Z, 2.9410, 101.9020]
]
```

#### 1NF

| id | owner_phone_number | session_id | latitude | longitude | point_type | recorded_at | is_synced |
|---:|---|---|---:|---:|---|---|---:|
| 1 | +60111111111 | hike-101 | 2.9401 | 101.9012 | check_in | 2026-09-11T08:00:00Z | 0 |
| 2 | +60111111111 | hike-101 | 2.9410 | 101.9020 | check_in | 2026-09-11T08:30:00Z | 0 |

Every coordinate and timestamp is now independently queryable. SQLite can
index the rows by session, synchronization state, and recording time.

### Chat messages

#### 0NF

```text
messages = [
  [chat-1, msg-1, "Reached checkpoint", pending],
  [chat-1, msg-2, "All safe", sent]
]
```

#### 1NF

| local_id | owner_phone_number | chat_id | text | send_status | retry_count |
|---|---|---|---|---|---:|
| msg-1 | +60111111111 | chat-1 | Reached checkpoint | pending | 0 |
| msg-2 | +60111111111 | chat-1 | All safe | sent | 0 |

This allows one message to be retried without deleting or rewriting other
messages. `owner_phone_number` also prevents one account from reading another
account's local conversation data.

## 4. Assign primary keys

Every 1NF table needs a key that identifies one row.

HikerCircle uses three key patterns:

### Single-column keys

Examples:

- `users.phone_number`
- `pending_messages.local_id`
- `sync_outbox.operation_id`
- `offline_map_regions.trail_id`

### Auto-increment integer keys

Examples:

- `local_location_points.id`
- `queued_alerts.id`
- `emergency_contacts.id`
- `device_notifications.id`
- `hazard_features.local_id`
- `hazard_feature_rtree.local_id`

### Composite keys

Composite keys identify rows whose uniqueness depends on more than one value.

Examples:

- `chat_read_receipts(owner_phone_number, chat_id)`
- `cached_entities(owner_phone_number, entity_type, entity_id)`
- `local_preferences(owner_phone_number, preference_key)`
- `planned_hike_state(owner_phone_number, upcoming_hike_id)`
- `pending_hike_ends(owner_phone_number, session_id)`
- `route_cache(trail_id, checkpoints_hash)`
- `nearby_sos_events(owner_phone_number, event_key)`
- `trail_hazard_matches(trail_id, hazard_id)`

## 5. Make column values atomic

Values that must be filtered, sorted, indexed, or updated independently are
stored in their own columns.

For example, an offline map is not stored as:

```text
map = [country:MY, outdoors-v12, 4, 12, complete, 42800000]
```

It becomes:

| trail_id | style_uri | min_zoom | max_zoom | status | completed_bytes |
|---|---|---:|---:|---|---:|
| country:MY | mapbox://styles/mapbox/outdoors-v12 | 4 | 12 | complete | 42800000 |

The app can now update `status` or `completed_bytes` without replacing the
other values.

## 6. Treatment of JSON columns in 1NF

The schema includes columns such as:

- `payload_json`
- `value_json`
- `bounds_json`
- `attachment_json`
- `data_json`
- `completed_checklist_json`

For this project, each serialized JSON document is treated as one atomic value
at the SQLite boundary. This is acceptable for the requested 1NF design
because the app reads or replaces the document as a single value.

Frequently queried operational properties are still extracted into normal
columns. For example, `sync_outbox` stores its payload as JSON but keeps
`status`, `attempt_count`, `next_attempt_at`, and `last_error` in separate
columns so retry processing remains efficient.

Further normalization to 2NF or 3NF could split the internal JSON structures
into additional tables, but that is outside the scope of this design.

## 7. Account isolation

User-owned tables include `owner_phone_number`. This value acts as a logical
relationship to `users.phone_number`.

```text
users.phone_number
        |
        +-- emergency_contacts.owner_phone_number
        +-- active_hike_session.owner_phone_number
        +-- pending_messages.owner_phone_number
        +-- chat_read_receipts.owner_phone_number
        +-- cached_entities.owner_phone_number
        +-- sync_outbox.owner_phone_number
        +-- local_preferences.owner_phone_number
        +-- device_notifications.owner_phone_number
        +-- nearby_sos_events.owner_phone_number
```

These are logical rather than enforced foreign keys. Safety records and queued
writes must survive sign-out, interrupted migrations, and temporary loss of a
user-session row.

## 8. Resulting 1NF example

After conversion, the original 0NF user record is represented by related rows:

```text
users
  (+60111111111, Aina, ...)

emergency_contacts
  (1, +60111111111, +60122222222, Ali, Brother, 0)
  (2, +60111111111, +60133333333, Mei, Friend, 1)

active_hike_session
  (+60111111111, hike-101, <atomic JSON snapshot>, ...)

local_location_points
  (1, +60111111111, hike-101, 2.9401, 101.9012, check_in, ...)
  (2, +60111111111, hike-101, 2.9410, 101.9020, check_in, ...)

pending_messages
  (msg-1, +60111111111, chat-1, "Reached checkpoint", pending, ...)
  (msg-2, +60111111111, chat-1, "All safe", sent, ...)

offline_map_regions
  (country:MY, country-malaysia-v1, outdoors-v12, complete, ...)

local_preferences
  (+60111111111, sos_whatsapp_note_manual, "I need assistance", ...)

hazard_features
  (1, mapbox:trail_broga_001:waterway:river:123, river, 2.9402, 101.9014, ...)

trail_hazard_matches
  (trail_broga_001, mapbox:trail_broga_001:waterway:river:123,
   possible_crossing, 5, 0.42, ...)
```

Each row is identifiable, each column stores one SQLite value, and repeating
items exist as separate rows. The resulting schema is therefore in 1NF.

## 9. Transformation summary

```text
0NF
One nested user record containing lists and repeated groups
  |
  | Identify independent entities
  v
Separate users, contacts, hikes, messages, maps, preferences and alerts
  |
  | Convert every repeated item into a row
  v
Rows with atomic values
  |
  | Add single or composite primary keys and account ownership
  v
1NF
Queryable, account-scoped and independently updateable SQLite records
```

The complete resulting schema and ERD are documented in
[`sqlite_erd_1nf.md`](sqlite_erd_1nf.md).
