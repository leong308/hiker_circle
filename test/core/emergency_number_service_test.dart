import 'dart:convert';

import 'package:emergency_helpline/emergency_helpline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/emergency_number_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads emergency numbers from the bundled country catalogue', () async {
    final bundled = await EmergencyHelpline.instance.getCountry('MY');
    expect(bundled?.ambulance, '999');
    final service = EmergencyNumberService(
      googleGeocodingApiKey: '',
      geoapifyApiKey: '',
    );

    final target = await service.resolve(fallbackCountryCode: 'MY');

    expect(target.number, '999');
    expect(target.countryName, 'Malaysia');
    expect(target.isFallback, isFalse);
  });

  test(
    'uses the SOS coordinate country instead of the device locale',
    () async {
      final requestedCodes = <String>[];
      final service = EmergencyNumberService(
        client: MockClient((request) async {
          expect(request.url.host, 'maps.googleapis.com');
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'address_components': [
                    {
                      'long_name': 'Malaysia',
                      'short_name': 'MY',
                      'types': ['country'],
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }),
        googleGeocodingApiKey: 'test-key',
        geoapifyApiKey: '',
        countryLookup: (code) async {
          requestedCodes.add(code);
          return const EmergencyCountryNumbers(
            countryName: 'Malaysia',
            ambulance: '999',
          );
        },
      );

      final target = await service.resolve(
        latitude: 5.4141,
        longitude: 100.3288,
        fallbackCountryCode: 'US',
      );

      expect(requestedCodes, ['MY']);
      expect(target.number, '999');
      expect(target.countryCode, 'MY');
      expect(target.countryName, 'Malaysia');
      expect(target.isLocationBased, isTrue);
      expect(target.isFallback, isFalse);
    },
  );

  test('uses Geoapify when Google cannot resolve the country', () async {
    final service = EmergencyNumberService(
      client: MockClient((request) async {
        if (request.url.host == 'maps.googleapis.com') {
          return http.Response('{}', 500);
        }
        expect(request.url.host, 'api.geoapify.com');
        return http.Response(
          jsonEncode({
            'results': [
              {'country_code': 'sg', 'country': 'Singapore'},
            ],
          }),
          200,
        );
      }),
      googleGeocodingApiKey: 'google-key',
      geoapifyApiKey: 'geoapify-key',
      countryLookup: (code) async {
        expect(code, 'SG');
        return const EmergencyCountryNumbers(
          countryName: 'Singapore',
          ambulance: '995',
        );
      },
    );

    final target = await service.resolve(latitude: 1.3521, longitude: 103.8198);

    expect(target.number, '995');
    expect(target.countryCode, 'SG');
    expect(target.isLocationBased, isTrue);
  });

  test('uses the device country when no coordinate is available', () async {
    final service = EmergencyNumberService(
      googleGeocodingApiKey: '',
      geoapifyApiKey: '',
      countryLookup: (code) async {
        expect(code, 'US');
        return const EmergencyCountryNumbers(
          countryName: 'United States',
          ambulance: '911',
        );
      },
    );

    final target = await service.resolve(fallbackCountryCode: 'us');

    expect(target.number, '911');
    expect(target.countryName, 'United States');
    expect(target.isLocationBased, isFalse);
    expect(target.isFallback, isFalse);
  });

  test('keeps a dialable fallback when the country is unavailable', () async {
    final service = EmergencyNumberService(
      googleGeocodingApiKey: '',
      geoapifyApiKey: '',
      countryLookup: (_) async => null,
    );

    final target = await service.resolve(fallbackCountryCode: 'ZZ');

    expect(target.number, '112');
    expect(target.isFallback, isTrue);
  });
}
