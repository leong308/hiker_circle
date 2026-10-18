// TrailImageCache shares the bounded disk-cache policy used by downloaded trail images.
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class TrailImageCache {
  TrailImageCache._();

  static final CacheManager instance = CacheManager(
    Config(
      'hikerCircleTrailCoversV1',
      stalePeriod: const Duration(days: 365),
      maxNrOfCacheObjects: 1000,
    ),
  );
}
