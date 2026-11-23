part of '../me_page_feature.dart';

/// Represents qr matrix.
class _QrMatrix {
  /// Creates qr matrix using .
  _QrMatrix._(this.modules);

  static const int _version = 4;
  static const int _size = 17 + _version * 4;
  static const int _dataCodewords = 80;
  static const int _ecCodewords = 20;
  static const int _formatBitsLowMaskZero = 0x77C4;

  final List<List<bool>> modules;

  /// Computes encode.
  static _QrMatrix encode(String text) {
    final data = _buildDataCodewords(text);
    final errorCorrection = _computeRemainder(
      data,
      _computeDivisor(_ecCodewords),
    );
    final codewords = [...data, ...errorCorrection];
    final qr = _MutableQr();
    qr.drawFunctionPatterns();
    qr.drawCodewords(codewords);
    qr.applyMask();
    qr.drawFormatBits(_formatBitsLowMaskZero);
    return _QrMatrix._(qr.modules);
  }

  /// Builds data codewords.
  static List<int> _buildDataCodewords(String text) {
    final bytes = utf8.encode(text);
    if (bytes.length > 73) {
      throw ArgumentError('Profile link is too long for the local QR encoder.');
    }

    final bits = <bool>[];
    _appendBits(bits, 0x4, 4);
    _appendBits(bits, bytes.length, 8);
    for (final byte in bytes) {
      _appendBits(bits, byte, 8);
    }

    final capacityBits = _dataCodewords * 8;
    final terminator = (capacityBits - bits.length).clamp(0, 4);
    _appendBits(bits, 0, terminator);
    while (bits.length % 8 != 0) {
      bits.add(false);
    }

    final result = <int>[];
    for (var i = 0; i < bits.length; i += 8) {
      var value = 0;
      for (var j = 0; j < 8; j++) {
        value = (value << 1) | (bits[i + j] ? 1 : 0);
      }
      result.add(value);
    }

    var pad = 0xEC;
    while (result.length < _dataCodewords) {
      result.add(pad);
      pad ^= 0xEC ^ 0x11;
    }
    return result;
  }

  /// Computes append bits.
  static void _appendBits(List<bool> bits, int value, int length) {
    for (var i = length - 1; i >= 0; i--) {
      bits.add(((value >> i) & 1) != 0);
    }
  }

  /// Computes divisor.
  static List<int> _computeDivisor(int degree) {
    final result = List<int>.filled(degree, 0);
    result[degree - 1] = 1;
    var root = 1;
    for (var i = 0; i < degree; i++) {
      for (var j = 0; j < result.length; j++) {
        result[j] = _multiply(result[j], root);
        if (j + 1 < result.length) {
          result[j] ^= result[j + 1];
        }
      }
      root = _multiply(root, 0x02);
    }
    return result;
  }

  /// Computes remainder.
  static List<int> _computeRemainder(List<int> data, List<int> divisor) {
    final result = List<int>.filled(divisor.length, 0, growable: true);
    for (final byte in data) {
      final factor = byte ^ result.removeAt(0);
      result.add(0);
      for (var i = 0; i < result.length; i++) {
        result[i] ^= _multiply(divisor[i], factor);
      }
    }
    return result;
  }

  /// Computes multiply.
  static int _multiply(int x, int y) {
    var z = 0;
    for (var i = 7; i >= 0; i--) {
      z = (z << 1) ^ ((z >> 7) * 0x11D);
      if (((y >> i) & 1) != 0) {
        z ^= x;
      }
    }
    return z & 0xFF;
  }
}

/// Represents mutable qr.
class _MutableQr {
  final List<List<bool>> modules = List.generate(
    _QrMatrix._size,
    (_) => List<bool>.filled(_QrMatrix._size, false),
  );
  final List<List<bool>> _isFunction = List.generate(
    _QrMatrix._size,
    (_) => List<bool>.filled(_QrMatrix._size, false),
  );

  /// Computes draw function patterns.
  void drawFunctionPatterns() {
    _drawFinder(3, 3);
    _drawFinder(_QrMatrix._size - 4, 3);
    _drawFinder(3, _QrMatrix._size - 4);

    for (var i = 0; i < _QrMatrix._size; i++) {
      if (!_isFunction[6][i]) {
        _setFunction(i, 6, i.isEven);
      }
      if (!_isFunction[i][6]) {
        _setFunction(6, i, i.isEven);
      }
    }

    _drawAlignment(26, 26);
    _setFunction(8, 4 * _QrMatrix._version + 9, true);
    drawFormatBits(0);
  }

