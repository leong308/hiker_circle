// ButtonDebugEntry records application BLE payloads and their decoded diagnostic values.
import 'dart:typed_data';

import 'button_debug_field.dart';

/// Application-visible BLE payloads, not radio/link-layer frames.
class ButtonDebugEntry {
  ButtonDebugEntry({
    required this.timestamp,
    required this.direction,
    required this.operation,
    required this.deviceId,
    required this.characteristic,
    required this.status,
    required this.bytes,
    required this.interpretation,
  });

  factory ButtonDebugEntry.fromEvent(Map<Object?, Object?> event) {
    final characteristic = '${event['characteristic'] ?? ''}';
    final bytes = buttonDebugSafePayload(
      (event['bytes'] as List? ?? const [])
          .whereType<int>()
          .map((v) => v & 255)
          .toList(),
      characteristic,
    );
    final message = '${event['message'] ?? ''}';
    return ButtonDebugEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (event['timestampMillis'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        isUtc: true,
      ),
      direction: '${event['direction'] ?? 'LOCAL'}',
      operation: '${event['operation'] ?? 'event'}',
      deviceId: '${event['deviceId'] ?? ''}',
      characteristic: characteristic,
      status: '${event['status'] ?? ''}',
      bytes: bytes,
      interpretation: [
        if (message.isNotEmpty) message,
        decodeButtonPayload(bytes, characteristic),
      ].where((s) => s.isNotEmpty).join('\n'),
    );
  }

  final DateTime timestamp;
  final String direction,
      operation,
      deviceId,
      characteristic,
      status,
      interpretation;
  final Uint8List bytes;
  String get hex => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  Map<String, Object?> toRow(String sessionId, int sequence) => {
    'session_id': sessionId,
    'sequence': sequence,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'direction': direction,
    'operation': operation,
    'device_id': deviceId,
    'characteristic': characteristic,
    'status': status,
    'payload': bytes,
    'interpretation': interpretation,
  };

  static String formatRow(Map<String, Object?> row) {
    final characteristic = '${row['characteristic'] ?? ''}';
    final bytes = buttonDebugSafePayload(
      (row['payload'] as List).cast<int>(),
      characteristic,
    );
    final hex = buttonPayloadHex(bytes);
    final fields = decodeButtonFields(bytes, characteristic);
    final table = fields.isEmpty
        ? ''
        : 'Byte offsets are zero-based; multi-byte numbers are big-endian.\n'
              '| Bytes | HEX | Meaning / decoded value |\n'
              '| --- | --- | --- |\n'
              '${fields.map((f) => '| ${f.range} | ${f.hex} | ${f.name}: ${f.value} |').join('\n')}\n';
    return '#${row['sequence']} ${row['timestamp']} ${row['direction']} ${row['operation']}\n'
        'Device: ${row['device_id']} | Characteristic: ${row['characteristic']} | Status: ${row['status']}\n'
        'HEX (${bytes.length} bytes): $hex\nDEC: ${bytes.join(' ')}\n$table${row['interpretation']}\n';
  }
}

