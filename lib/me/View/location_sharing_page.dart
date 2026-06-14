import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../Data/live_location_sharing_service.dart';
import '../../sos/Data/location_snapshot_service.dart';
import '../../sos/Model/sos_models.dart';

class LocationSharingPage extends StatefulWidget {
  const LocationSharingPage({
    super.key,
    required this.phoneNumber,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final String phoneNumber;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  @override
  State<LocationSharingPage> createState() => _LocationSharingPageState();
}

class _LocationSharingPageState extends State<LocationSharingPage> {
  final LocationSnapshotService _locationService =
      LocationSnapshotService.instance;
  final LiveLocationSharingService _liveLocationSharingService =
      LiveLocationSharingService.instance;
  Timer? _refreshTimer;
  SosTriggerLocation? _location;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _liveLocationSharingService.addListener(_refresh);
    _location = _locationService.latestLocation;
    _isLoading = _location == null;
    unawaited(
      _liveLocationSharingService.loadExisting(
        phoneNumber: widget.phoneNumber,
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      ),
    );
    unawaited(_refreshLocation());
    _refreshTimer = Timer.periodic(LocationSnapshotService.snapshotInterval, (
      _,
    ) {
      unawaited(_refreshLocation());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _liveLocationSharingService.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<SosTriggerLocation?> _refreshLocation() async {
    if (_isLoading && _location != null) {
      return _location;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final location = await _locationService.refresh();
      if (!mounted) {
        return _location;
      }

      setState(() {
        _location = location;
        _isLoading = false;
        _errorMessage = location == null
            ? 'Location unavailable. Check GPS and location permission.'
            : null;
      });
      if (location != null && _liveLocationSharingService.isActive) {
        unawaited(_liveLocationSharingService.publishLatest());
      }
      return location;
    } catch (_) {
      if (!mounted) {
        return _location;
      }

      setState(() {
        _isLoading = false;
        _errorMessage =
            'Unable to refresh your live location. Try again in a moment.';
      });
      return _location;
    }
  }

  Future<void> _toggleLiveLocation() async {
    if (_liveLocationSharingService.isActive) {
      await _liveLocationSharingService.deactivate();
    } else {
      await _liveLocationSharingService.activate(
        phoneNumber: widget.phoneNumber,
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      );
    }

    _showLiveLocationMessage();
  }

  Future<void> _shareLiveLocation() async {
    await _liveLocationSharingService.shareLiveLocation(
      phoneNumber: widget.phoneNumber,
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    _showLiveLocationMessage(fallbackMessage: 'Live location link ready.');
  }

  void _showLiveLocationMessage({String? fallbackMessage}) {
    if (!mounted) {
      return;
    }

    final errorMessage = _liveLocationSharingService.errorMessage;
    final message =
        errorMessage ??
        fallbackMessage ??
        (_liveLocationSharingService.isActive
            ? 'Live location active.'
            : 'Live location stopped.');

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: errorMessage == null
              ? _LocationColors.green
              : _LocationColors.destructive,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _LocationColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(onBack: () => Navigator.of(context).pop()),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 250,
                    child: _MapPanel(
                      location: _location,
                      isLoading: _isLoading,
                      errorMessage: _errorMessage,
                      onRefresh: () => unawaited(_refreshLocation()),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _LocationDetails(location: _location, isLoading: _isLoading),
                  const SizedBox(height: 14),
                  _LiveLocationControls(
                    isActive: _liveLocationSharingService.isActive,
                    isBusy: _liveLocationSharingService.isBusy,
                    isSharing: _liveLocationSharingService.isSharing,
                    shareUrl: _liveLocationSharingService.share?.shareUrl,
                    onToggle: () => unawaited(_toggleLiveLocation()),
                    onShare: () => unawaited(_shareLiveLocation()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        children: [
          Tooltip(
            message: 'Back',
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size.square(36),
              onPressed: onBack,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _LocationColors.surfaceFor(context),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.chevron_back,
                  color: _LocationColors.green,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Location Sharing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: _LocationColors.textFor(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Live GPS position with map pin',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _LocationColors.secondaryTextFor(context),
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPanel extends StatelessWidget {
  const _MapPanel({
    required this.location,
    required this.isLoading,
    required this.errorMessage,
    required this.onRefresh,
  });

  final SosTriggerLocation? location;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(color: _LocationColors.surfaceFor(context)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (location case final location?)
              _OpenStreetMap(location: location)
            else
              ColoredBox(color: _LocationColors.mapFallbackFor(context)),
            const Center(child: _MapPin()),
            if (isLoading)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: const LinearProgressIndicator(minHeight: 2),
              ),
            if (errorMessage case final errorMessage?)
              Align(
                alignment: Alignment.bottomCenter,
                child: _MapMessage(message: errorMessage),
              ),
            Positioned(
              right: 12,
              top: 12,
              child: Tooltip(
                message: 'Refresh location',
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size.square(38),
                  onPressed: isLoading ? null : onRefresh,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _LocationColors.surfaceFor(
                        context,
                      ).withValues(alpha: 0.94),
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1F000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const SizedBox.square(
                      dimension: 38,
                      child: Icon(
                        Icons.my_location_rounded,
                        color: _LocationColors.green,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenStreetMap extends StatelessWidget {
  const _OpenStreetMap({required this.location});

  static const int _zoom = 16;
  static const double _tileSize = 256;

  final SosTriggerLocation location;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final centerTile = _tileCoordinate(
          latitude: location.latitude,
          longitude: location.longitude,
          zoom: _zoom,
        );
        final baseTileX = centerTile.x.floor();
        final baseTileY = centerTile.y.floor();
        final centerOffsetX = (centerTile.x - baseTileX) * _tileSize;
        final centerOffsetY = (centerTile.y - baseTileY) * _tileSize;
        final gridRadius =
            (math.max(constraints.maxWidth, constraints.maxHeight) /
                    _tileSize /
                    2)
                .ceil() +
            1;
        final left =
            constraints.maxWidth / 2 - centerOffsetX - gridRadius * _tileSize;
        final top =
            constraints.maxHeight / 2 - centerOffsetY - gridRadius * _tileSize;

        return ClipRect(
          child: Stack(
            children: [
              for (var yOffset = -gridRadius; yOffset <= gridRadius; yOffset++)
                for (
                  var xOffset = -gridRadius;
                  xOffset <= gridRadius;
                  xOffset++
                )
                  Positioned(
                    left: left + (xOffset + gridRadius) * _tileSize,
                    top: top + (yOffset + gridRadius) * _tileSize,
                    width: _tileSize,
                    height: _tileSize,
                    child: Image.network(
                      _tileUrl(
                        zoom: _zoom,
                        x: baseTileX + xOffset,
                        y: baseTileY + yOffset,
                      ),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return ColoredBox(
                          color: _LocationColors.mapFallbackFor(context),
                        );
                      },
                    ),
                  ),
              Positioned(
                left: 10,
                bottom: 8,
                child: Text(
                  'OpenStreetMap contributors',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _LocationColors.secondaryTextFor(context),
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static _TileCoordinate _tileCoordinate({
    required double latitude,
    required double longitude,
    required int zoom,
  }) {
    final scale = math.pow(2, zoom).toDouble();
    final latitudeRadians = latitude * math.pi / 180;
    final x = (longitude + 180) / 360 * scale;
    final y =
        (1 -
            math.log(
                  math.tan(latitudeRadians) + 1 / math.cos(latitudeRadians),
                ) /
                math.pi) /
        2 *
        scale;

    return _TileCoordinate(x: x, y: y);
  }

  static String _tileUrl({required int zoom, required int x, required int y}) {
    final tileCount = math.pow(2, zoom).toInt();
    final wrappedX = x % tileCount;
    final normalizedX = wrappedX < 0 ? wrappedX + tileCount : wrappedX;
    return 'https://tile.openstreetmap.org/$zoom/$normalizedX/$y.png';
  }
}

class _TileCoordinate {
  const _TileCoordinate({required this.x, required this.y});

  final double x;
  final double y;
}

class _MapPin extends StatelessWidget {
  const _MapPin();

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -18),
      child: const Icon(
        Icons.location_pin,
        color: _LocationColors.pin,
        size: 48,
        shadows: [
          Shadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
    );
  }
}

class _MapMessage extends StatelessWidget {
  const _MapMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _LocationColors.surfaceFor(context).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _LocationColors.textFor(context),
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationDetails extends StatelessWidget {
  const _LocationDetails({required this.location, required this.isLoading});

  final SosTriggerLocation? location;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final capturedAt = location?.capturedAt?.toLocal();
    final timestamp = capturedAt == null
        ? 'Waiting for GPS'
        : '${_twoDigits(capturedAt.hour)}:${_twoDigits(capturedAt.minute)}:${_twoDigits(capturedAt.second)}';
    final accuracy = location?.accuracyMeters == null
        ? 'Accuracy unknown'
        : 'Accuracy +/- ${location!.accuracyMeters!.toStringAsFixed(0)} m';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(color: _LocationColors.surfaceFor(context)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _LocationColors.green,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  isLoading
                      ? Icons.satellite_alt_rounded
                      : Icons.my_location_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location == null
                          ? 'Live location'
                          : '${location!.latitude.toStringAsFixed(6)}, ${location!.longitude.toStringAsFixed(6)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _LocationColors.textFor(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$accuracy - Updated $timestamp',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _LocationColors.secondaryTextFor(context),
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

class _LiveLocationControls extends StatelessWidget {
  const _LiveLocationControls({
    required this.isActive,
    required this.isBusy,
    required this.isSharing,
    required this.shareUrl,
    required this.onToggle,
    required this.onShare,
  });

  final bool isActive;
  final bool isBusy;
  final bool isSharing;
  final String? shareUrl;
  final VoidCallback onToggle;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final statusText = isActive ? 'Live location active' : 'Live location off';
    final linkText = shareUrl ?? 'Firebase live link not created yet';
    final isDisabled = isBusy || isSharing;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(color: _LocationColors.surfaceFor(context)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isActive
                          ? _LocationColors.green
                          : _LocationColors.secondaryTextFor(context),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      isActive
                          ? Icons.location_searching_rounded
                          : Icons.location_disabled_rounded,
                      color: Colors.white,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: _LocationColors.textFor(context),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          linkText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _LocationColors.secondaryTextFor(
                                  context,
                                ),
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isDisabled ? null : onToggle,
                      icon: Icon(
                        isActive
                            ? Icons.stop_circle_rounded
                            : Icons.power_settings_new_rounded,
                        size: 18,
                      ),
                      label: Text(isActive ? 'Stop Live' : 'Activate Live'),
                      style: FilledButton.styleFrom(
                        backgroundColor: isActive
                            ? _LocationColors.destructive
                            : _LocationColors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isDisabled ? null : onShare,
                      icon: Icon(
                        isSharing
                            ? Icons.hourglass_top_rounded
                            : Icons.ios_share_rounded,
                        size: 18,
                      ),
                      label: const Text('Share Live'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _LocationColors.green,
                        minimumSize: const Size(0, 44),
                        side: const BorderSide(color: _LocationColors.green),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

abstract final class _LocationColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color mapFallback = Color(0xFFEAF7EE);
  static const Color pin = Color(0xFFFF3B30);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color destructive = Color(0xFFFF3B30);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color mapFallbackFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF102217) : mapFallback;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;
}
