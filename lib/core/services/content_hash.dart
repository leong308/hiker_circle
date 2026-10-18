// canonicalContent and stableContentHash produce repeatable JSON hashes for cache validation and
// unchanged-payload detection.
import 'dart:convert';
import 'package:crypto/crypto.dart';

Object? canonicalContent(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: canonicalContent(value[key])};
  }
  if (value is Iterable) return value.map(canonicalContent).toList();
  if (value is DateTime) return value.toUtc().toIso8601String();
  return value;
}

String stableContentHash(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(canonicalContent(value)))).toString();
