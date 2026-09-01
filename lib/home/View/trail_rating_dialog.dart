import 'package:flutter/material.dart';

import '../../core/widgets/loading_toast.dart';

class TrailRatingFeedback {
  const TrailRatingFeedback({
    required this.rating,
    required this.difficulty,
    required this.comment,
  });

  final int rating;
  final String difficulty;
  final String comment;
}

class TrailRatingDialog extends StatefulWidget {
  const TrailRatingDialog({
    super.key,
    required this.trailName,
    required this.onSubmit,
  });

  final String trailName;
  final Future<void> Function(TrailRatingFeedback feedback) onSubmit;

  @override
  State<TrailRatingDialog> createState() => _TrailRatingDialogState();
}

class _TrailRatingDialogState extends State<TrailRatingDialog> {
  final _commentController = TextEditingController();
  int _rating = 0;
  String? _difficulty;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _difficulty == null || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await widget.onSubmit(
        TrailRatingFeedback(
          rating: _rating,
          difficulty: _difficulty!,
          comment: _commentController.text.trim(),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = error.toString();
      });
    }
  }

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
        content: SingleChildScrollView(
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
                  for (final difficulty in const ['Easy', 'Moderate', 'Hard'])
                    ChoiceChip(
                      key: Key('trail-difficulty-${difficulty.toLowerCase()}'),
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
              TextField(
                key: const Key('trail-rating-comment'),
                controller: _commentController,
                enabled: !_isSubmitting,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Comment (optional)',
                  hintText: 'Trail conditions, views, or helpful tips...',
                  alignLabelWithHint: true,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 2),
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
                'Your rating and difficulty vote contribute to this route’s public community results.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
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
            child: _isSubmitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: HikerCircleMinorLoadingIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Submit rating'),
          ),
        ],
      ),
    );
  }
}

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
