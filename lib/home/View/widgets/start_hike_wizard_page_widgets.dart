part of '../../start_hike_wizard_page_feature.dart';

/// Displays the header.
class _Header extends StatelessWidget {
  /// Creates header.
  const _Header({required this.onBack});

  final VoidCallback onBack;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => PageHeader(
    title: 'Create Hiking Session',
    subtitle: 'Plan timing, safety, and route preparation',
    onBack: onBack,
  );
}

/// Displays the step card.
class _StepCard extends StatelessWidget {
  /// Creates step card.
  const _StepCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _WizardColors.textFor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _WizardColors.secondaryTextFor(context),
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Displays the choice tile.
class _ChoiceTile extends StatelessWidget {
  /// Creates choice tile.
  const _ChoiceTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final color = selected
        ? _WizardColors.green
        : _WizardColors.secondaryTextFor(context);

    return Material(
      color: selected
          ? _WizardColors.greenSoftFor(context)
          : _WizardColors.surfaceFor(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? _WizardColors.green
                  : _WizardColors.separatorFor(context),
            ),
          ),
          child: Row(
            children: [
              _Glyph(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _WizardColors.textFor(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _WizardColors.secondaryTextFor(context),
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: _WizardColors.green,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the tappable field.
class _TappableField extends StatelessWidget {
  /// Creates tappable field.
  const _TappableField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: Icon(
            Icons.edit_rounded,
            size: 18,
            color: _WizardColors.secondaryTextFor(context),
          ),
        ),
        child: Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: _WizardColors.textFor(context),
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

/// Displays the duration picker field.
class _DurationPickerField extends StatelessWidget {
  /// Creates duration picker field.
  const _DurationPickerField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final Duration value;
  final ValueChanged<Duration> onChanged;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showPicker(context),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Estimated Hike Duration',
          prefixIcon: Icon(Icons.timer_rounded),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _durationLabel(value),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: _WizardColors.textFor(context),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded),
          ],
        ),
      ),
    );
  }

  /// Shows picker.
  Future<void> _showPicker(BuildContext context) async {
    var selectedHours = value.inHours.clamp(0, 23).toInt();
    var selectedMinutes = value.inMinutes.remainder(60);
    final hoursController = FixedExtentScrollController(
      initialItem: selectedHours,
    );
    final minutesController = FixedExtentScrollController(
      initialItem: selectedMinutes,
    );
    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: _WizardColors.surfaceFor(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (context) {
          return SafeArea(
            child: SizedBox(
              height: 280,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: _WizardColors.textFor(context),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            final duration = Duration(
                              hours: selectedHours,
                              minutes: selectedMinutes,
                            );
                            onChanged(
                              duration == Duration.zero
                                  ? const Duration(minutes: 1)
                                  : duration,
                            );
                            Navigator.of(context).pop();
                          },
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: CupertinoPicker(
                            itemExtent: 42,
                            scrollController: hoursController,
                            onSelectedItemChanged: (value) {
                              selectedHours = value;
                            },
                            children: [
                              for (var hour = 0; hour <= 23; hour++)
                                Center(child: Text('$hour h')),
                            ],
                          ),
                        ),
                        Expanded(
                          child: CupertinoPicker(
                            itemExtent: 42,
                            scrollController: minutesController,
                            onSelectedItemChanged: (value) {
                              selectedMinutes = value;
                            },
                            children: [
                              for (var minute = 0; minute < 60; minute++)
                                Center(
                                  child: Text(
                                    '${minute.toString().padLeft(2, '0')} min',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      hoursController.dispose();
      minutesController.dispose();
    }
  }
}
