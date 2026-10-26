part of '../../trail_page_feature.dart';

/// Displays the header.
class _Header extends StatelessWidget {
  /// Creates header.
  const _Header({
    required this.isAdmin,
    required this.onAddTrail,
    required this.view,
    required this.onToggleView,
  });

  final bool isAdmin;
  final VoidCallback onAddTrail;
  final TrailCardView view;
  final VoidCallback onToggleView;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Discover Trails',
                  style: PageHeaderStyle.title(
                    context,
                    _TrailColors.textFor(context),
                  ),
                ),
                Text(
                  'Pick a route by conditions, safety, and team fit',
                  style: PageHeaderStyle.subtitle(
                    context,
                    _TrailColors.secondaryTextFor(context),
                  ),
                ),
              ],
            ),
          ),
          if (isAdmin)
            PageHeaderAction(
              tooltip: 'Add trail',
              icon: Icons.add_rounded,
              onPressed: onAddTrail,
              color: _TrailColors.green,
              surface: _TrailColors.surfaceFor(context),
            ),
          if (isAdmin) const SizedBox(width: 6),
          TrailViewToggle(
            key: const ValueKey('trail-view-toggle'),
            view: view,
            onPressed: onToggleView,
          ),
        ],
      ),
    );
  }
}

/// Displays the trail insight strip.
class _TrailInsightStrip extends StatelessWidget {
  /// Creates trail insight strip.
  const _TrailInsightStrip({
    required this.visibleCount,
    required this.verifiedCount,
    required this.hazardCount,
  });

  final int visibleCount;
  final int verifiedCount;
  final int hazardCount;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _InsightTile(
              label: 'Matches',
              value: '$visibleCount',
              icon: Icons.filter_alt_rounded,
              color: _TrailColors.green,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _InsightTile(
              label: 'Verified',
              value: '$verifiedCount',
              icon: Icons.verified_rounded,
              color: _TrailColors.blue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _InsightTile(
              label: 'Hazards',
              value: '$hazardCount',
              icon: Icons.warning_amber_rounded,
              color: _TrailColors.orange,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the insight tile.
class _InsightTile extends StatelessWidget {
  /// Creates insight tile.
  const _InsightTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 18),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _TrailColors.textFor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _TrailColors.secondaryTextFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the detail header.
class _DetailHeader extends StatelessWidget {
  /// Creates detail header.
  const _DetailHeader({required this.onBack, this.subtitle});

  final VoidCallback onBack;
  final String title = 'Trail';
  final String? subtitle;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) =>
      PageHeader(title: title, subtitle: subtitle, onBack: onBack);
}

/// Displays the trail card.
class _TrailCard extends StatelessWidget {
  /// Creates trail card.
  const _TrailCard({
    super.key,
    required this.trail,
    required this.onOpenTrail,
    this.grid = false,
    this.onEditTrail,
    this.onDeleteTrail,
  });

  final Trail trail;
  final VoidCallback onOpenTrail;
  final bool grid;
  final Future<void> Function()? onEditTrail;
  final Future<void> Function()? onDeleteTrail;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          trail.name,
          maxLines: grid ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _TrailColors.textFor(context),
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          trail.locationLabel,
          maxLines: grid ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _TrailColors.secondaryTextFor(context),
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${trail.distanceLabel} - Approx. ${trail.durationLabel}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _TrailColors.textFor(context),
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        TrailCardRating(trail: trail),
      ],
    );
    final card = _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenTrail,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: grid
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TrailCover(
                        trail: trail,
                        height: 110,
                        width: double.infinity,
                        showLocationLabel: false,
                      ),
                      const SizedBox(height: 10),
                      details,
                    ],
                  )
                : Row(
                    children: [
                      _TrailCover(trail: trail, height: 94, width: 96),
                      const SizedBox(width: 12),
                      Expanded(child: details),
                      const SizedBox(width: 8),
                      const Icon(CupertinoIcons.chevron_forward, size: 16),
                    ],
                  ),
          ),
        ),
      ),
    );

    if (onEditTrail == null || onDeleteTrail == null) {
      return card;
    }

    return Dismissible(
      key: ValueKey('trail-${trail.trailId}-${trail.name}'),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await onEditTrail?.call();
          return false;
        }

        await onDeleteTrail?.call();
        return false;
      },
      background: const _TrailSwipeActionBackground(
        alignment: Alignment.centerLeft,
        color: _TrailColors.green,
        icon: Icons.edit_rounded,
        label: 'Edit',
      ),
      secondaryBackground: _TrailSwipeActionBackground(
        alignment: Alignment.centerRight,
        color: _TrailColors.redFor(context),
        icon: Icons.delete_rounded,
        label: 'Delete',
      ),
      child: card,
    );
  }
}

