import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class OtpChallenge {
  OtpChallenge({
    required this.phoneNumber,
    required this.issuedAt,
    required this.expiresAt,
    required this.nonce,
    required this.codeHash,
    this.code,
  });

  factory OtpChallenge.generate({required String phoneNumber}) {
    final issuedAt = DateTime.now().toUtc();
    final expiresAt = issuedAt.add(defaultTtl);
    final random = Random.secure();
    final entropy = List<int>.generate(16, (_) => random.nextInt(256));
    final seed =
        '$phoneNumber:${issuedAt.microsecondsSinceEpoch}:'
        '${base64UrlEncode(entropy)}';
    final seedDigest = sha256.convert(utf8.encode(seed)).bytes;
    final number = seedDigest
        .take(6)
        .fold<int>(0, (value, byte) => ((value << 5) + byte) & 0x7fffffff);
    final code = (number % 1000000).toString().padLeft(6, '0');
    final nonce = base64UrlEncode(entropy);

    return OtpChallenge(
      phoneNumber: phoneNumber,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      nonce: nonce,
      code: code,
      codeHash: _hashCode(
        phoneNumber: phoneNumber,
        code: code,
        issuedAt: issuedAt,
        nonce: nonce,
      ),
    );
  }

  static const defaultTtl = Duration(minutes: 5);

  final String phoneNumber;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String nonce;
  final String codeHash;
  final String? code;

  Duration get ttl => expiresAt.difference(issuedAt);

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  OtpChallenge hideCode() {
    return OtpChallenge(
      phoneNumber: phoneNumber,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      nonce: nonce,
      codeHash: codeHash,
    );
  }

  bool verify(String input) {
    if (isExpired) {
      return false;
    }

    final candidateHash = _hashCode(
      phoneNumber: phoneNumber,
      code: input.trim(),
      issuedAt: issuedAt,
      nonce: nonce,
    );
    return _constantTimeEquals(codeHash, candidateHash);
  }

  static String _hashCode({
    required String phoneNumber,
    required String code,
    required DateTime issuedAt,
    required String nonce,
  }) {
    final payload =
        '$phoneNumber:$code:${issuedAt.microsecondsSinceEpoch}:'
        '$nonce';
    return sha256.convert(utf8.encode(payload)).toString();
  }

  static bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) {
      return false;
    }

    var mismatch = 0;
    for (var index = 0; index < left.length; index++) {
      mismatch |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return mismatch == 0;
  }
}
