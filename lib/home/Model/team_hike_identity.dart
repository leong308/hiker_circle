import 'dart:math' as math;

/// The shared team capacity and fixed palette, mirrored by the server's team policy.
abstract final class TeamHikeIdentity {
  static const maximumHikers = 30;
  static const colors = <int>[
    0xff34a853,
    0xffe6194b,
    0xff4363d8,
    0xfff58231,
    0xff911eb4,
    0xff42d4f4,
    0xfff032e6,
    0xffbfef45,
    0xff469990,
    0xff9a6324,
    0xff800000,
    0xff808000,
    0xff000075,
    0xffa9a9a9,
    0xffffe119,
    0xfffabed4,
    0xffaaffc3,
    0xffffd8b1,
    0xffdcbeff,
    0xffa6cee3,
    0xffd95f02,
    0xff1b9e77,
    0xff7570b3,
    0xffe7298a,
    0xff66a61e,
    0xffe6ab02,
    0xffa6761d,
    0xff666666,
    0xffff6f61,
    0xff00a6a6,
  ];

  /// Normalizes a roster identity independently of its display name and the viewing hiker.
  static String key(Object? phone) =>
      phone.toString().replaceAll(RegExp(r'\D'), '');

  /// Preserves saved assignments and deterministically fills unused slots for legacy teams.
  static Map<String, int> assignments(
    List<Map<String, dynamic>> participants,
    Object? saved,
  ) {
    final stored = saved is Map ? saved : const {};
    final ordered = [...participants]
      ..sort((a, b) {
        final hostOrder =
            (b['isHost'] == true ? 1 : 0) - (a['isHost'] == true ? 1 : 0);
        return hostOrder != 0
            ? hostOrder
            : participantKey(a).compareTo(participantKey(b));
      });
    final result = <String, int>{}, used = <int>{};
    for (final participant in ordered) {
      final phone = participantKey(participant), value = stored[phone];
      if (phone.isNotEmpty &&
          value is int &&
          colors.contains(value) &&
          used.add(value)) {
        result[phone] = value;
      }
    }
    for (final participant in ordered) {
      final phone = participantKey(participant);
      if (phone.isEmpty || result.containsKey(phone)) continue;
      final unused = colors.where((value) => !used.contains(value)).firstOrNull;
      final buddy = participant['buddy'] is Map
          ? participant['buddy'] as Map
          : const {};
      final color =
          unused ??
          (buddy['avatarColorValue'] is int
              ? buddy['avatarColorValue'] as int
              : colors.first);
      result[phone] = color;
      used.add(color);
    }
    return result;
  }

  /// Reads old nested or current top-level roster identifiers.
  static String participantKey(Map<String, dynamic> participant) {
    final buddy = participant['buddy'] is Map
        ? participant['buddy'] as Map
        : const {};
    final direct = key(participant['phoneNumber'] ?? '');
    return direct.isNotEmpty ? direct : key(buddy['phoneNumber'] ?? '');
  }

  /// Chooses readable initials for every light and dark palette colour.
  static int foreground(int color) {
    /// Converts an sRGB channel to linear light for readable avatar initials.
    double channel(int shift) {
      final value = ((color >> shift) & 255) / 255;
      return value <= .04045
          ? value / 12.92
          : math.pow((value + .055) / 1.055, 2.4).toDouble();
    }

    final luminance =
        .2126 * channel(16) + .7152 * channel(8) + .0722 * channel(0);
    return luminance > .179 ? 0xff000000 : 0xffffffff;
  }
}
