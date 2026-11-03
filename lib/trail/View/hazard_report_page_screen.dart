part of '../hazard_report_page_feature.dart';

/// Displays the hazard report page.
class HazardReportPage extends StatefulWidget {
  /// Creates hazard report page.
  const HazardReportPage({
    super.key,
    required this.session,
    required this.hikerCircleRepository,
    required this.trail,
  });
  final AppSession session;
  final HikerCircleFirebaseRepository hikerCircleRepository;
  final Trail trail;

  /// Creates the presentation state for this widget.
  @override
  State<HazardReportPage> createState() => _HazardReportPageState();
}

/// Manages the hazard report page presentation and lifecycle.
class _HazardReportPageState extends State<HazardReportPage> {
  final evidence = GlobalKey<CautionEvidenceEditorState>();
  String? category, selected, error;
  bool busy = false;
  late final reportId =
      'report_${DateTime.now().microsecondsSinceEpoch}_${widget.session.phoneNumber.replaceAll(RegExp(r'[^0-9]'), '')}';

  /// Computes back.
  void back() {
    if (busy) return;
    if (category != null) {
      setState(() {
        category = null;
        selected = null;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Save the report and evidence locally; the retry queue publishes it later.
  Future<void> submit() async {
    if (busy || selected == null || evidence.currentState?.picking == true) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final route = ModalRoute.of<void>(context);
    try {
      final location = await LocationSnapshotService.instance.refresh().timeout(
        const Duration(seconds: 4),
        onTimeout: () => LocationSnapshotService.instance.latestLocation,
      );
      if (location == null ||
          location.capturedAt == null ||
          DateTime.now().toUtc().difference(location.capturedAt!.toUtc()) >
              const Duration(seconds: 30)) {
        throw StateError(
          'Waiting for a current GPS location. Try again when your location is available.',
        );
      }
      await _HazardReportPageDataActions.submitHazardReport(
        widget.hikerCircleRepository,
      )(
        session: widget.session,
        trail: widget.trail,
        hazardType: selected!,
        description: evidence.currentState!.note.text,
        severity: trailHazardTypeIsFatal(selected!) ? 'fatal' : 'moderate',
        location: location,
        reportId: reportId,
        media: evidence.currentState!.files,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      _presentSubmitEffect1(route);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Caution saved on this phone. It will send automatically when connected. Check history for its status.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                children: [
                  Row(
                    children: [
                      PageHeaderAction(
                        tooltip: 'Back',
                        icon: Icons.arrow_back_rounded,
                        onPressed: busy ? null : back,
                        color: colors.onSurface,
                        surface: colors.surfaceContainerLow,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Report a Caution',
                              style: PageHeaderStyle.title(
                                context,
                                colors.onSurface,
                              ),
                            ),
                            Text(
                              widget.trail.name,
                              style: PageHeaderStyle.subtitle(
                                context,
                                colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PageHeaderAction(
                        tooltip: 'Caution report history',
                        icon: Icons.history_rounded,
                        onPressed: busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => CautionReportHistoryPage(
                                    session: widget.session,
                                    repository: widget.hikerCircleRepository,
                                  ),
                                ),
                              ),
                        color: colors.onSurface,
                        surface: colors.surfaceContainerLow,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'What is on the trail?',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Let nearby hikers know what to look out for.'),
                  const SizedBox(height: 18),
                  if (category == null) ...[
                    for (final entry in trailHazardReportCategories.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: busy
                                ? null
                                : () => setState(() => category = entry.key),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: colors.primary.withValues(
                                        alpha: .12,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      entry.value.$1,
                                      color: colors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      entry.key,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ] else ...[
                    Row(
                      children: [
                        Icon(
                          trailHazardReportCategories[category]!.$1,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            category!,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: busy ? null : back,
                          child: const Text('Change'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: [
                        for (final type
                            in trailHazardReportCategories[category]!.$2)
                          ChoiceChip(
                            avatar: Icon(trailHazardIconFor(type), size: 19),
                            label: Text(type),
                            selected: selected == type,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            onSelected: busy
                                ? null
                                : (_) => setState(() => selected = type),
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),
                  ],
                  Offstage(
                    offstage: selected == null,
                    child: CautionEvidenceEditor(key: evidence, enabled: !busy),
                  ),
                  if (selected != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: trailHazardTypeIsFatal(selected!)
                            ? colors.errorContainer.withValues(alpha: .5)
                            : colors.primaryContainer.withValues(alpha: .4),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CautionIcon(
                            icon: trailHazardIconFor(selected!),
                            seriousRisk: trailHazardTypeIsFatal(selected!),
                            color: trailHazardTypeIsFatal(selected!)
                                ? colors.error
                                : colors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              trailHazardTypeIsFatal(selected!)
                                  ? 'Serious risk: hikers will be advised to cancel or choose another time.'
                                  : 'Hikers will be reminded to prepare and stay alert.',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Icon(
                          Icons.my_location_rounded,
                          size: 18,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Your current GPS location will be attached.',
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        error!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: selected == null
            ? null
            : SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                child: FilledButton.icon(
                  onPressed: busy ? null : submit,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.warning_amber_rounded),
                  label: Text(busy ? 'Reporting…' : 'Report here'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
      ),
    );
  }

  /// Presents the submit effect1 UI.
  void _presentSubmitEffect1(ModalRoute<void>? route) =>
      HikeStartNavigation.closeOwnedRoute(route);
}
