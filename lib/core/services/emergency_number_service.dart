// EmergencyNumberService resolves country-specific emergency dial targets and keeps a fallback
// available for the SOS calling flow.
import 'private_provider_client.dart';
import 'dart:async';
import 'dart:convert';

import 'package:emergency_helpline/emergency_helpline.dart';
import 'package:http/http.dart' as http;

import '../config/google_api_config.dart';

/// Represents emergency number resolver.
abstract interface class EmergencyNumberResolver {
  /// Resolves.
  Future<EmergencyDialTarget> resolve({
    double? latitude,
    double? longitude,
    String? fallbackCountryCode,
  });
}

/// Represents emergency dial target.
class EmergencyDialTarget {
  /// Creates emergency dial target.
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

  /// Returns description.
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

/// Represents emergency country numbers.
class EmergencyCountryNumbers {
  /// Creates emergency country numbers.
  const EmergencyCountryNumbers({
    required this.countryName,
    required this.ambulance,
  });

  final String countryName;
  final String ambulance;
}

typedef EmergencyCountryLookup =
    Future<EmergencyCountryNumbers?> Function(String countryCode);

/// Represents emergency number service.
class EmergencyNumberService implements EmergencyNumberResolver {
  /// Creates emergency number service.
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

  /// Resolves.
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

  /// Computes country at.
  Future<_CountryMatch?> _countryAt(double latitude, double longitude) async {
    final client = _client ?? http.Client();
    final ownsClient = _client == null;
    try {
      final lookups = <Future<_CountryMatch?>>[
        if (_client == null || _googleGeocodingApiKey.trim().isNotEmpty)
          _countryFromGoogle(client, latitude, longitude),
        if (_client == null || _geoapifyApiKey.trim().isNotEmpty)
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

  /// Computes country from google.
  Future<_CountryMatch?> _countryFromGoogle(
    http.Client client,
    double latitude,
    double longitude,
  ) async {
    final key = _googleGeocodingApiKey.trim();
    if (_client != null && key.isEmpty) return null;
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '$latitude,$longitude',
        'result_type': 'country',
        'key': key,
      });
      final response =
          await (_client == null
                  ? PrivateProviderClient.request('googleGeocode', {
                      'latitude': latitude,
                      'longitude': longitude,
                      'countryOnly': true,
                    })
                  : client.get(
                      uri,
                      headers: GoogleApiConfig.androidBetaHeaders,
                    ))
              .timeout(_requestTimeout);
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

  /// Computes country from geoapify.
  Future<_CountryMatch?> _countryFromGeoapify(
    http.Client client,
    double latitude,
    double longitude,
  ) async {
    final key = _geoapifyApiKey.trim();
    if (_client != null && key.isEmpty) return null;
    try {
      final uri = Uri.https('api.geoapify.com', '/v1/geocode/reverse', {
        'lat': '$latitude',
        'lon': '$longitude',
        'type': 'country',
        'format': 'json',
        'apiKey': key,
      });
      final response =
          await (_client == null
                  ? PrivateProviderClient.request('geoReverse', {
                      'latitude': latitude,
                      'longitude': longitude,
                      'countryOnly': true,
                    })
                  : client.get(uri))
              .timeout(_requestTimeout);
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

  /// Computes country from address components.
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

  /// Computes lookup bundled country.
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

  /// Checks whether coordinate valid.
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

  /// Normalizes country code.
  static String? _normalizeCountryCode(String? value) {
    final code = value?.trim().toUpperCase();
    if (code == null || !RegExp(r'^[A-Z]{2}$').hasMatch(code)) return null;
    return code;
  }

  /// Computes dialable number.
  static String? _dialableNumber(String? value) {
    final number = value?.replaceAll(RegExp(r'[^0-9+]'), '');
    if (number == null || number.length < 2) return null;
    return number;
  }

  /// Computes non empty.
  static String? _nonEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

/// Represents country match.
class _CountryMatch {
  /// Creates country match.
  const _CountryMatch({
    required this.code,
    required this.name,
    this.fromCoordinate = false,
  });

  final String code;
  final String? name;
  final bool fromCoordinate;
}
