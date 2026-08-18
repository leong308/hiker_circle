import 'dart:async';
import 'dart:convert';

import 'package:emergency_helpline/emergency_helpline.dart';
import 'package:http/http.dart' as http;

import '../config/google_api_config.dart';

abstract interface class EmergencyNumberResolver {
  Future<EmergencyDialTarget> resolve({
    double? latitude,
    double? longitude,
    String? fallbackCountryCode,
  });
}

class EmergencyDialTarget {
  const EmergencyDialTarget({
    required this.number,
    required this.countryCode,
    required this.countryName,
    required this.isLocationBased,
    required this.isFallback,
  });

  final String number;
  final String? countryCode;
  final String? countryName;
  final bool isLocationBased;
  final bool isFallback;

  String get description {
    final region = countryName?.trim();
    if (isFallback) {
      return region == null || region.isEmpty
          ? 'International mobile emergency fallback'
          : '$region emergency fallback';
    }
    return region == null || region.isEmpty
        ? 'Local ambulance service'
        : '$region ambulance service';
  }
}

class EmergencyCountryNumbers {
  const EmergencyCountryNumbers({
    required this.countryName,
    required this.ambulance,
  });

  final String countryName;
  final String ambulance;
}

typedef EmergencyCountryLookup =
    Future<EmergencyCountryNumbers?> Function(String countryCode);

class EmergencyNumberService implements EmergencyNumberResolver {
  EmergencyNumberService({
    http.Client? client,
    EmergencyCountryLookup? countryLookup,
    String? googleGeocodingApiKey,
    String? geoapifyApiKey,
  }) : _client = client,
       _countryLookup = countryLookup ?? _lookupBundledCountry,
       _googleGeocodingApiKey =
           googleGeocodingApiKey ?? GoogleApiConfig.geocodingApiKey,
       _geoapifyApiKey = geoapifyApiKey ?? GoogleApiConfig.geoapifyApiKey;

  static const Duration _requestTimeout = Duration(seconds: 8);
  static const String _internationalMobileFallback = '112';

  final http.Client? _client;
  final EmergencyCountryLookup _countryLookup;
  final String _googleGeocodingApiKey;
  final String _geoapifyApiKey;

  @override
  Future<EmergencyDialTarget> resolve({
    double? latitude,
    double? longitude,
    String? fallbackCountryCode,
  }) async {
    final hasCoordinate = _isCoordinateValid(latitude, longitude);
    _CountryMatch? country;

    if (hasCoordinate) {
      country = await _countryAt(latitude!, longitude!);
    }

    final normalizedFallbackCode = _normalizeCountryCode(fallbackCountryCode);
    country ??= normalizedFallbackCode == null
        ? null
        : _CountryMatch(code: normalizedFallbackCode, name: null);

    final countryCode = country?.code;
    if (countryCode != null) {
      try {
        final numbers = await _countryLookup(countryCode);
        final number = _dialableNumber(numbers?.ambulance);
        if (number != null) {
          return EmergencyDialTarget(
            number: number,
            countryCode: countryCode,
            countryName:
                _nonEmpty(country?.name) ??
                _nonEmpty(numbers?.countryName) ??
                countryCode,
            isLocationBased: hasCoordinate && country?.fromCoordinate == true,
            isFallback: false,
          );
        }
      } catch (_) {
        // Keep the emergency action usable if the bundled catalogue cannot load.
      }
    }

    return EmergencyDialTarget(
      number: _internationalMobileFallback,
      countryCode: countryCode,
      countryName: _nonEmpty(country?.name) ?? countryCode,
      isLocationBased: hasCoordinate && country?.fromCoordinate == true,
      isFallback: true,
    );
  }

