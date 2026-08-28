import 'package:flutter/material.dart';

import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../Model/hike_session_models.dart';

class UpcomingHikeJoinRequestDialog extends StatefulWidget {
  const UpcomingHikeJoinRequestDialog({
    super.key,
    required this.review,
    required this.onResolve,
  });

  final UpcomingHikeJoinRequestReview review;
  final Future<UpcomingHikeJoinRequestReview> Function(bool accept) onResolve;

  @override
  State<UpcomingHikeJoinRequestDialog> createState() =>
      _UpcomingHikeJoinRequestDialogState();
}

class _UpcomingHikeJoinRequestDialogState
    extends State<UpcomingHikeJoinRequestDialog> {
  static const _green = Color(0xFF34A853);
  static const _red = Color(0xFFE11D48);
  bool _isResolving = false;
  String? _error;

  Future<void> _resolve(bool accept) async {
    if (_isResolving) return;
    setState(() {
      _isResolving = true;
      _error = null;
    });
    try {
      final result = await widget.onResolve(accept);
      if (mounted) Navigator.of(context).pop(result);
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to respond right now. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }

  ({String title, String message, IconData icon, Color color})
  _terminalContent() {
    final review = widget.review;
    if (review.status == 'accepted') {
      return (
        title: 'Request already accepted',
        message: '${review.requesterName} is already part of this hike.',
        icon: Icons.check_circle_rounded,
        color: _green,
      );
    }
    if (review.status == 'rejected') {
      return (
        title: 'Request already declined',
        message: 'This request was declined and the link has expired.',
        icon: Icons.block_rounded,
        color: _red,
      );
    }
    return switch (review.reason) {
      'hike_removed' => (
        title: 'Hike no longer available',
        message: 'The upcoming hike was removed, so this request has expired.',
        icon: Icons.delete_outline_rounded,
        color: _red,
      ),
      'hike_started' => (
        title: 'Hike already started',
        message: 'The participant list is closed and this request has expired.',
        icon: Icons.directions_walk_rounded,
        color: _red,
      ),
      'hike_ended' => (
        title: 'Hike already ended',
        message: 'This request can no longer be accepted.',
        icon: Icons.event_busy_rounded,
        color: _red,
      ),
      _ => (
        title: 'Request link expired',
        message: 'This join request is no longer available.',
        icon: Icons.link_off_rounded,
        color: _red,
      ),
    };
  }

  String _departureLabel() {
    final departure = widget.review.departureTime?.toLocal();
    if (departure == null) return 'Scheduled upcoming hike';
    final minute = departure.minute.toString().padLeft(2, '0');
    return '${departure.day}/${departure.month}/${departure.year} · '
        '${departure.hour}:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF141C17) : Colors.white;
    final text = isDark ? const Color(0xFFEAF4EE) : const Color(0xFF111111);
    final secondary = isDark
        ? const Color(0xFFA8B8AE)
        : const Color(0xFF6E6E73);
    final pending = widget.review.canResolve;
    final terminal = pending ? null : _terminalContent();
    final accent = terminal?.color ?? _green;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(
                      terminal?.icon ?? Icons.person_add_alt_1_rounded,
                      color: accent,
                      size: 29,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          terminal?.title ?? 'New hike join request',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: text,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          terminal?.message ??
                              '${widget.review.requesterName} would like to join your solo hike.',
                          style: TextStyle(color: secondary, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (pending) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF101813)
                        : const Color(0xFFF5F7F5),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.terrain_rounded, color: _green),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.review.trailName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: text,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            color: secondary,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _departureLabel(),
                            style: TextStyle(color: secondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (pending)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('decline-upcoming-hike-join-request'),
                        onPressed: _isResolving ? null : () => _resolve(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _red,
                          side: const BorderSide(color: _red),
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        key: const Key('accept-upcoming-hike-join-request'),
                        onPressed: _isResolving ? null : () => _resolve(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isResolving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Accept'),
                      ),
                    ),
                  ],
                )
              else
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(widget.review),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              if (pending)
                TextButton(
                  onPressed: _isResolving
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: Text(
                    'Review later',
                    style: TextStyle(color: secondary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