  /// Computes draw finder.
  void _drawFinder(int centerX, int centerY) {
    for (var dy = -4; dy <= 4; dy++) {
      for (var dx = -4; dx <= 4; dx++) {
        final x = centerX + dx;
        final y = centerY + dy;
        if (x < 0 || x >= _QrMatrix._size || y < 0 || y >= _QrMatrix._size) {
          continue;
        }
        final distance = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
        _setFunction(x, y, distance != 2 && distance != 4);
      }
    }
  }

  /// Computes draw alignment.
  void _drawAlignment(int centerX, int centerY) {
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        final distance = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
        _setFunction(centerX + dx, centerY + dy, distance != 1);
      }
    }
  }

  /// Computes draw format bits.
  void drawFormatBits(int bits) {
    for (var i = 0; i <= 5; i++) {
      _setFunction(8, i, _bit(bits, i));
    }
    _setFunction(8, 7, _bit(bits, 6));
    _setFunction(8, 8, _bit(bits, 7));
    _setFunction(7, 8, _bit(bits, 8));
    for (var i = 9; i < 15; i++) {
      _setFunction(14 - i, 8, _bit(bits, i));
    }
    for (var i = 0; i < 8; i++) {
      _setFunction(_QrMatrix._size - 1 - i, 8, _bit(bits, i));
    }
    for (var i = 8; i < 15; i++) {
      _setFunction(8, _QrMatrix._size - 15 + i, _bit(bits, i));
    }
  }

  /// Computes draw codewords.
  void drawCodewords(List<int> codewords) {
    final bits = <bool>[];
    for (final codeword in codewords) {
      for (var i = 7; i >= 0; i--) {
        bits.add(((codeword >> i) & 1) != 0);
      }
    }

    var bitIndex = 0;
    var upward = true;
    for (var right = _QrMatrix._size - 1; right >= 1; right -= 2) {
      if (right == 6) {
        right = 5;
      }
      for (var vert = 0; vert < _QrMatrix._size; vert++) {
        final y = upward ? _QrMatrix._size - 1 - vert : vert;
        for (var dx = 0; dx < 2; dx++) {
          final x = right - dx;
          if (_isFunction[y][x]) {
            continue;
          }
          modules[y][x] = bitIndex < bits.length && bits[bitIndex];
          bitIndex++;
        }
      }
      upward = !upward;
    }
  }

  /// Applies mask.
  void applyMask() {
    for (var y = 0; y < _QrMatrix._size; y++) {
      for (var x = 0; x < _QrMatrix._size; x++) {
        if (!_isFunction[y][x] && (x + y).isEven) {
          modules[y][x] = !modules[y][x];
        }
      }
    }
  }

  /// Sets function.
  void _setFunction(int x, int y, bool isDark) {
    modules[y][x] = isDark;
    _isFunction[y][x] = true;
  }

  /// Computes bit.
  static bool _bit(int value, int index) {
    return ((value >> index) & 1) != 0;
  }
}

/// Represents achievement guidance.
class _AchievementGuidance {
  /// Creates achievement guidance.
  const _AchievementGuidance({
    required this.whyItMatters,
    required this.whatCounts,
  });

  final String whyItMatters;
  final String whatCounts;

  /// Computes goal progress.
  String goalProgress(_AchievementProfileItem item) {
    if (!item.isCumulative) {
      return 'Complete this action once to unlock the badge.';
    }
    final remaining = (item.targetCount - item.progressCount).clamp(
      0,
      item.targetCount,
    );
    return '${AchievementCatalog.quantity(item.metricKey, remaining)} remaining to reach ${AchievementCatalog.quantity(item.metricKey, item.targetCount)}.';
  }

  /// Creates achievement guidance using for item.
  factory _AchievementGuidance.forItem(_AchievementProfileItem item) {
    return _AchievementGuidance(
      whyItMatters: item.whyItMatters,
      whatCounts: item.whatCounts,
    );
  }
}

/// Represents achievement profile item.
class _AchievementProfileItem {
  /// Creates achievement profile item.
  const _AchievementProfileItem({
    required this.achievementId,
    required this.title,
    required this.condition,
    required this.whyItMatters,
    required this.whatCounts,
    required this.rewardRecognition,
    required this.category,
    required this.iconName,
    required this.rewardPoints,
    required this.pointsAwarded,
    required this.rewardType,
    required this.metricKey,
    required this.progressCount,
    required this.targetCount,
    required this.sortOrder,
    required this.accentColorValue,
    required this.isUnlocked,
    required this.awardedAt,
    required this.source,
  });