  Future<_CountryMatch?> _countryAt(double latitude, double longitude) async {
    final client = _client ?? http.Client();
    final ownsClient = _client == null;
    try {
      final lookups = <Future<_CountryMatch?>>[
        if (_googleGeocodingApiKey.trim().isNotEmpty)
          _countryFromGoogle(client, latitude, longitude),
        if (_geoapifyApiKey.trim().isNotEmpty)
          _countryFromGeoapify(client, latitude, longitude),
      ];
      if (lookups.isEmpty) return null;

      final completer = Completer<_CountryMatch?>();
      var remaining = lookups.length;
      for (final lookup in lookups) {
        unawaited(
          lookup.then((match) {
            if (match != null && !completer.isCompleted) {
              completer.complete(match);
            }
            remaining -= 1;
            if (remaining == 0 && !completer.isCompleted) {
              completer.complete(null);
            }
          }),
        );
      }
      return await completer.future.timeout(
        _requestTimeout,
        onTimeout: () => null,
      );
    } finally {
      if (ownsClient) client.close();
    }
  }

  Future<_CountryMatch?> _countryFromGoogle(
    http.Client client,
    double latitude,
    double longitude,
  ) async {
    final key = _googleGeocodingApiKey.trim();
    if (key.isEmpty) return null;
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '$latitude,$longitude',
        'result_type': 'country',
        'key': key,
      });
      final response = await client.get(uri).timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final results = decoded['results'];
      if (results is! List) return null;
      for (final result in results.whereType<Map<String, dynamic>>()) {
        final match = _countryFromAddressComponents(
          result['address_components'],
        );
        if (match != null) return match;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<_CountryMatch?> _countryFromGeoapify(
    http.Client client,
    double latitude,
    double longitude,
  ) async {
    final key = _geoapifyApiKey.trim();
    if (key.isEmpty) return null;
    try {
      final uri = Uri.https('api.geoapify.com', '/v1/geocode/reverse', {
        'lat': '$latitude',
        'lon': '$longitude',
        'type': 'country',
        'format': 'json',
        'apiKey': key,
      });
      final response = await client.get(uri).timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final results = decoded['results'];
      if (results is! List || results.isEmpty) return null;
      final first = results.first;
      if (first is! Map<String, dynamic>) return null;
      final code = _normalizeCountryCode(first['country_code']?.toString());
      if (code == null) return null;
      return _CountryMatch(
        code: code,
        name: _nonEmpty(first['country']?.toString()),
        fromCoordinate: true,
      );
    } catch (_) {
      return null;
    }
  }

  static _CountryMatch? _countryFromAddressComponents(Object? raw) {
    if (raw is! List) return null;
    for (final component in raw.whereType<Map<String, dynamic>>()) {
      final types = component['types'];
      if (types is! List || !types.contains('country')) continue;
      final code = _normalizeCountryCode(component['short_name']?.toString());
      if (code == null) continue;
      return _CountryMatch(
        code: code,
        name: _nonEmpty(component['long_name']?.toString()),
        fromCoordinate: true,
      );
    }
    return null;
  }

  static Future<EmergencyCountryNumbers?> _lookupBundledCountry(
    String countryCode,
  ) async {
    final country = await EmergencyHelpline.instance.getCountry(countryCode);
    if (country == null) return null;
    return EmergencyCountryNumbers(
      countryName: country.countryName,
      ambulance: country.ambulance,
    );
  }

  static bool _isCoordinateValid(double? latitude, double? longitude) {
    return latitude != null &&
        longitude != null &&
        latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  static String? _normalizeCountryCode(String? value) {
    final code = value?.trim().toUpperCase();
    if (code == null || !RegExp(r'^[A-Z]{2}$').hasMatch(code)) return null;
    return code;
  }

  static String? _dialableNumber(String? value) {
    final number = value?.replaceAll(RegExp(r'[^0-9+]'), '');
    if (number == null || number.length < 2) return null;
    return number;
  }

  static String? _nonEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

class _CountryMatch {
  const _CountryMatch({
    required this.code,
    required this.name,
    this.fromCoordinate = false,
  });

  final String code;
  final String? name;
  final bool fromCoordinate;
}
