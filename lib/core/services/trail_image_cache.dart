// TrailImageCache shares the bounded disk-cache policy used by downloaded trail images.
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Represents trail image cache.
class TrailImageCache {
  /// Creates trail image cache using .
  TrailImageCache._();

  static final CacheManager instance = CacheManager(
    Config(
      'hikerCircleTrailCoversV1',
      stalePeriod: const Duration(days: 365),
      maxNrOfCacheObjects: 1000,
    ),
  );
}
