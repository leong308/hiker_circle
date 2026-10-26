part of '../upcoming_hike_join_request_dialog_feature.dart';

/// Displays the upcoming hike join request dialog.
class UpcomingHikeJoinRequestDialog extends StatefulWidget {
  /// Creates upcoming hike join request dialog.
  const UpcomingHikeJoinRequestDialog({
    super.key,
    required this.review,
    required this.onResolve,
  });

  final UpcomingHikeJoinRequestReview review;
  final Future<UpcomingHikeJoinRequestReview> Function(bool accept) onResolve;

  /// Creates the presentation state for this widget.
  @override
  State<UpcomingHikeJoinRequestDialog> createState() =>
      _UpcomingHikeJoinRequestDialogState();
}

/// Manages the upcoming hike join request dialog presentation and lifecycle.
class _UpcomingHikeJoinRequestDialogState
    extends State<UpcomingHikeJoinRequestDialog> {
  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _UpcomingHikeJoinRequestDialogStateViewModel(
      readReview: () => widget.review,
    )..addListener(_renderScreenModel);
  }

  late final _UpcomingHikeJoinRequestDialogStateViewModel _screenModel;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  static const _green = Color(0xFF34A853);
  static const _red = Color(0xFFE11D48);
  bool _isResolving = false;
  String? _error;

  /// Resolves.
  Future<void> _resolve(bool accept) async {
    if (_isResolving) return;
    setState(() {
      _isResolving = true;
      _error = null;
    });
    var loadingPopupOpen = true;
    unawaited(_presentResolveEffect1());
    // Give the modal route a frame to mount before the request can complete;
    // this keeps the cleanup below from touching the underlying review dialog.
    await Future<void>.delayed(Duration.zero);
    try {
      final result = await widget
          .onResolve(accept)
          .timeout(const Duration(seconds: 30));
      if (loadingPopupOpen && mounted) {
        loadingPopupOpen = false;
        _presentResolveEffect2();
      }
      if (mounted) _presentResolveEffect3(result);
    } on TimeoutException {
      if (mounted) {
        setState(() => _error = 'The request timed out. Please try again.');
      }
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to respond right now. Try again.');
      }
    } finally {
      if (loadingPopupOpen && mounted) {
        loadingPopupOpen = false;
        _presentResolveEffect4();
      }
      if (mounted) setState(() => _isResolving = false);
    }
  }

  /// Computes terminal content.
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

  /// Delegates departure label to the ViewModel.
  String _departureLabel() => _screenModel.commandDepartureLabel();

  /// Delegates profile text to the ViewModel.
  String _profileText(String key, [String fallback = 'Not provided']) =>
      _screenModel.commandProfileText(key, fallback);

  /// Delegates history subtitle to the ViewModel.
  String _historySubtitle(Map<String, dynamic> hike) =>
      _screenModel.commandHistorySubtitle(hike);

  /// Builds this widget from its current presentation state.
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
        constraints: BoxConstraints(
          maxWidth: 430,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
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
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: accent.withValues(
                                alpha: isDark ? 0.2 : 0.1,
                              ),
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
                                  style: TextStyle(
                                    color: secondary,
                                    height: 1.4,
                                  ),
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
                                  const Icon(
                                    Icons.terrain_rounded,
                                    color: _green,
                                  ),
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
                        const SizedBox(height: 14),
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
                                  CircleAvatar(
                                    radius: 25,
                                    backgroundColor: _green.withValues(
                                      alpha: 0.14,
                                    ),
                                    backgroundImage:
                                        _profileText('photoURL', '').isEmpty
                                        ? null
                                        : NetworkImage(
                                            _profileText('photoURL', ''),
                                          ),
                                    child: _profileText('photoURL', '').isEmpty
                                        ? const Icon(
                                            Icons.person_rounded,
                                            color: _green,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _profileText(
                                            'displayName',
                                            widget.review.requesterName,
                                          ),
                                          style: TextStyle(
                                            color: text,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          '${_profileText('hikerLevelName', 'Hiker')} · '
                                          '${widget.review.profile['achievementPoints'] ?? 0} points',
                                          style: TextStyle(color: secondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _ProfileLine(
                                icon: Icons.landscape_outlined,
                                label: 'Experience',
                                value: _profileText('hikerExperience'),
                                color: secondary,
                              ),
                              _ProfileLine(
                                icon: Icons.calendar_month_outlined,
                                label: 'Hike frequency',
                                value: _profileText('hikeFrequency'),
                                color: secondary,
                              ),
                              _ProfileLine(
                                icon: Icons.location_on_outlined,
                                label: 'Area',
                                value: _profileText('residentialLocation'),
                                color: secondary,
                              ),
                              if (widget.review.achievements.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  'Achievements',
                                  style: TextStyle(
                                    color: text,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: widget.review.achievements
                                      .map(
                                        (achievement) => Chip(
                                          avatar: const Icon(
                                            Icons.workspace_premium_rounded,
                                            size: 17,
                                            color: Color(0xFFF59E0B),
                                          ),
                                          label: Text(
                                            achievement['title']?.toString() ??
                                                'Achievement',
                                          ),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                              if (widget.review.hikeHistory.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'Recent hike history',
                                  style: TextStyle(
                                    color: text,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                for (final hike in widget.review.hikeHistory)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.route_rounded,
                                      color: _green,
                                    ),
                                    title: Text(
                                      hike['trailName']?.toString() ?? 'Hike',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(_historySubtitle(hike)),
                                  ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                'Phone number and private route data are never shown.',
                                style: TextStyle(
                                  color: secondary,
                                  fontSize: 11,
                                ),
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
                    ],
                  ),
                ),
              ),
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
                        child: const Text('Accept'),
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

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Presents the resolve effect1 UI.
  Future<void> _presentResolveEffect1() => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const HikerCircleLoadingToast(
      compact: true,
      message: 'Updating join request…',
      detail: 'Saving the host decision securely.',
    ),
  );

  /// Presents the resolve effect2 UI.
  void _presentResolveEffect2() =>
      Navigator.of(context, rootNavigator: true).pop();

  /// Presents the resolve effect3 UI.
  void _presentResolveEffect3(UpcomingHikeJoinRequestReview result) =>
      Navigator.of(context).pop(result);

  /// Presents the resolve effect4 UI.
  void _presentResolveEffect4() =>
      Navigator.of(context, rootNavigator: true).pop();
}

/// Displays the profile line.
class _ProfileLine extends StatelessWidget {
  /// Creates profile line.
  const _ProfileLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(color: color)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
