part of '../../sos_page_feature.dart';

/// Displays the header.
class _Header extends StatelessWidget {
  /// Creates header.
  const _Header({
    required this.onOpenTestSettings,
    required this.onOpenPairedButton,
  });

  final VoidCallback onOpenTestSettings;
  final VoidCallback onOpenPairedButton;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SOS',
                  style: PageHeaderStyle.title(
                    context,
                    _SosColors.textFor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Emergency controls and safety checks',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PageHeaderStyle.subtitle(
                    context,
                    _SosColors.secondaryTextFor(context),
                  ),
                ),
              ],
            ),
          ),
          _HeaderAction(
            tooltip: 'Paired SOS button',
            icon: Icons.settings_remote_rounded,
            onPressed: onOpenPairedButton,
          ),
          const SizedBox(width: 8),
          _HeaderAction(
            tooltip: 'Test settings',
            icon: Icons.science_rounded,
            onPressed: onOpenTestSettings,
          ),
        ],
      ),
    );
  }
}

/// Displays the network sos status card.
class _NetworkSosStatusCard extends StatelessWidget {
  /// Creates network sos status card.
  const _NetworkSosStatusCard({
    required this.isNetworkAvailable,
    required this.isCheckingNetwork,
    required this.errorMessage,
  });

  final bool isNetworkAvailable;
  final bool isCheckingNetwork;
  final String? errorMessage;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final color = isCheckingNetwork
        ? _SosColors.orange
        : isNetworkAvailable
        ? _SosColors.green
        : _SosColors.orange;
    final title = isCheckingNetwork
        ? 'Checking network SOS'
        : isNetworkAvailable
        ? 'Network SOS available'
        : 'Cloud SOS unavailable';
    final subtitle = isCheckingNetwork
        ? 'Checking internet reachability before cloud SOS delivery.'
        : isNetworkAvailable
        ? 'Alerts can use cloud logging and WhatsApp delivery when sent.'
        : 'No backend connection right now. WhatsApp dispatch and Firebase cloud logging may fail until connection is restored.';

    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isCheckingNetwork)
              const SizedBox.square(
                dimension: 32,
                child: HikerCircleMinorLoadingIndicator(size: 28),
              )
            else
              _Glyph(
                icon: isNetworkAvailable
                    ? Icons.cloud_done_rounded
                    : Icons.signal_wifi_connected_no_internet_4_rounded,
                color: color,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: _SosColors.textFor(context),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                        ),
                      ),
                      _StatusPill(
                        label: isCheckingNetwork
                            ? 'Checking'
                            : isNetworkAvailable
                            ? 'Online'
                            : 'Offline',
                        color: color,
                        surface: color.withValues(alpha: 0.12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    errorMessage == null ? subtitle : '$subtitle $errorMessage',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SosColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the active nearby sos events panel.
class _ActiveNearbySosEventsPanel extends StatelessWidget {
  /// Creates active nearby sos events panel.
  const _ActiveNearbySosEventsPanel({
    required this.events,
    required this.phoneLocation,
    required this.onTap,
  });

  final List<NearbySosEvent> events;
  final SosTriggerLocation? phoneLocation;
  final ValueChanged<NearbySosEvent> onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                const _Glyph(icon: Icons.sos_rounded, color: _SosColors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nearby SOS needed',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _SosColors.textFor(context),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                      ),
                      Text(
                        events.length == 1
                            ? '1 active nearby event'
                            : '${events.length} active nearby events',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _SosColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(
                  label: 'Active',
                  color: _SosColors.orange,
                  surface: _SosColors.orange.withValues(alpha: 0.12),
                ),
              ],
            ),
          ),
          const _HorizontalSeparator(),
          for (var index = 0; index < events.length; index++) ...[
            _TapSurface(
              onTap: () => onTap(events[index]),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_searching_rounded,
                      color: _SosColors.orange,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            events[index].hasReportedLocation
                                ? 'Reported location available'
                                : 'Approximate nearby area',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: _SosColors.textFor(context),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _nearbySosEventSummary(
                              events[index],
                              phoneLocation,
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _SosColors.secondaryTextFor(context),
                                  letterSpacing: 0,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_forward,
                      color: _SosColors.chevronFor(context),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
            if (index != events.length - 1) const _HorizontalSeparator(),
          ],
        ],
      ),
    );
  }
}

