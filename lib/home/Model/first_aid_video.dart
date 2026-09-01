class FirstAidVideo {
  const FirstAidVideo({
    required this.title,
    required this.storagePath,
    required this.durationLabel,
    required this.attribution,
    required this.license,
    required this.sourceUrl,
    required this.version,
    this.expectedBytes,
  });

  factory FirstAidVideo.fromJson(Map<String, dynamic> json) {
    return FirstAidVideo(
      title: _stringFrom(json['title']),
      storagePath: _stringFrom(json['storagePath']),
      durationLabel: _stringFrom(json['durationLabel']),
      attribution: _stringFrom(json['attribution']),
      license: _stringFrom(json['license']),
      sourceUrl: _stringFrom(json['sourceUrl']),
      version: _intFrom(json['version'], fallback: 1),
      expectedBytes: _nullableIntFrom(json['expectedBytes']),
    );
  }

  final String title;
  final String storagePath;
  final String durationLabel;
  final String attribution;
  final String license;
  final String sourceUrl;
  final int version;
  final int? expectedBytes;

  String cacheFileName(String topicId) =>
      '${_safeSegment(topicId)}_v$version.mp4';

  static String _stringFrom(Object? value) =>
      value is String ? value.trim() : '';

  static int _intFrom(Object? value, {required int fallback}) {
    if (value is int) return value;
    return int.tryParse('$value') ?? fallback;
  }

  static int? _nullableIntFrom(Object? value) {
    if (value is int) return value;
    return value == null ? null : int.tryParse('$value');
  }

  static String _safeSegment(String value) {
    final cleaned = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    return cleaned.isEmpty ? 'tutorial' : cleaned;
  }
}