/// Decode application payload fields for inspection without treating them as BLE radio frames.
String decodeButtonPayload(Uint8List bytes, String characteristic) {
  if (bytes.isEmpty) {
    return 'No application payload (control operation or status only).';
  }
  final c = characteristic.toLowerCase();
  final d = ByteData.sublistView(bytes);
  String hex(int a, int b) => bytes
      .sublist(a, b)
      .map((v) => v.toRadixString(16).padLeft(2, '0'))
      .join('')
      .toUpperCase();
  int u32(int p) => d.getUint32(p, Endian.big);
  double coord(int p) => d.getInt32(p, Endian.big) / 1e7;
  bool uuid(String prefix) => c.startsWith('7e2a1d$prefix');
  if (uuid('3f') && bytes.length <= 2) {
    return 'Log page index=${bytes[0]}${bytes.length == 2 ? ', chunk index=${bytes[1]}' : ''} (zero-based).';
  }
  if (uuid('3d') && bytes.length == 8) {
    return 'Log authentication: truncated HMAC-SHA256 tag=${hex(0, 8)}. Authentication is verified by the device, not by this viewer.';
  }
  if (bytes.length < 4 || bytes[0] != 0x48 || bytes[1] != 0x43) {
    return 'Unrecognized payload or partial log chunk; raw bytes preserved.';
  }
  final header =
      'Magic=HC, version=${bytes[2]}, type/status=0x${bytes[3].toRadixString(16)}.';
  if (uuid('38')) {
    return '$header Pair request; device ID=${bytes.length >= 10 ? hex(4, 10) : 'truncated'}. Permanent key bytes [10..41] are redacted (zero placeholders), not actual zero values.';
  }
  if (uuid('39') && bytes.length == 10 && bytes[2] == 1) {
    final name = switch (bytes[3]) {
      1 => 'ready',
      2 => 'awaiting confirmation',
      3 => 'paired',
      4 => 'invalid request',
      5 => 'confirmation expired',
      _ => 'unknown',
    };
    return '$header Pairing status=${bytes[3]} ($name), device ID=${hex(4, 10)}.';
  }
  if (bytes[2] == 2 && bytes[3] == 4 && bytes.length == 23) {
    return '$header Paired button: mode=${bytes[4]} (${switch (bytes[4]) {
      1 => 'SOS',
      2 => 'test',
      _ => 'unknown',
    }}), device ID=${hex(5, 11)}, event counter=${u32(11)}, authentication tag=${hex(15, 23)}. Raw reception alone does not prove authentication.';
  }
  if (bytes[2] == 2 && bytes[3] == 5) {
    if (bytes.length == 24) {
      return '$header Location relay: device ID=${hex(4, 10)}, event=${u32(10)}, latitude=${coord(14)}, longitude=${coord(18)}, accuracy=${d.getUint16(22) / 10} m.';
    }
    if (bytes.length == 30) {
      return '$header Authenticated location handoff: event=${u32(4)}, latitude=${coord(8)}, longitude=${coord(12)}, accuracy=${d.getUint16(16) / 10} m, captured epoch seconds=${u32(18)}, HMAC tag=${hex(22, 30)}.';
    }
  }
  if (bytes[2] == 1) {
    if (bytes[3] == 6 && bytes.length == 6) {
      return '$header Setup state=${bytes[4]}, remaining=${bytes[5]} seconds.';
    }
    if (bytes[3] == 1 && bytes.length == 9) {
      return '$header Legacy SOS: flag=${bytes[4]}, event counter=${u32(5)}.';
    }
    if (bytes[3] == 0x13 && (bytes.length == 22 || bytes.length == 30)) {
      return '$header Safe-test ${bytes.length == 22 ? 'challenge' : 'authenticated arm request'}: device ID=${hex(4, 10)}, next event ID=${u32(10)}, nonce=${hex(14, 22)}${bytes.length == 30 ? ', HMAC tag=${hex(22, 30)}' : ''}.';
    }
    if (bytes[3] == 0x10 && bytes.length == 26) {
      return '$header Log challenge: device ID=${hex(4, 10)}, nonce=${hex(10, 26)}.';
    }
    if (bytes[3] == 0x12 && bytes.length >= 8) {
      final lines = <String>[
        '$header Log page: record bytes=${bytes[4]}, total records=${bytes[5]}, page=${bytes[6]}, records in page=${bytes[7]}.',
      ];
      if (bytes[4] == 20) {
        for (var i = 0; i < bytes[7] && 8 + (i + 1) * 20 <= bytes.length; i++) {
          final p = 8 + i * 20;
          lines.add(
            'Record $i: sequence=${u32(p)}, uptime=${u32(p + 4)} ms, epoch=${u32(p + 8)}, event=${u32(p + 12)}, type=${bytes[p + 16]}, reset reason=${bytes[p + 17]}, detail=${d.getUint16(p + 18)}.',
          );
        }
      }
      if (bytes.length != 8 + bytes[7] * bytes[4]) {
        lines.add(
          'Partial/malformed page; subsequent chunks remain separate raw entries.',
        );
      }
      return lines.join('\n');
    }
    if (bytes[3] == 2 && bytes.length == 26) {
      return '$header Team location: team hash=${u32(4)}, phone hash=${u32(8)}, latitude=${coord(12)}, longitude=${coord(16)}, accuracy=${d.getUint16(20) / 10} m, epoch seconds=${u32(22)}.';
    }
    if (bytes[3] == 3 && bytes.length == 22) {
      return '$header SOS help: phone hash=${u32(4)}, latitude=${coord(8)}, longitude=${coord(12)}, accuracy=${d.getUint16(16) / 10} m, epoch seconds=${u32(18)}.';
    }
  }
  return '$header Unsupported type/version/length (${bytes.length} bytes); raw bytes preserved without guessing fields.';
}