/// Displays the nearby sos history row.
class _NearbySosHistoryRow extends StatelessWidget {
  /// Creates nearby sos history row.
  const _NearbySosHistoryRow({
    required this.event,
    required this.phoneLocation,
    required this.onTap,
  });

  final NearbySosEvent event;
  final SosTriggerLocation? phoneLocation;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final distance = event.distanceMetersFrom(phoneLocation);
    final archivedByAge =
        event.ageAt(DateTime.now().toUtc()) > NearbySosEvent.activeDuration;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Glyph(icon: Icons.sos_rounded, color: _SosColors.orange),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NEARBY SOS',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _SosColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _nearbySosTimestamp(event.receivedAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SosColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _StatusPill(
                        label: event.hasReportedLocation
                            ? 'Location reported'
                            : 'Approximate area',
                        color: _SosColors.orange,
                        surface: _SosColors.orange.withValues(alpha: 0.12),
                      ),
                      _StatusPill(
                        label: archivedByAge
                            ? 'Over 1 hour old'
                            : distance == null
                            ? 'Distance unavailable'
                            : _nearbySosDistance(distance),
                        color: _SosColors.secondaryTextFor(context),
                        surface: _SosColors.surfaceFor(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

/// Displays the admin sos system logs panel.
class _AdminSosSystemLogsPanel extends StatelessWidget {
  /// Creates admin sos system logs panel.
  const _AdminSosSystemLogsPanel({
    required this.onOpen,
    required this.logs,
    required this.nearbyEvents,
    required this.isLoading,
    required this.errorMessage,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> logs;
  final VoidCallback onOpen;
  final List<NearbySosEvent> nearbyEvents;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRefresh;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final eventCount = logs.length + nearbyEvents.length;
    final subtitle = errorMessage != null && eventCount == 0
        ? 'Unable to load events. Tap to inspect the status.'
        : eventCount == 0
        ? 'No SOS events found yet.'
        : '$eventCount event${eventCount == 1 ? '' : 's'} available. Tap to view all.';

    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                _Glyph(
                  icon: Icons.receipt_long_rounded,
                  color: errorMessage == null
                      ? _SosColors.green
                      : _SosColors.orange,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SOS events',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _SosColors.textFor(context),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _SosColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh SOS events',
                  onPressed: isLoading ? null : onRefresh,
                  icon: isLoading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: HikerCircleMinorLoadingIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the sos system log row.
class _SosSystemLogRow extends StatelessWidget {
  /// Creates sos system log row.
  const _SosSystemLogRow({required this.log});

  final Map<String, dynamic> log;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final status = _sosLogString(log['status'], fallback: 'unknown');
    final mode = _sosLogString(log['mode'], fallback: 'sos');
    final sent = _sosLogInt(log['sentCount']);
    final failed = _sosLogInt(log['failedCount']);
    final contactCount = _sosLogInt(log['contactCount']);
    final unconfirmed = SosAlert.fromFirestore(log).unconfirmedCount > 0;
    final color = failed > 0 || status == 'failed'
        ? _SosColors.orange
        : _SosColors.green;

    return InkWell(
      onTap: () => _showSosSystemLogDetails(context, log),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(
              icon: failed > 0 || status == 'failed'
                  ? Icons.warning_amber_rounded
                  : Icons.verified_rounded,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_friendlySosType(mode)} · ${status == 'partial' ? '$sent of $contactCount contacts confirmed' : _friendlySosStatus(status)}',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _SosColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _sosLogDateLabel(log['triggeredAtLocal']),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SosColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _StatusPill(
                        label: '$sent of $contactCount contacts confirmed',
                        color: _SosColors.green,
                        surface: _SosColors.greenSoftFor(context),
                      ),
                      _StatusPill(
                        label: failed == 0
                            ? unconfirmed
                                  ? 'Unconfirmed'
                                  : sent < contactCount
                                  ? 'Awaiting confirmation'
                                  : 'All contacts confirmed'
                            : '$failed need attention',
                        color: failed > 0
                            ? _SosColors.orange
                            : _SosColors.secondaryTextFor(context),
                        surface: _SosColors.surfaceFor(context),
                      ),
                      _StatusPill(
                        label: '$contactCount contacts',
                        color: _SosColors.secondaryTextFor(context),
                        surface: _SosColors.surfaceFor(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

/// Displays the sos system log empty state.
class _SosSystemLogEmptyState extends StatelessWidget {
  /// Creates sos system log empty state.
  const _SosSystemLogEmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _Glyph(icon: icon, color: _SosColors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _SosColors.secondaryTextFor(context),
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the emergency sos control card.
class _EmergencySosControlCard extends StatefulWidget {
  /// Creates emergency sos control card.
  const _EmergencySosControlCard({
    required this.isSending,
    required this.isAlarmActive,
    required this.onTrigger,
    required this.onStopAlarm,
    required this.onShowGuide,
    required this.onDuressLongPress,
  });

  final bool isSending;
  final bool isAlarmActive;
  final VoidCallback onTrigger;
  final VoidCallback onStopAlarm;
  final VoidCallback onShowGuide;
  final VoidCallback onDuressLongPress;

  /// Creates the presentation state for this widget.
  @override
  State<_EmergencySosControlCard> createState() =>
      _EmergencySosControlCardState();
}

/// Manages the emergency sos control card presentation and lifecycle.
class _EmergencySosControlCardState extends State<_EmergencySosControlCard>
    with SingleTickerProviderStateMixin {
  late final _EmergencySosControlCardStateViewModel _screenModel;

  /// Returns duress triggered.
  bool get _duressTriggered => _screenModel.stateDuressTriggered;

  /// Updates duress triggered.
  set _duressTriggered(bool value) => _screenModel.stateDuressTriggered = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  static const Duration _duressHoldDuration = Duration(milliseconds: 1200);

  late final AnimationController _holdController;
  bool _isPressing = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _EmergencySosControlCardStateViewModel(
      readIsAlarmActive: () => widget.isAlarmActive,
      readIsSending: () => widget.isSending,
      readOnStopAlarm: () => widget.onStopAlarm,
      readOnTrigger: () => widget.onTrigger,
      effectCancelPress: _cancelPress,
    )..addListener(_renderScreenModel);

    _holdController =
        AnimationController(vsync: this, duration: _duressHoldDuration)
          ..addStatusListener((status) {
            if (status != AnimationStatus.completed ||
                _duressTriggered ||
                widget.isSending ||
                widget.isAlarmActive) {
              return;
            }
            _duressTriggered = true;
            if (mounted) setState(() {});
            widget.onDuressLongPress();
          });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _holdController.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Handles tap down.
  void _handleTapDown(TapDownDetails details) {
    if (widget.isSending && !widget.isAlarmActive) return;
    _duressTriggered = false;
    setState(() => _isPressing = true);
    if (!widget.isAlarmActive) {
      _holdController.forward(from: 0);
    }
  }

  /// Delegates handle tap up to the ViewModel.
  void _handleTapUp(TapUpDetails details) =>
      _screenModel.commandHandleTapUp(details);

  /// Cancels press.
  void _cancelPress() {
    _holdController.stop();
    _holdController.value = 0;
    if (mounted && (_isPressing || _duressTriggered)) {
      setState(() {
        _isPressing = false;
        _duressTriggered = false;
      });
    } else {
      _isPressing = false;
      _duressTriggered = false;
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Emergency SOS',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _SosColors.textFor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: GestureDetector(
                key: const Key('sos-emergency-button'),
                behavior: HitTestBehavior.opaque,
                onTapDown: _handleTapDown,
                onTapUp: _handleTapUp,
                onTapCancel: _cancelPress,
                child: AnimatedBuilder(
                  animation: _holdController,
                  builder: (context, child) {
                    final holdProgress = widget.isAlarmActive
                        ? 0.0
                        : _holdController.value;
                    final idleColor = _SosColors.destructiveFor(context);
                    final buttonColor = widget.isAlarmActive
                        ? _SosColors.green
                        : widget.isSending
                        ? idleColor.withValues(alpha: 0.58)
                        : Color.lerp(
                            idleColor,
                            _SosColors.duress,
                            holdProgress,
                          )!;
                    final actionLabel = widget.isAlarmActive
                        ? 'STOP'
                        : widget.isSending
                        ? 'SENDING'
                        : _duressTriggered
                        ? 'DURESS'
                        : _isPressing
                        ? 'HOLD…'
                        : null;
                    final helperLabel = widget.isAlarmActive
                        ? 'Alarm active'
                        : widget.isSending
                        ? 'Notifying contacts'
                        : _duressTriggered
                        ? 'Silent alert started'
                        : _isPressing
                        ? 'Keep holding for Duress'
                        : 'Tap or hold';
                    return SizedBox.square(
                      dimension: 208,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (holdProgress > 0)
                            SizedBox.square(
                              dimension: 204,
                              child: HikerCircleMinorLoadingIndicator(
                                value: holdProgress,
                                strokeWidth: 5,
                                color: _SosColors.duress,
                                backgroundColor: _SosColors.duress.withValues(
                                  alpha: 0.14,
                                ),
                              ),
                            ),
                          AnimatedScale(
                            scale: _isPressing ? 0.96 : 1,
                            duration: const Duration(milliseconds: 140),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              width: 188,
                              height: 188,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: buttonColor,
                                boxShadow: [
                                  BoxShadow(
                                    color: buttonColor.withValues(alpha: 0.26),
                                    blurRadius: 26,
                                    spreadRadius: 8,
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  width: 7,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    widget.isAlarmActive
                                        ? Icons.notifications_off_rounded
                                        : _duressTriggered
                                        ? Icons.visibility_off_rounded
                                        : Icons.sos_rounded,
                                    color: Colors.white,
                                    size: 46,
                                  ),
                                  SizedBox(
                                    height: actionLabel == null ? 12 : 8,
                                  ),
                                  if (actionLabel != null) ...[
                                    Text(
                                      actionLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  Text(
                                    helperLabel,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Colors.white.withValues(
                                            alpha: 0.88,
                                          ),
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: BoxDecoration(
                color: _SosColors.backgroundFor(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _SosColors.separatorFor(context)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Tap: ',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const TextSpan(
                            text:
                                'Manual SOS with a loud alarm and cancel time.\n',
                          ),
                          TextSpan(
                            text: 'Hold: ',
                            style: TextStyle(
                              color: _SosColors.duress,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const TextSpan(
                            text: 'silent Duress SOS sent without a countdown.',
                          ),
                        ],
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _SosColors.secondaryTextFor(context),
                        height: 1.45,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -5),
                    child: IconButton(
                      key: const Key('sos-gesture-info-button'),
                      tooltip: 'How Manual and Duress SOS work',
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onShowGuide,
                      icon: const Icon(Icons.info_outline_rounded),
                      color: _SosColors.green,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the sos gesture explanation card.
class _SosGestureExplanationCard extends StatelessWidget {
  /// Creates sos gesture explanation card.
  const _SosGestureExplanationCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                      color: _SosColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SosColors.secondaryTextFor(context),
                      height: 1.4,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the sos demo result panel.
class _SosDemoResultPanel extends StatelessWidget {
  /// Creates sos demo result panel.
  const _SosDemoResultPanel({super.key, required this.result});

  final _SosGestureDemoResult result;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final (icon, color, title, message) = switch (result) {
      _SosGestureDemoResult.manual => (
        Icons.notifications_active_rounded,
        _SosColors.destructiveFor(context),
        'Manual SOS gesture',
        'A 10-second cancel screen would appear before the loud alert starts.',
      ),
      _SosGestureDemoResult.duress => (
        Icons.visibility_off_rounded,
        _SosColors.duress,
        'Duress SOS gesture',
        'A silent alert would be sent immediately without showing a countdown.',
      ),
      _SosGestureDemoResult.waiting => (
        Icons.touch_app_rounded,
        _SosColors.green,
        'Tap or hold the demo button',
        'The result will appear here. This demo never contacts anyone.',
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _SosColors.secondaryTextFor(context),
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the queued sos dispatch card.
class _QueuedSosDispatchCard extends StatelessWidget {
  /// Creates queued sos dispatch card.
  const _QueuedSosDispatchCard({required this.dispatch, required this.onTap});

  final SosQueuedDispatch dispatch;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: _TapSurface(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _Glyph(
                icon: dispatch.mode == SosAlertMode.duress
                    ? Icons.visibility_off_rounded
                    : Icons.outbox_rounded,
                color: dispatch.mode == SosAlertMode.duress
                    ? _SosColors.duress
                    : _SosColors.orange,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dispatch.mode.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _SosColors.textFor(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _queuedSosTimeLabel(dispatch.triggeredAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _SosColors.secondaryTextFor(context),
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${dispatch.pendingContactCount} contact dispatches waiting'
                      '${dispatch.retryCount == 0 ? '' : ' · ${dispatch.retryCount} retries'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _SosColors.orange,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                CupertinoIcons.chevron_forward,
                color: _SosColors.chevronFor(context),
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the queued sos empty state.
class _QueuedSosEmptyState extends StatelessWidget {
  /// Creates queued sos empty state.
  const _QueuedSosEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onRetry;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Glyph(icon: icon, color: _SosColors.green),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _SosColors.textFor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _SosColors.secondaryTextFor(context),
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

/// Displays the sos safety tool tile.
class _SosSafetyToolTile extends StatelessWidget {
  /// Creates sos safety tool tile.
  const _SosSafetyToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Glyph(icon: icon, color: _SosColors.green),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _SosColors.textFor(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _SosColors.secondaryTextFor(context),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the sos trigger log panel.
class _SosTriggerLogPanel extends StatelessWidget {
  /// Creates sos trigger log panel.
  const _SosTriggerLogPanel({
    required this.session,
    required this.latestResult,
    required this.customWhatsAppNotes,
    required this.onCustomWhatsAppNoteChanged,
  });

  final AppSession session;
  final SosAlertResult? latestResult;
  final Map<SosAlertMode, String> customWhatsAppNotes;
  final void Function(SosAlertMode mode, String note)
  onCustomWhatsAppNoteChanged;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel(label: 'SOS communication'),
        const SizedBox(height: 8),
        _DeliveryActionCard(
          icon: Icons.chat_bubble_rounded,
          title: 'WhatsApp notification',
          subtitle: 'Edit Manual, Duress, and Medical SOS notes.',
          trailing: 'Edit',
          onTap: () => unawaited(_openWhatsAppMessageEditor(context)),
        ),
      ],
    );
  }

  /// Opens whats app message editor.
  Future<void> _openWhatsAppMessageEditor(BuildContext context) async {
    final latestAlert = latestResult?.alert;
    final update = await Navigator.of(context).push<_WhatsAppNoteUpdate>(
      MaterialPageRoute<_WhatsAppNoteUpdate>(
        builder: (context) {
          return _WhatsAppMessageDetailPage(
            session: session,
            initialNotes: customWhatsAppNotes,
            previewMode: latestAlert?.mode ?? SosAlertMode.manual,
            previewTriggeredAt: latestAlert?.triggeredAt ?? DateTime.now(),
            previewLocation: latestAlert?.triggerLocation,
          );
        },
      ),
    );

    if (update != null && context.mounted) {
      onCustomWhatsAppNoteChanged(update.mode, update.note);
    }
  }
}

/// Displays the delivery action card.
class _DeliveryActionCard extends StatelessWidget {
  /// Creates delivery action card.
  const _DeliveryActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: _TapSurface(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            children: [
              _Glyph(icon: icon, color: _SosColors.green),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _SosColors.textFor(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _SosColors.secondaryTextFor(context),
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(
                label: trailing,
                color: _SosColors.green,
                surface: _SosColors.greenSoftFor(context),
              ),
              const SizedBox(width: 6),
              Icon(
                CupertinoIcons.chevron_forward,
                color: _SosColors.chevronFor(context),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the sos test row.
class _SosTestRow extends StatelessWidget {
  /// Creates sos test row.
  const _SosTestRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _TapSurface(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(icon: icon, color: _SosColors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _SosColors.textFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SosColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              color: _SosColors.chevronFor(context),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the sos detail header.
class _SosDetailHeader extends StatelessWidget {
  /// Creates sos detail header.
  const _SosDetailHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) =>
      PageHeader(title: title, subtitle: subtitle, onBack: onBack);
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
      padding: const EdgeInsets.fromLTRB(0, 11, 0, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _SosColors.textFor(context),
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _SosColors.secondaryTextFor(context),
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

/// Displays the status pill.
class _StatusPill extends StatelessWidget {
  /// Creates status pill.
  const _StatusPill({
    required this.label,
    required this.color,
    required this.surface,
  });

  final String label;
  final Color color;
  final Color surface;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
