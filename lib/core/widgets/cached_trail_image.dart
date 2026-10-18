// CachedTrailImage displays a cached trail photo with consistent loading, fallback and image-fit
// behavior.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/trail_image_cache.dart';

class CachedTrailImage extends StatelessWidget {
  const CachedTrailImage({
    super.key,
    required this.imageUrl,
    required this.fallbackBuilder,
    this.loadingBuilder,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.semanticLabel,
  });

  final String imageUrl;
  final WidgetBuilder fallbackBuilder;
  final WidgetBuilder? loadingBuilder;
  final BoxFit fit;
  final double? width;
  final double? height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = imageUrl.trim();
    if (normalizedUrl.isEmpty) {
      return fallbackBuilder(context);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        final logicalWidth =
            width ??
            (constraints.maxWidth.isFinite ? constraints.maxWidth : null);
        final logicalHeight =
            height ??
            (constraints.maxHeight.isFinite ? constraints.maxHeight : null);

        return CachedNetworkImage(
          cacheManager: TrailImageCache.instance,
          imageUrl: normalizedUrl,
          width: width,
          height: height,
          fit: fit,
          memCacheWidth: _decodeDimension(logicalWidth, pixelRatio),
          memCacheHeight: _decodeDimension(logicalHeight, pixelRatio),
          fadeInDuration: const Duration(milliseconds: 180),
          fadeOutDuration: const Duration(milliseconds: 80),
          useOldImageOnUrlChange: true,
          placeholder: (context, _) =>
              (loadingBuilder ?? fallbackBuilder)(context),
          errorWidget: (context, _, _) => fallbackBuilder(context),
          imageBuilder: semanticLabel == null
              ? null
              : (context, provider) => Semantics(
                  image: true,
                  label: semanticLabel,
                  child: Image(
                    image: provider,
                    width: width,
                    height: height,
                    fit: fit,
                    excludeFromSemantics: true,
                  ),
                ),
        );
      },
    );
  }

  int? _decodeDimension(double? logicalSize, double pixelRatio) {
    if (logicalSize == null ||
        !logicalSize.isFinite ||
        logicalSize <= 0 ||
        !pixelRatio.isFinite ||
        pixelRatio <= 0) {
      return null;
    }
    return (logicalSize * pixelRatio).ceil().clamp(1, 4096).toInt();
  }
}
