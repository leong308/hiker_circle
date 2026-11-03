part of '../trail_rating_dialog_feature.dart';

/// Displays the trail rating dialog.
class TrailRatingDialog extends StatefulWidget {
  /// Creates trail rating dialog.
  const TrailRatingDialog({
    super.key,
    required this.trailName,
    required this.onSubmit,
  });

  final String trailName;
  final Future<void> Function(TrailRatingFeedback feedback) onSubmit;

  /// Creates the presentation state for this widget.
  @override
  State<TrailRatingDialog> createState() => _TrailRatingDialogState();
}

/// Manages the trail rating dialog presentation and lifecycle.
class _TrailRatingDialogState extends State<TrailRatingDialog> {
  int _rating = 0;
  String? _difficulty;
  bool _isSubmitting = false;
  String? _errorMessage;
  HikerCircleLoadingDialogRoute? _loadingRoute;

  @override
  void dispose() {
    final loading = _loadingRoute;
    WidgetsBinding.instance.addPostFrameCallback((_) => loading?.close());
    super.dispose();
  }

  /// Computes submit.
  Future<void> _submit() async {
    if (_rating == 0 || _difficulty == null || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final loading = HikerCircleLoadingDialogRoute(
      context: context,
      compact: true,
      message: 'Saving your route rating…',
      detail: 'Keeping your rating with the saved hike on this phone.',
    );
    _loadingRoute = loading;
    unawaited(Navigator.of(context, rootNavigator: true).push<void>(loading));
    try {
      await widget.onSubmit(
        TrailRatingFeedback(rating: _rating, difficulty: _difficulty!),
      );
      loading.close();
      if (mounted) _presentSubmitEffect1();
    } catch (error) {
      loading.close();
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = error.toString();
      });
    } finally {
      loading.close();
      _loadingRoute = null;
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_isSubmitting,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF34A853).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.terrain_rounded,
                color: Color(0xFF34A853),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rate this route',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.trailName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'How was your experience on this trail?',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var star = 1; star <= 5; star++)
                          Semantics(
                            label: '$star star${star == 1 ? '' : 's'}',
                            button: true,
                            selected: star == _rating,
                            child: IconButton(
                              key: Key('trail-rating-star-$star'),
                              onPressed: _isSubmitting
                                  ? null
                                  : () => setState(() => _rating = star),
                              tooltip: '$star star${star == 1 ? '' : 's'}',
                              iconSize: 38,
                              color: const Color(0xFFF59E0B),
                              icon: Icon(
                                star <= _rating
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: Text(
                      _ratingLabel(_rating),
                      key: ValueKey(_rating),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: _rating == 0
                            ? colorScheme.onSurfaceVariant
                            : const Color(0xFF34A853),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'How difficult did this hike feel?',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final difficulty in const [
                        'Easy',
                        'Moderate',
                        'Hard',
                      ])
                        ChoiceChip(
                          key: Key(
                            'trail-difficulty-${difficulty.toLowerCase()}',
                          ),
                          label: Text(difficulty),
                          selected: _difficulty == difficulty.toLowerCase(),
                          onSelected: _isSubmitting
                              ? null
                              : (selected) => setState(() {
                                  _difficulty = selected
                                      ? difficulty.toLowerCase()
                                      : null;
                                }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    'Your rating is saved on this phone and will sync with your completed hike when connected.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('skip-trail-rating'),
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Not now'),
          ),
          FilledButton(
            key: const Key('submit-trail-rating'),
            onPressed: _rating == 0 || _difficulty == null || _isSubmitting
                ? null
                : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF34A853),
              foregroundColor: Colors.white,
            ),
            child: const Text('Save rating'),
          ),
        ],
      ),
    );
  }

  /// Presents the submit effect1 UI.
  void _presentSubmitEffect1() => Navigator.of(context).pop(true);
}

/// Computes rating label.
String _ratingLabel(int rating) {
  return switch (rating) {
    1 => 'Poor',
    2 => 'Fair',
    3 => 'Good',
    4 => 'Great',
    5 => 'Excellent',
    _ => 'Tap a star to rate',
  };
}
