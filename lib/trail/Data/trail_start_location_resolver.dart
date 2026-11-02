import '../../core/services/geoapify_service.dart';
import '../../core/widgets/worldwide_region_picker.dart';
import '../../onboarding/Data/google_city_geocoding_service.dart';
import '../Model/trail_start_location.dart';

/// Resolves trail starting points using the same providers and region catalog.
class TrailStartLocationResolver {
  /// Allows isolated provider checks without changing the authenticated defaults.
  TrailStartLocationResolver({
    GoogleCityGeocodingService? google,
    GeoapifyService? geoapify,
  }) : _google = google ?? GoogleCityGeocodingService(),
       _geoapify = geoapify ?? GeoapifyService();

  final GoogleCityGeocodingService _google;
  final GeoapifyService _geoapify;

  /// Uses Google first, falling back when lookup or region validation fails.
  Future<TrailStartLocation> resolve({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final result = await _google.resolveCity(
        latitude: latitude,
        longitude: longitude,
      );
      return await _normalize(
        area: result.city,
        state: result.state,
        country: result.country,
      );
    } catch (_) {
      final result = await _geoapify.reverseGeocode(
        latitude: latitude,
        longitude: longitude,
      );
      return _normalize(
        area: result.area,
        state: result.state,
        country: result.country,
      );
    }
  }

  /// Requires a complete place while retaining the admin form's region aliases.
  Future<TrailStartLocation> _normalize({
    required String area,
    required String state,
    required String country,
  }) async {
    final region = await WorldwideRegionCatalog.normalize(
      country: country,
      state: state,
    );
    final result = TrailStartLocation(
      area: area,
      state: region?.state ?? state,
      country: region?.country ?? country,
    );
    if (result.area.trim().isEmpty ||
        result.state.trim().isEmpty ||
        result.country.trim().isEmpty) {
      throw StateError('The starting point location is incomplete.');
    }
    return result;
  }
}
