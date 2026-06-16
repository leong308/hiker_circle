import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/onboarding/Data/google_city_geocoding_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('resolves locality, state, and country from Google response', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['latlng'], '1.3521,103.8198');
      return http.Response('''
        {
          "status": "OK",
          "results": [
            {
              "address_components": [
                {"long_name": "Singapore", "types": ["locality", "political"]},
                {"long_name": "Singapore", "types": ["administrative_area_level_1", "political"]},
                {"long_name": "Singapore", "types": ["country", "political"]}
              ]
            }
          ]
        }
      ''', 200);
    });
    final service = GoogleCityGeocodingService(
      client: client,
      apiKey: 'test-key',
    );

    final city = await service.resolveCity(
      latitude: 1.3521,
      longitude: 103.8198,
    );

    expect(city.city, 'Singapore');
    expect(city.state, 'Singapore');
    expect(city.country, 'Singapore');
    expect(city.label, 'Singapore');
  });

  test('rejects coordinates without a recognised city', () async {
    final service = GoogleCityGeocodingService(
      client: MockClient(
        (_) async =>
            http.Response('{"status":"ZERO_RESULTS","results":[]}', 200),
      ),
      apiKey: 'test-key',
    );

    expect(
      () => service.resolveCity(latitude: 0, longitude: 0),
      throwsA(isA<CityGeocodingException>()),
    );
  });
}
