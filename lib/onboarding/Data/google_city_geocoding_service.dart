// GoogleCityGeocodingService resolves residential city selections through the backend geocoding service.
import '../../core/services/private_provider_client.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/google_api_config.dart';

/// Represents city geocoding exception.
class CityGeocodingException implements Exception {
  /// Creates city geocoding exception.
  const CityGeocodingException(this.message);

  final String message;

  /// Converts to string.
  @override
  String toString() => message;
}

/// Represents residential city selection.
class ResidentialCitySelection {
  /// Creates residential city selection.
  const ResidentialCitySelection({
    required this.city,
    required this.state,
    required this.country,
    required this.latitude,
    required this.longitude,
  });

  final String city;
  final String state;
  final String country;
  final double latitude;
  final double longitude;

  /// Returns label.
  String get label => [
    city,
    state,
    country,
  ].where((part) => part.trim().isNotEmpty).toSet().join(', ');
}

/// Represents google city geocoding service.
class GoogleCityGeocodingService {
  /// Creates google city geocoding service.
  GoogleCityGeocodingService({http.Client? client, String? apiKey})
    : _client = client,
      _apiKey = apiKey ?? GoogleApiConfig.geocodingApiKey;

  final http.Client? _client;
  final String _apiKey;

  /// Resolves city.
  Future<ResidentialCitySelection> resolveCity({
    required double latitude,
    required double longitude,
  }) async {
    if (_client != null && _apiKey.trim().isEmpty) {
      throw const CityGeocodingException(
        'Google Geocoding API key is not configured.',
      );
    }

    final client = _client ?? http.Client();
    try {
      final response = _client == null
          ? await PrivateProviderClient.request('googleGeocode', {
              'latitude': latitude,
              'longitude': longitude,
            })
          : await client.get(
              Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
                'latlng': '$latitude,$longitude',
                'key': _apiKey,
                'language': 'en',
              }),
              headers: GoogleApiConfig.androidBetaHeaders,
            );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CityGeocodingException(
          'Google Geocoding ${response.statusCode}: unable to resolve this city.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const CityGeocodingException(
          'Google Geocoding returned an unexpected response.',
        );
      }
      final status = decoded['status'];
      if (status != 'OK') {
        final message = decoded['error_message'];
        throw CityGeocodingException(
          message is String && message.trim().isNotEmpty
              ? message
              : 'No city was found at this map location.',
        );
      }

      final results = decoded['results'];
      if (results is! Iterable) {
        throw const CityGeocodingException(
          'No city was found at this map location.',
        );
      }

      var city = '';
      var state = '';
      var country = '';
      for (final result in results) {
        if (result is! Map) {
          continue;
        }
        final components = result['address_components'];
        if (components is! Iterable) {
          continue;
        }
        for (final component in components) {
          if (component is! Map) {
            continue;
          }
          final name = component['long_name'];
          final types = component['types'];
          if (name is! String || types is! Iterable) {
            continue;
          }
          if (city.isEmpty &&
              (types.contains('locality') ||
                  types.contains('postal_town') ||
                  types.contains('administrative_area_level_2'))) {
            city = name;
          }
          if (state.isEmpty && types.contains('administrative_area_level_1')) {
            state = name;
          }
          if (country.isEmpty && types.contains('country')) {
            country = name;
          }
        }
        if (city.isNotEmpty && country.isNotEmpty) {
          break;
        }
      }

      if (city.isEmpty) {
        throw const CityGeocodingException(
          'Choose a location within a recognised city or town.',
        );
      }
      return ResidentialCitySelection(
        city: city,
        state: state,
        country: country,
        latitude: latitude,
        longitude: longitude,
      );
    } on CityGeocodingException {
      rethrow;
    } on FormatException {
      throw const CityGeocodingException(
        'Google Geocoding returned invalid location data.',
      );
    } catch (_) {
      throw const CityGeocodingException(
        'Unable to resolve this city. Check your connection and try again.',
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }
}