  final String achievementId;
  final String title;
  final String condition;
  final String whyItMatters, whatCounts, rewardRecognition;
  final String category;
  final String iconName;
  final int rewardPoints;
  final int pointsAwarded;
  final String rewardType;
  final String metricKey;
  final int progressCount;
  final int targetCount;
  final int sortOrder;
  final int accentColorValue;
  final bool isUnlocked;
  final DateTime? awardedAt;
  final Map<String, dynamic> source;

  /// The rule flag is authoritative even when an older award remains earned.
  bool get isActive => source['isActive'] != false;

  /// Returns is cumulative.
  bool get isCumulative => rewardType == 'cumulative';

  /// Returns progress.
  double get progress => targetCount <= 0
      ? 0
      : (progressCount / targetCount).clamp(0, 1).toDouble();

  /// Creates achievement profile item using from row.
  factory _AchievementProfileItem.fromRow(Map<String, dynamic> row) {
    final title = _mapString(row['title']);
    final condition = _mapString(row['condition']);
    final category = _mapString(row['category']);
    final iconName = _mapString(row['iconName']);

    return _AchievementProfileItem(
      achievementId: _mapString(row['achievementId']),
      source: Map<String, dynamic>.from(row),
      title: title.isEmpty ? 'Achievement' : title,
      condition: condition.isEmpty
          ? AchievementCatalog.goal(
              _mapString(row['metricKey']),
              _mapInt(row['targetCount']),
            )
          : condition,
      whyItMatters: AchievementCatalog.content(row)['whyItMatters']!,
      whatCounts: AchievementCatalog.content(row)['whatCounts']!,
      rewardRecognition: AchievementCatalog.content(row)['rewardRecognition']!,
      category: category.isEmpty ? 'Safety' : category,
      iconName: iconName.isEmpty ? 'emoji_events' : iconName,
      rewardPoints: _mapInt(row['rewardPoints']),
      pointsAwarded: _mapInt(row['pointsAwarded']),
      rewardType: _mapString(row['rewardType']) == 'cumulative'
          ? 'cumulative'
          : 'one_time',
      metricKey: _mapString(row['metricKey']),
      progressCount: _mapInt(row['progressCount']),
      targetCount: _mapInt(row['targetCount']).clamp(1, 1000000000),
      sortOrder: _mapInt(row['sortOrder']),
      accentColorValue: _mapInt(row['accentColorValue']),
      isUnlocked: row['isUnlocked'] == true,
      awardedAt: DateTime.tryParse(_mapString(row['awardedAtLocal'])),
    );
  }
}

/// Computes achievement items from rows.
List<_AchievementProfileItem> _achievementItemsFromRows(
  List<Map<String, dynamic>> rows, {
  bool includeInactive = false,
}) {
  return rows
      .where(
        (row) =>
            AchievementCatalog.visible(row) &&
            (includeInactive || row['isActive'] != false),
      )
      .map(_AchievementProfileItem.fromRow)
      .toList()
    ..sort((left, right) {
      final orderComparison = left.sortOrder.compareTo(right.sortOrder);
      if (orderComparison != 0) {
        return orderComparison;
      }
      return left.title.compareTo(right.title);
    });
}

/// Computes map string.
String _mapString(Object? value) {
  return value is String ? value : '';
}

/// Computes map int.
int _mapInt(Object? value) {
  return value is num && value.isFinite ? value.toInt() : 0;
}

/// Formats achievement date.
String _formatAchievementDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = date.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

/// Represents profile history item.
class _ProfileHistoryItem {
  /// Creates profile history item.
  const _ProfileHistoryItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.meta = '',
    this.photoURL = '',
    this.buddyPhoneNumber = '',
  });

  final String title;
  final String subtitle;
  final String meta;
  final IconData icon;
  final String photoURL;
  final String buddyPhoneNumber;
}

/// Retired badges stay hidden while their previously awarded points remain part of the hiker's rank.
int _retainedAchievementPoints(
  List<Map<String, dynamic>> rows, {
  bool includeInactive = false,
}) => rows
    .where(
      (row) =>
          row['isUnlocked'] == true &&
          (!AchievementCatalog.visible(row) ||
              (!includeInactive && row['isActive'] == false)),
    )
    .fold<int>(0, (total, row) => total + _mapInt(row['pointsAwarded']));
