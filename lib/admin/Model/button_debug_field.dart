// ButtonDebugField maps byte offsets to safe, readable BLE payload fields.
import 'dart:typed_data';

/// Byte ranges use zero-based, inclusive offsets, matching the captured payload.
class ButtonDebugField {
  const ButtonDebugField(this.start, this.end, this.hex, this.name, this.value);
  final int start, end;
  final String hex, name, value;
  String get range => start == end ? '$start' : '$start–$end';
}

String buttonPayloadHex(List<int> bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');

Uint8List buttonDebugSafePayload(List<int> payload, String characteristic) {
  final bytes = Uint8List.fromList(payload);
  if (characteristic.toLowerCase().startsWith('7e2a1d38') &&
      bytes.length > 10) {
    bytes.fillRange(10, bytes.length, 0);
  }
  return bytes;
}

/// Only decode layouts recognized by the application protocol. Every byte is
/// covered once, including unsupported payloads and incomplete log records.
List<ButtonDebugField> decodeButtonFields(
  List<int> payload,
  String characteristic,
) {
  final bytes = buttonDebugSafePayload(payload, characteristic);
  if (bytes.isEmpty) return const [];
  final data = ByteData.sublistView(bytes);
  final fields = <ButtonDebugField>[];
  bool uuid(String suffix) =>
      characteristic.toLowerCase().startsWith('7e2a1d$suffix');
  void add(int start, int length, String name, String value) {
    fields.add(
      ButtonDebugField(
        start,
        start + length - 1,
        buttonPayloadHex(bytes.sublist(start, start + length)),
        name,
        value,
      ),
    );
  }

  void number(int start, int length, String name, [String unit = '']) {
    final value = length == 4
        ? data.getUint32(start, Endian.big)
        : length == 2
        ? data.getUint16(start, Endian.big)
        : bytes[start];
    add(start, length, name, '$value$unit');
  }

  void identifier(int start, int length, String name) => add(
    start,
    length,
    name,
    buttonPayloadHex(bytes.sublist(start, start + length)).replaceAll(' ', ''),
  );
  void tag(int start, int length) => add(
    start,
    length,
    'Authentication tag',
    'Truncated HMAC-SHA256; reception alone does not verify authentication.',
  );
  void location(int lat, int lon, int accuracy) {
    add(
      lat,
      4,
      'Latitude',
      '${(data.getInt32(lat, Endian.big) / 1e7).toStringAsFixed(7)}°',
    );
    add(
      lon,
      4,
      'Longitude',
      '${(data.getInt32(lon, Endian.big) / 1e7).toStringAsFixed(7)}°',
    );
    add(
      accuracy,
      2,
      'Location accuracy',
      '${data.getUint16(accuracy, Endian.big) / 10} m',
    );
  }

  void epoch(int start, String name) {
    final seconds = data.getUint32(start, Endian.big);
    add(start, 4, name, '$seconds seconds since Unix epoch (UTC)');
  }

  void remaining() {
    final start = fields.isEmpty ? 0 : fields.last.end + 1;
    if (start < bytes.length) {
      add(
        start,
        bytes.length - start,
        'Undecoded bytes',
        'Unknown format or incomplete data; raw bytes preserved.',
      );
    }
  }

  if (uuid('3f') && bytes.length <= 2) {
    number(0, 1, 'Log page index', ' (zero-based)');
    if (bytes.length == 2) number(1, 1, 'Chunk index', ' (zero-based)');
    return fields;
  }
  if (uuid('3d') && bytes.length == 8) {
    tag(0, 8);
    return fields;
  }
  if (bytes.length < 4 || bytes[0] != 0x48 || bytes[1] != 0x43) {
    remaining();
    return fields;
  }
  add(0, 2, 'Packet signature', 'HC (HikerCircle)');
  number(2, 1, 'Protocol version');
  final version = bytes[2], type = bytes[3], length = bytes.length;
  // Characteristic-specific messages take precedence over shared type codes.
  final pair = uuid('38');
  final pairStatus = uuid('39') && version == 1 && length == 10;
  final kind = pair
      ? 'Pair request'
      : pairStatus
      ? 'Pairing status'
      : switch ((version, type, length)) {
          (2, 4, 23) => 'Paired button event',
          (2, 5, 24) => 'Location relay',
          (2, 5, 30) => 'Authenticated location handoff',
          (1, 6, 6) => 'Setup state',
          (1, 1, 9) => 'Legacy SOS',
          (1, 0x13, 22) => 'Safe-test challenge',
          (1, 0x13, 30) => 'Safe-test arm request',
          (1, 0x10, 26) => 'Log challenge',
          (1, 0x12, >= 8) => 'Log page',
          (1, 2, 26) => 'Team location',
          (1, 3, 22) => 'SOS help',
          _ => 'Unsupported type, version or length',
        };
  final status = switch (type) {
    1 => 'Ready',
    2 => 'Awaiting confirmation',
    3 => 'Paired',
    4 => 'Invalid request',
    5 => 'Confirmation expired',
    _ => 'Unknown status',
  };
  add(
    3,
    1,
    pairStatus ? 'Pairing status' : 'Message type',
    pairStatus ? '$type · $status' : '$type · $kind',
  );
  if (pair) {
    if (length >= 10) identifier(4, 6, 'Device ID');
    if (length > 10) {
      add(
        10,
        length - 10,
        'Permanent pairing key',
        'REDACTED · zero placeholders, not the actual key.',
      );
    }
  } else if (pairStatus) {
    identifier(4, 6, 'Device ID');
  } else if (kind == 'Paired button event') {
    add(
      4,
      1,
      'Button mode',
      '${bytes[4]} · ${switch (bytes[4]) {
        1 => 'SOS',
        2 => 'Test',
        _ => 'Unknown',
      }}',
    );
    identifier(5, 6, 'Device ID');
    number(11, 4, 'Event counter');
    tag(15, 8);
  } else if (kind == 'Location relay') {
    identifier(4, 6, 'Device ID');
    number(10, 4, 'Event counter');
    location(14, 18, 22);
  } else if (kind == 'Authenticated location handoff') {
    number(4, 4, 'Event counter');
    location(8, 12, 16);
    epoch(18, 'Captured time');
    tag(22, 8);
  } else if (kind == 'Setup state') {
    number(4, 1, 'Setup state code');
    number(5, 1, 'Time remaining', ' seconds');
  } else if (kind == 'Legacy SOS') {
    number(4, 1, 'SOS flag');
    number(5, 4, 'Event counter');
  } else if (kind.startsWith('Safe-test')) {
    identifier(4, 6, 'Device ID');
    number(10, 4, 'Next event ID');
    identifier(14, 8, 'Challenge nonce');
    if (length == 30) tag(22, 8);
  } else if (kind == 'Log challenge') {
    identifier(4, 6, 'Device ID');
    identifier(10, 16, 'Challenge nonce');
  } else if (kind == 'Log page') {
    number(4, 1, 'Bytes per record');
    number(5, 1, 'Total records');
    number(6, 1, 'Page index', ' (zero-based)');
    number(7, 1, 'Records in this page');
    if (bytes[4] == 20) {
      for (var i = 0; i < bytes[7] && 8 + (i + 1) * 20 <= length; i++) {
        final p = 8 + i * 20;
        final prefix = 'Record ${i + 1} · ';
        number(p, 4, '${prefix}sequence');
        number(p + 4, 4, '${prefix}uptime', ' ms');
        epoch(p + 8, '${prefix}time');
        number(p + 12, 4, '${prefix}event ID');
        number(p + 16, 1, '${prefix}event type');
        number(p + 17, 1, '${prefix}reset reason code');
        number(p + 18, 2, '${prefix}detail');
      }
    }
  } else if (kind == 'Team location') {
    number(4, 4, 'Team hash');
    number(8, 4, 'Phone hash');
    location(12, 16, 20);
    epoch(22, 'Captured time');
  } else if (kind == 'SOS help') {
    number(4, 4, 'Phone hash');
    location(8, 12, 16);
    epoch(18, 'Captured time');
  }
  remaining();
  return fields;
}