/// Displays the trail image credit tile.
class _TrailImageCreditTile extends StatelessWidget {
  /// Creates trail image credit tile.
  const _TrailImageCreditTile({required this.index, required this.credit});

  final int index;
  final TrailImageCredit credit;

  /// Opens link.
  Future<void> _openLink(BuildContext context, String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    final launched =
        uri != null &&
        const {'https', 'http'}.contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open this credit link.')),
      );
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final sourceLabel = credit.sourceName.trim().isEmpty
        ? 'Image source'
        : credit.sourceName.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Image $index · $sourceLabel',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (credit.description.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(credit.description.trim()),
        ],
        if (credit.author.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          Text('By ${credit.author.trim()}'),
        ],
        if (credit.licenseName.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text('License: ${credit.licenseName.trim()}'),
        ],
        if (credit.sourcePageUri != null || credit.licenseUri != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (credit.sourcePageUri != null)
                OutlinedButton.icon(
                  onPressed: () =>
                      _openLink(context, credit.sourcePageUrl.trim()),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('View source'),
                ),
              if (credit.licenseUri != null)
                OutlinedButton(
                  onPressed: () => _openLink(context, credit.licenseUrl.trim()),
                  child: const Text('View license'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Displays the trail plan card.
class _TrailPlanCard extends StatelessWidget {
  /// Creates trail plan card.
  const _TrailPlanCard({required this.trail, required this.onStartHike});

  final Trail trail;
  final VoidCallback onStartHike;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _Glyph(icon: Icons.route_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plan this hike',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _TrailColors.textFor(context),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                      ),
                      Text(
                        _planSummary(trail),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _TrailColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onStartHike,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the hero pill.
class _HeroPill extends StatelessWidget {
  /// Creates hero pill.
  const _HeroPill({required this.label});

  final String label;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// Displays the route preview mode label.
class _RoutePreviewModeLabel extends StatelessWidget {
  /// Creates route preview mode label.
  const _RoutePreviewModeLabel({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : _TrailColors.textFor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the extra detail card.
class _ExtraDetailCard extends StatelessWidget {
  /// Creates extra detail card.
  const _ExtraDetailCard({required this.weather, required this.uvLabel});

  final TrailWeather weather;
  final String Function(double uvIndex) uvLabel;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    /// Adds row.
    void addRow(String label, String value) {
      if (rows.isNotEmpty) {
        rows.add(const _HorizontalSeparator());
      }
      rows.add(_StatusRow(label: label, value: value));
    }

    if (weather.feelsLike != null) {
      addRow('Feels like', '${weather.feelsLike!.round()} °C');
    }
    if (weather.humidity != null) {
      addRow('Humidity', '${weather.humidity}%');
    }
    if (weather.windSpeed != null) {
      addRow('Wind', '${weather.windSpeed!.toStringAsFixed(1)} km/h');
    }
    if (weather.uvIndex != null) {
      addRow('UV Index', uvLabel(weather.uvIndex!));
    }

    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: rows),
      ),
    );
  }
}

/// Displays the hourly forecast row.
class _HourlyForecastRow extends StatelessWidget {
  /// Creates hourly forecast row.
  const _HourlyForecastRow({required this.forecast});

  final HourlyForecast forecast;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final hour = forecast.time.hour.toString().padLeft(2, '0');
    final minute = forecast.time.minute.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '$hour:$minute',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _TrailColors.textFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            _weatherIcon(forecast.weatherCode),
            size: 18,
            color: _TrailColors.secondaryTextFor(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              forecast.weatherLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _TrailColors.secondaryTextFor(context),
                letterSpacing: 0,
              ),
            ),
          ),
          Text(
            '${forecast.temperature.round()}°C',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _TrailColors.textFor(context),
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 36,
            child: Text(
              '${forecast.precipitationProbability}%',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: forecast.precipitationProbability > 50
                    ? _TrailColors.orange
                    : _TrailColors.secondaryTextFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Computes weather icon.
  IconData _weatherIcon(int code) {
    if (code == 0) return Icons.light_mode_rounded;
    if (code <= 2) return Icons.cloud_rounded;
    if (code <= 3) return Icons.cloud_queue_rounded;
    if (code <= 48) return Icons.foggy;
    if (code <= 67) return Icons.water_drop_rounded;
    if (code <= 77) return Icons.ac_unit_rounded;
    if (code <= 86) return Icons.umbrella_rounded;
    return Icons.thunderstorm_rounded;
  }
}

/// Displays the difficulty breakdown card.
class _DifficultyBreakdownCard extends StatelessWidget {
  /// Creates difficulty breakdown card.
  const _DifficultyBreakdownCard({required this.trail});

  final Trail trail;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final total = trail.difficultyRatingCount;
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Community result: ${trail.difficulty}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _TrailColors.textFor(context),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Based on $total completed-hike ${total == 1 ? 'vote' : 'votes'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _TrailColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.groups_2_rounded, color: _TrailColors.green),
              ],
            ),
            const SizedBox(height: 18),
            _DifficultyBarRow(
              label: 'Easy',
              votes: trail.easyDifficultyVotes,
              fraction: trail.difficultyVoteFraction('easy'),
              color: const Color(0xFF34A853),
            ),
            const SizedBox(height: 14),
            _DifficultyBarRow(
              label: 'Moderate',
              votes: trail.moderateDifficultyVotes,
              fraction: trail.difficultyVoteFraction('moderate'),
              color: const Color(0xFFF59E0B),
            ),
            const SizedBox(height: 14),
            _DifficultyBarRow(
              label: 'Hard',
              votes: trail.hardDifficultyVotes,
              fraction: trail.difficultyVoteFraction('hard'),
              color: const Color(0xFFE05252),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the difficulty bar row.
class _DifficultyBarRow extends StatelessWidget {
  /// Creates difficulty bar row.
  const _DifficultyBarRow({
    required this.label,
    required this.votes,
    required this.fraction,
    required this.color,
  });

  final String label;
  final int votes;
  final double fraction;
  final Color color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final percentage = (fraction * 100).round();
    return Semantics(
      label: '$label, $percentage percent, $votes votes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 76,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: _TrailColors.textFor(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: fraction.clamp(0, 1),
                    minHeight: 10,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 76,
                child: Text(
                  '$percentage% · $votes',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _TrailColors.secondaryTextFor(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Displays the weather card.
class _WeatherCard extends StatelessWidget {
  /// Creates weather card.
  const _WeatherCard({required this.trail});

  final Trail trail;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final weather = trail.weather;
    final cachedAt = weather.cachedAt;
    final diff = DateTime.now().toUtc().difference(cachedAt.toUtc());
    final refreshedText = diff.inMinutes < 1
        ? 'Just now'
        : diff.inMinutes < 60
        ? '${diff.inMinutes}m ago'
        : diff.inHours < 24
        ? '${diff.inHours}h ago'
        : '${diff.inDays}d ago';

    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _StatusRow(label: 'Today', value: weather.summary),
            const _HorizontalSeparator(),
            _StatusRow(label: 'Temperature', value: weather.temperatureRange),
            const _HorizontalSeparator(),
            _StatusRow(
              label: 'Rain Probability',
              value: '${weather.rainProbability}%',
            ),
            if (weather.windSpeed != null) ...[
              const _HorizontalSeparator(),
              _StatusRow(
                label: 'Wind',
                value: '${weather.windSpeed!.toStringAsFixed(0)} km/h',
              ),
            ],
            if (weather.humidity != null) ...[
              const _HorizontalSeparator(),
              _StatusRow(label: 'Humidity', value: '${weather.humidity}%'),
            ],
            const _HorizontalSeparator(),
            _StatusRow(label: 'Refreshed', value: refreshedText),
          ],
        ),
      ),
    );
  }
}

/// Displays the status row.
class _StatusRow extends StatelessWidget {
  /// Creates status row.
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _TrailColors.textFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _TrailColors.secondaryTextFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the empty state.
class _EmptyState extends StatelessWidget {
  /// Creates empty state.
  const _EmptyState({required this.message});

  final String message;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Center(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _TrailColors.secondaryTextFor(context),
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the status pill.
class _StatusPill extends StatelessWidget {
  /// Creates status pill.
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
