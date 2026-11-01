part of '../upcoming_hike_join_request_dialog_feature.dart';

/// A content-sized host review with an expandable, privacy-safe hiking record.
class UpcomingHikeJoinRequestDialog extends StatefulWidget {
  /// Uses the existing server transaction for both decisions.
  const UpcomingHikeJoinRequestDialog({
    super.key,
    required this.review,
    required this.onResolve,
  });
  final UpcomingHikeJoinRequestReview review;
  final Future<UpcomingHikeJoinRequestReview> Function(bool accept) onResolve;

  /// Creates the host review presentation.
  @override
  State<UpcomingHikeJoinRequestDialog> createState() =>
      _UpcomingHikeJoinRequestDialogState();
}

/// Owns navigation and delegates decision state to its ViewModel.
class _UpcomingHikeJoinRequestDialogState
    extends State<UpcomingHikeJoinRequestDialog> {
  late final _UpcomingHikeJoinRequestDialogStateViewModel _screenModel;
  HikerCircleLoadingDialogRoute? _resolveLoadingRoute;

  /// Binds the fresh canonical review and its decision operation.
  @override
  void initState() {
    super.initState();
    _screenModel = _UpcomingHikeJoinRequestDialogStateViewModel(
      readReview: () => widget.review,
      resolve: (accept) => widget.onResolve(accept),
    )..addListener(_renderScreenModel);
  }

  /// Updates the visible state after validation or a server response.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Presents one compact loading route and closes only this review on success.
  Future<void> _resolve(bool accept) async {
    if (_screenModel.resolving) return;
    final response = _screenModel.commandResolve(accept);
    final loading = HikerCircleLoadingDialogRoute(
      context: context,
      compact: true,
      message: accept ? 'Accepting request…' : 'Rejecting request…',
      detail: 'Updating the hike and request history.',
    );
    _resolveLoadingRoute = loading;
    unawaited(Navigator.of(context, rootNavigator: true).push<void>(loading));
    try {
      final result = await response;
      loading.close();
      _resolveLoadingRoute = null;
      if (!mounted || result == null) return;
      final route = ModalRoute.of<UpcomingHikeJoinRequestReview>(context),
          owner = Navigator.of(context);
      if (route == null || !route.isActive) return;
      if (route.isCurrent) {
        owner.pop(result);
      } else {
        owner.removeRoute(route, result);
      }
    } finally {
      loading.close();
      _resolveLoadingRoute = null;
    }
  }

  /// Releases the model and removes its own loading route after disposal.
  @override
  void dispose() {
    final loading = _resolveLoadingRoute;
    WidgetsBinding.instance.addPostFrameCallback((_) => loading?.close());
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Builds the request with pinned decisions and naturally sized scrollable content.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final pending = widget.review.canResolve, busy = _screenModel.resolving;
    final status = widget.review.status;
    final terminalTitle = status == 'accepted'
        ? 'Request accepted'
        : status == 'rejected'
        ? 'Request rejected'
        : 'Request expired';
    final terminalMessage = status == 'accepted'
        ? 'This hiker has joined the hike.'
        : status == 'rejected'
        ? 'You rejected this request.'
        : 'This hike or join request is no longer available.';
    return PopScope(
      canPop: !busy,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          key: const Key('upcoming-hike-join-review'),
          constraints: BoxConstraints(
            maxWidth: 430,
            maxHeight: MediaQuery.sizeOf(context).height * .84,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        pending
                            ? Icons.person_add_alt_1_rounded
                            : status == 'accepted'
                            ? Icons.check_rounded
                            : Icons.history_rounded,
                        color: colors.primary,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        pending ? 'Join request' : terminalTitle,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Review later',
                      onPressed: busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 21),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!pending)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Text(
                              terminalMessage,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: colors.primary.withValues(
                                alpha: .1,
                              ),
                              child: Icon(
                                Icons.person_outline_rounded,
                                color: colors.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _screenModel.commandRequesterName(),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    pending
                                        ? 'Would like to join your hike'
                                        : widget.review.stats.available
                                        ? 'Level ${widget.review.stats.hikerLevel}'
                                        : 'HikerCircle member',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: .07),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionLabel(
                                label: 'The hike',
                                padding: EdgeInsets.zero,
                              ),
                              const SizedBox(height: 7),
                              Text(
                                widget.review.trailName,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 16,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _screenModel.commandDepartureLabel(),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (pending || widget.review.stats.available) ...[
                          const SizedBox(height: 18),
                          HikeJoinRequestStatsCard(stats: widget.review.stats),
                        ],
                        if (_screenModel.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Text(
                              _screenModel.error!,
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (pending)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final buttons = [
                        OutlinedButton(
                          key: const Key('decline-upcoming-hike-join-request'),
                          onPressed: busy ? null : () => _resolve(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.error,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Reject'),
                        ),
                        FilledButton(
                          key: const Key('accept-upcoming-hike-join-request'),
                          onPressed: busy ? null : () => _resolve(true),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Accept'),
                        ),
                      ];
                      if (MediaQuery.textScalerOf(context).scale(1) > 1.4) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buttons[1],
                            const SizedBox(height: 8),
                            buttons[0],
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: buttons[0]),
                          const SizedBox(width: 10),
                          Expanded(child: buttons[1]),
                        ],
                      );
                    },
                  )
                else
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(widget.review),
                    child: const Text('Close'),
                  ),
                if (pending)
                  TextButton(
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Review later'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
