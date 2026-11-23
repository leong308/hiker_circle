import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../core/widgets/app_toast.dart';

/// Reveals the hike removal action on hover, keyboard focus or long press.
class UpcomingHikeDeleteCard extends StatefulWidget {
  const UpcomingHikeDeleteCard({
    super.key,
    required this.trailName,
    required this.isHost,
    required this.onDelete,
    required this.builder,
  });

  final String trailName;
  final bool isHost;
  final Future<void> Function() onDelete;
  final Widget Function(Widget? deleteButton) builder;

  @override
  State<UpcomingHikeDeleteCard> createState() => _UpcomingHikeDeleteCardState();
}

class _UpcomingHikeDeleteCardState extends State<UpcomingHikeDeleteCard>
    with SingleTickerProviderStateMixin {
  late final _wiggle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _hovered = false, _focused = false, _pinned = false, _busy = false;
  bool get _visible => _hovered || _focused || _pinned;

  void _syncMotion() {
    if (_visible &&
        !_busy &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context)) {
      if (!_wiggle.isAnimating) _wiggle.repeat();
    } else {
      _wiggle.reset();
    }
  }

  void _change(VoidCallback change) {
    setState(change);
    _syncMotion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  Future<void> _delete() async {
    if (_busy) return;
    final trailName = widget.trailName;
    final host = widget.isHost;
    _change(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(host ? 'Delete upcoming hike?' : 'Leave upcoming hike?'),
          content: Text(
            host
                ? 'This cancels the scheduled hike at $trailName for everyone.'
                : 'You will leave $trailName. The other hikers will keep their plan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep hike'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(host ? 'Delete hike' : 'Leave hike'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted && host == widget.isHost) {
        await widget.onDelete();
      }
    } catch (error) {
      if (mounted) {
        HikerCircleToast.show(
          context,
          error is HikerCircleFirebaseRepositoryException
              ? error.message
              : 'Could not remove this hike. Try again.',
          tone: HikerCircleToastTone.error,
        );
      }
    } finally {
      if (mounted) {
        _change(() {
          _busy = false;
          _pinned = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      tooltip: widget.isHost ? 'Delete upcoming hike' : 'Leave upcoming hike',
      onPressed: _busy ? null : _delete,
      icon: Icon(
        widget.isHost ? Icons.delete_outline : Icons.logout_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
    );
    return TapRegion(
      onTapOutside: _pinned ? (_) => _change(() => _pinned = false) : null,
      child: MouseRegion(
        onEnter: (_) => _change(() => _hovered = true),
        onExit: (_) => _change(() => _hovered = false),
        child: FocusableActionDetector(
          onShowFocusHighlight: (v) => _change(() => _focused = v),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPress: () => _change(() => _pinned = !_pinned),
            child: AnimatedBuilder(
              animation: _wiggle,
              child: widget.builder(_visible ? button : null),
              builder: (context, child) => Transform.rotate(
                angle: math.sin(_wiggle.value * 2 * math.pi) * .006,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _wiggle.dispose();
    super.dispose();
  }
}
