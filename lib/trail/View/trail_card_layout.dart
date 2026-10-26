import 'package:flutter/material.dart';
import '../../core/widgets/page_header_style.dart';
import '../Model/trail_card_view.dart';
import '../Model/trail_models.dart';
import '../ModelView/trail_card_view_model.dart';

export '../Model/trail_card_view.dart';

/// Rebuilds trail presentation when the shared layout preference changes.
class TrailCardViewBuilder extends StatelessWidget {
  /// Creates a binding to the shared or supplied layout ViewModel.
  const TrailCardViewBuilder({
    super.key,
    required this.builder,
    this.viewModel,
  });

  final Widget Function(BuildContext, TrailCardView, VoidCallback) builder;
  final TrailCardViewModel? viewModel;

  /// Supplies the current layout and its toggle command to the view.
  @override
  Widget build(BuildContext context) {
    final model = viewModel ?? TrailCardViewModel.instance;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => builder(context, model.view, model.toggle),
    );
  }
}

/// Displays the trail view toggle.
class TrailViewToggle extends StatelessWidget {
  /// Creates trail view toggle.
  const TrailViewToggle({
    super.key,
    required this.view,
    required this.onPressed,
  });
  final TrailCardView view;
  final VoidCallback onPressed;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => PageHeaderAction(
    tooltip: view == TrailCardView.list
        ? 'Switch to grid view'
        : 'Switch to list view',
    icon: view == TrailCardView.list
        ? Icons.grid_view_rounded
        : Icons.view_list_rounded,
    onPressed: onPressed,
    color: Theme.of(context).colorScheme.primary,
    surface: Theme.of(context).colorScheme.surface,
  );
}

/// Both modes share the filtered/sorted items and the surrounding page's scroll view.
class TrailCardCollection extends StatelessWidget {
  /// Creates trail card collection.
  const TrailCardCollection({
    super.key,
    required this.view,
    required this.itemCount,
    required this.itemBuilder,
  });
  final TrailCardView view;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (view == TrailCardView.list) {
      return Column(
        key: const ValueKey('trail-list-view'),
        children: [
          for (var index = 0; index < itemCount; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: itemBuilder(context, index),
            ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 320 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.3
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          key: const ValueKey('trail-grid-view'),
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var index = 0; index < itemCount; index++)
              SizedBox(width: width, child: itemBuilder(context, index)),
          ],
        );
      },
    );
  }
}

/// Displays the trail card rating.
class TrailCardRating extends StatelessWidget {
  /// Creates trail card rating.
  const TrailCardRating({super.key, required this.trail});
  final Trail trail;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 18),
      const SizedBox(width: 3),
      Expanded(
        child: Text(
          trail.cardRatingLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}
