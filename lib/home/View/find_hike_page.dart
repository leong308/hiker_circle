import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../sos/Data/location_snapshot_service.dart';
import '../Model/hike_session_models.dart';

Future<void> showUpcomingHikePopup(
  BuildContext context, {
  required UpcomingHike hike,
  required AppSession session,
  required HikerCircleFirebaseRepository repository,
  double? userLat,
  double? userLng,
  VoidCallback? onJoin,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
        child: UpcomingHikeCard(
          hike: hike,
          userLat: userLat,
          userLng: userLng,
          phoneNumber: session.phoneNumber,
          userName: session.username,
          repository: repository,
          onJoin: onJoin ?? () {},
        ),
      ),
    ),
  );
}

class FindHikePage extends StatefulWidget {
  const FindHikePage({
    super.key,
    required this.session,
    required this.repository,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository repository;

  @override
  State<FindHikePage> createState() => _FindHikePageState();
}

class _FindHikePageState extends State<FindHikePage> {
  List<UpcomingHike> _hikes = const [];
  bool _isLoading = true;
  double? _userLat;
  double? _userLng;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final location = await LocationSnapshotService.instance.refresh();
      final hikes = await widget.repository.loadUpcomingHikes();
      if (!mounted) return;
      final userLat = location?.latitude;
      final userLng = location?.longitude;

      final now = DateTime.now();
      final active = hikes
          .where(
            (h) => !now.isAfter(h.departureTime.add(const Duration(hours: 1))),
          )
          .toList();

      List<UpcomingHike> sorted;
      if (userLat != null && userLng != null) {
        sorted = List.of(active)
          ..sort(
            (a, b) => a
                .distanceFrom(userLat, userLng)
                .compareTo(b.distanceFrom(userLat, userLng)),
          );
      } else {
        sorted = active;
      }
      setState(() {
        _hikes = sorted;
        _userLat = userLat;
        _userLng = userLng;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load upcoming hikes.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(
                    title: 'Find a Hike',
                    subtitle: _isLoading
                        ? 'Loading...'
                        : _error != null
                        ? 'Something went wrong'
                        : '${_hikes.length} hike${_hikes.length == 1 ? '' : 's'} near you',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _buildBody(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _InsetGroup(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                'Loading upcoming hikes...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _AppColors.secondaryText,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return _InsetGroup(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _AppColors.secondaryText,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => unawaited(_load()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_hikes.isEmpty) {
      return _EmptyState(
        message: 'No upcoming hikes near you yet.\nBe the first to start one!',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: _hikes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => UpcomingHikeCard(
          hike: _hikes[index],
          userLat: _userLat,
          userLng: _userLng,
          phoneNumber: widget.session.phoneNumber,
          userName: widget.session.username,
          repository: widget.repository,
          onJoin: () => unawaited(_load()),
        ),
      ),
    );
  }
}

class UpcomingHikeCard extends StatefulWidget {
  const UpcomingHikeCard({
    super.key,
    required this.hike,
    this.userLat,
    this.userLng,
    required this.phoneNumber,
    this.userName = '',
    required this.repository,
    required this.onJoin,
  });

  final UpcomingHike hike;
  final double? userLat;
  final double? userLng;
  final String phoneNumber;
  final String userName;
  final HikerCircleFirebaseRepository repository;
  final VoidCallback onJoin;

  @override
  State<UpcomingHikeCard> createState() => _UpcomingHikeCardState();
}

class _UpcomingHikeCardState extends State<UpcomingHikeCard> {
  bool _joining = false;
  bool _joinedLocally = false;

  bool get _isParticipating {
    final phone = widget.phoneNumber;
    return _joinedLocally ||
        phone == widget.hike.creatorPhone ||
        widget.hike.participantPhones.contains(phone);
  }

  Future<void> _openDirections() async {
    final lat = widget.hike.latitude;
    final lng = widget.hike.longitude;
    final googleUrl =
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    final wazeUrl = 'https://waze.com/ul?ll=$lat,$lng&navigate=yes';
    final uri = Uri.parse(googleUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(Uri.parse(wazeUrl), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _join() async {
    if (_joining) return;
    setState(() => _joining = true);
    final ok = await widget.repository.joinUpcomingHike(
      hikeId: widget.hike.id,
      sessionId: widget.hike.sessionId,
      trailName: widget.hike.trailName,
      creatorPhone: widget.hike.creatorPhone,
      phoneNumber: widget.phoneNumber,
      userName: widget.userName,
    );
    if (!mounted) return;
    setState(() => _joining = false);
    if (ok) {
      setState(() => _joinedLocally = true);
      widget.onJoin();
    }
  }

  @override
  Widget build(BuildContext context) {
    final distKm = widget.userLat != null && widget.userLng != null
        ? widget.hike.distanceFrom(widget.userLat!, widget.userLng!)
        : widget.hike.distanceKm;
    final distText = distKm < 1
        ? '${(distKm * 1000).toStringAsFixed(0)} m'
        : '${distKm.toStringAsFixed(1)} km';

    final departureTime = widget.hike.departureTime.toLocal();
    final dateText =
        '${departureTime.day}/${departureTime.month}/${departureTime.year}';
    final timeText =
        '${departureTime.hour.toString().padLeft(2, '0')}:${departureTime.minute.toString().padLeft(2, '0')}';

    final participating = _isParticipating;
    final isCreator = widget.phoneNumber == widget.hike.creatorPhone;

    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Glyph(icon: Icons.hiking_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.hike.trailName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _AppColors.text,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${widget.hike.area}, ${widget.hike.state}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _AppColors.secondaryText,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusPill(
                  label: widget.hike.hikeType == 'team' ? 'Team' : 'Solo',
                  color: widget.hike.hikeType == 'team'
                      ? _AppColors.green
                      : _AppColors.secondaryText,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const _HorizontalSeparator(),
            const SizedBox(height: 10),
            _infoRow(
              context,
              Icons.directions_walk_rounded,
              'Start',
              widget.hike.startPointName,
            ),
            const SizedBox(height: 4),
            _infoRow(
              context,
              Icons.flag_rounded,
              'Destination',
              widget.hike.destinationName,
            ),
            const SizedBox(height: 4),
            _infoRow(
              context,
              Icons.person_rounded,
              'Host',
              widget.hike.creatorName.isNotEmpty
                  ? widget.hike.creatorName
                  : widget.hike.creatorPhone,
            ),
            const SizedBox(height: 4),
            _infoRow(
              context,
              Icons.phone_rounded,
              'Phone',
              widget.hike.creatorPhone,
            ),
            const SizedBox(height: 10),
            const _HorizontalSeparator(),
            const SizedBox(height: 10),
            Row(
              children: [
                _chip(context, Icons.schedule_rounded, '$dateText $timeText'),
                const SizedBox(width: 8),
                _chip(context, Icons.straighten_rounded, distText),
                const SizedBox(width: 8),
                _chip(
                  context,
                  Icons.people_rounded,
                  '${widget.hike.participantCount}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.timeline_rounded,
                  size: 13,
                  color: _AppColors.secondaryText,
                ),
                const SizedBox(width: 4),
                Text(
                  '${widget.hike.distanceKm.toStringAsFixed(1)} km \u00b7 ${widget.hike.durationMinutes} min \u00b7 ${widget.hike.difficulty}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _AppColors.secondaryText,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Material(
              color: _AppColors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _openDirections,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Get a route to this hike',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: _AppColors.green,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                        ),
                      ),
                      const Icon(
                        Icons.navigation_rounded,
                        size: 19,
                        color: _AppColors.green,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (participating) ...[
              const SizedBox(height: 10),
              const _HorizontalSeparator(),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    isCreator ? Icons.star_rounded : Icons.check_circle_rounded,
                    size: 16,
                    color: isCreator ? _AppColors.orange : _AppColors.green,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isCreator ? 'Created by you' : 'You joined this hike',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isCreator ? _AppColors.orange : _AppColors.green,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 12),
              const _HorizontalSeparator(),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _joining ? null : _join,
                  icon: _joining
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.person_add_rounded, size: 18),
                  label: Text(_joining ? 'Joining...' : 'Join Hike'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _AppColors.secondaryText),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _AppColors.secondaryText,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _AppColors.text,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _AppColors.chipBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _AppColors.secondaryText),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _AppColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: 'Back',
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(36),
            onPressed: onBack,
            child: const _CircleIcon(icon: CupertinoIcons.chevron_back),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _AppColors.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _AppColors.secondaryText,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _AppColors.surface,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: _AppColors.green, size: 19),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _AppColors.green,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

class _HorizontalSeparator extends StatelessWidget {
  const _HorizontalSeparator();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, thickness: 0.7, color: _AppColors.separator);
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _AppColors.secondaryText,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

abstract final class _AppColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color surface = Colors.white;
  static const Color green = Color(0xFF34A853);
  static const Color orange = Color(0xFFF59E0B);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color chipBackground = Color(0xFFF2F2F7);
}
