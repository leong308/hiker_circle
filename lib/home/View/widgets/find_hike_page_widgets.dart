part of '../../find_hike_page_feature.dart';

/// Displays the upcoming hike card.
class UpcomingHikeCard extends StatefulWidget {
  /// Creates upcoming hike card.
  const UpcomingHikeCard({
    super.key,
    required this.hike,
    this.userLat,
    this.userLng,
    required this.session,
    required this.repository,
    required this.onJoin,
  });

  final UpcomingHike hike;
  final double? userLat;
  final double? userLng;
  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final VoidCallback onJoin;

  /// Creates the presentation state for this widget.
  @override
  State<UpcomingHikeCard> createState() => _UpcomingHikeCardState();
}

/// Manages the upcoming hike card presentation and lifecycle.
class _UpcomingHikeCardState extends State<UpcomingHikeCard>
    with SingleTickerProviderStateMixin {
  late final _UpcomingHikeCardStateViewModel _screenModel;

  /// Updates joined locally.
  set _joinedLocally(bool value) => _screenModel.stateJoinedLocally = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  bool _joining = false;

  bool _remindingHost = false;
  late int _departureReminderCount = widget.hike.departureReminderCount;
  late bool _departureReminderSentByMe = widget.hike.departureReminderSentByMe;
  late String _joinRequestStatus = widget.hike.joinRequestStatus;
  DateTime _clock = DateTime.now();
  Timer? _clockTimer;
  late final AnimationController _wiggleController;
  bool _reduceMotion = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _UpcomingHikeCardStateViewModel(
      readHike: () => widget.hike,
      readSession: () => widget.session,
      effectShowError: _showError,
    )..addListener(_renderScreenModel);

    _wiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _syncUrgentAnimation(_clock);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final previousClock = _clock;
      final phaseChanged = _urgencyPhase(now) != _urgencyPhase(previousClock);
      _clock = now;
      _syncUrgentAnimation(now);
      if (phaseChanged || now.minute != previousClock.minute) setState(() {});
      if (now.isAfter(
        widget.hike.departureTime.add(const Duration(minutes: 15)),
      )) {
        widget.onJoin();
      }
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _clockTimer?.cancel();
    _wiggleController.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Refreshes presentation dependencies.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    _syncUrgentAnimation(_clock);
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant UpcomingHikeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hike.id != widget.hike.id ||
        oldWidget.hike.joinRequestStatus != widget.hike.joinRequestStatus) {
      _joinRequestStatus = widget.hike.joinRequestStatus;
      _departureReminderCount = widget.hike.departureReminderCount;
      _departureReminderSentByMe = widget.hike.departureReminderSentByMe;
    }
    if (oldWidget.hike.departureTime != widget.hike.departureTime) {
      _syncUrgentAnimation(_clock);
    }
  }

  /// Delegates urgency phase to the ViewModel.
  int _urgencyPhase(DateTime now) => _screenModel.commandUrgencyPhase(now);

  /// Synchronizes urgent animation.
  void _syncUrgentAnimation(DateTime now) {
    final phase = _urgencyPhase(now);
    final shouldAnimate = !_reduceMotion && (phase == 1 || phase == 2);
    if (shouldAnimate) {
      if (!_wiggleController.isAnimating) _wiggleController.repeat();
    } else if (_wiggleController.isAnimating || _wiggleController.value != 0) {
      _wiggleController
        ..stop()
        ..reset();
    }
  }

  /// Returns is participating.
  bool get _isParticipating => _screenModel.commandIsParticipating;

  /// Delegates open directions to the ViewModel.
  Future<void> _openDirections() => _screenModel.commandOpenDirections();

  /// Computes join.
  Future<void> _join() async {
    if (_joining) return;
    setState(() => _joining = true);
    try {
      if (widget.hike.hikeType != 'team' || widget.hike.requiresJoinApproval) {
        final status =
            await _FindHikePageWidgetsDataActions.requestToJoinUpcomingHike(
              widget.repository,
            )(hikeId: widget.hike.id);
        if (!mounted) return;
        setState(() => _joinRequestStatus = status);
        widget.onJoin();
        switch (status) {
          case 'pending':
            _showMessage(
              'Request sent. The host has been notified by app and WhatsApp.',
            );
            break;
          case 'accepted':
            setState(() => _joinedLocally = true);
            _showMessage('Your request was already accepted.');
            break;
          case 'rejected':
            _showError('The host declined this join request.');
            break;
          default:
            _showError('This join request is no longer available.');
            break;
        }
        return;
      }
      final ok = await _FindHikePageWidgetsDataActions.joinUpcomingHike(
        widget.repository,
      )(hikeId: widget.hike.id);
      if (!mounted) return;
      if (ok) {
        setState(() => _joinedLocally = true);
        await _editReminders(showJoinedConfirmation: true);
        widget.onJoin();
      } else {
        _showError('Unable to join this hike.');
      }
    } on HikerCircleFirebaseRepositoryException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Unable to join this hike right now.');
    } finally {
      if (mounted) {
        setState(() => _joining = false);
      }
    }
  }

  /// Computes edit reminders.
  Future<void> _editReminders({bool showJoinedConfirmation = false}) async {
    HikeReminderPreference initial = const HikeReminderPreference();
    try {
      initial =
          await _FindHikePageWidgetsDataActions.loadUpcomingHikeReminderPreference(
            widget.repository,
          )(session: widget.session, hikeId: widget.hike.id);
    } catch (_) {
      // A newly joined hike may take a moment to become readable locally.
      // The safe defaults still let the user configure and save immediately.
    }
    if (!mounted) return;
    final preference = await showHikeReminderPreferencesSheet(
      context,
      hikeName: widget.hike.trailName,
      departureTime: widget.hike.departureTime,
      initialPreference: initial,
    );
    if (!mounted) return;
    if (preference == null) {
      if (showJoinedConfirmation) {
        _showMessage('Hike joined. You can set reminders from this card.');
      }
      return;
    }
    try {
      await _FindHikePageWidgetsDataActions.saveUpcomingHikeReminderPreference(
        widget.repository,
      )(
        session: widget.session,
        hikeId: widget.hike.id,
        preference: preference,
        hike: widget.hike,
      );
      _showMessage(
        preference.enabled
            ? 'Your reminders for this hike are saved.'
            : 'Reminders are off for this hike.',
      );
    } catch (_) {
      _showError(
        'The hike was joined, but reminder settings could not be saved. Try again from this card.',
      );
    }
  }

  /// Computes remind host.
  Future<void> _remindHost() async {
    if (_remindingHost || _departureReminderSentByMe) return;
    if (_departureReminderCount >= 3) {
      _showMessage(
        'A few reminders were already sent to the host.',
        tone: HikerCircleToastTone.warning,
      );
      return;
    }
    setState(() => _remindingHost = true);
    try {
      final result =
          await _FindHikePageWidgetsDataActions.remindUpcomingHikeHost(
            widget.repository,
          )(hikeId: widget.hike.id);
      if (!mounted) return;
      final count =
          (result['reminderCount'] as num?)?.toInt() ?? _departureReminderCount;
      setState(() {
        _departureReminderCount = count;
        _departureReminderSentByMe = true;
      });
      _showMessage(
        result['alreadySent'] == true || count >= 3
            ? 'A few reminders were already sent to the host.'
            : 'The host was reminded through HikerCircle and WhatsApp.',
        tone: result['alreadySent'] == true || count >= 3
            ? HikerCircleToastTone.warning
            : HikerCircleToastTone.success,
      );
    } on HikerCircleFirebaseRepositoryException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _remindingHost = false);
    }
  }

  /// Shows error.
  void _showError(String message) {
    if (!mounted) return;
    HikerCircleToast.show(context, message, tone: HikerCircleToastTone.error);
  }

  /// Shows message.
  void _showMessage(
    String message, {
    HikerCircleToastTone tone = HikerCircleToastTone.success,
  }) {
    if (!mounted) return;
    HikerCircleToast.show(context, message, tone: tone);
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final distKm = widget.userLat != null && widget.userLng != null
        ? widget.hike.distanceFrom(widget.userLat!, widget.userLng!)
        : widget.hike.distanceKm;
    final distText = distKm < 1
        ? '${(distKm * 1000).toStringAsFixed(0)} m'
        : '${distKm.toStringAsFixed(1)} km';

    final departureTime = widget.hike.departureTime.toLocal();
    final dateText =
        '${departureTime.day}/${departureTime.month}/${departureTime.year}';
    final timeText =
        '${departureTime.hour.toString().padLeft(2, '0')}:${departureTime.minute.toString().padLeft(2, '0')}';

    final participating = _isParticipating;
    final isCreator = widget.session.phoneNumber == widget.hike.creatorPhone;
    final untilDeparture = widget.hike.departureTime.difference(_clock);
    final isApproaching =
        !untilDeparture.isNegative &&
        untilDeparture <= const Duration(minutes: 15);
    final isOverdue =
        untilDeparture.isNegative &&
        untilDeparture > const Duration(minutes: -15);
    final isUrgent = isApproaching || isOverdue;
    final cardBody = _InsetGroup(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isOverdue
              ? Theme.of(context).colorScheme.error.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.18
                      : 0.09,
                )
              : Colors.transparent,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Glyph(icon: Icons.hiking_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.hike.trailName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: _AppColors.textFor(context),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                                widget.hike.area,
                                widget.hike.state,
                                widget.hike.country,
                              ]
                              .map((part) => part.trim())
                              .where((part) => part.isNotEmpty)
                              .join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _AppColors.secondaryTextFor(context),
                                letterSpacing: 0,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(
                    label: widget.hike.hikeType == 'team' ? 'Group' : 'Solo',
                    color: widget.hike.hikeType == 'team'
                        ? _AppColors.green
                        : _AppColors.secondaryTextFor(context),
                  ),
                  if (isUrgent) ...[
                    const SizedBox(width: 7),
                    _VibratingHikeBell(
                      animation: _wiggleController,
                      color: isOverdue
                          ? Theme.of(context).colorScheme.error
                          : _AppColors.orange,
                    ),
                  ],
                ],
              ),
              if (isOverdue) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Text(
                    'EXPIRING SOON · This hike disappears 15 minutes after departure',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const _HorizontalSeparator(),
              const SizedBox(height: 10),
              _infoRow(
                context,
                Icons.directions_walk_rounded,
                'Start',
                widget.hike.startPointName,
              ),
              const SizedBox(height: 4),
              _infoRow(
                context,
                Icons.flag_rounded,
                'Destination',
                widget.hike.destinationName,
              ),
              const SizedBox(height: 4),
              _infoRow(
                context,
                Icons.person_rounded,
                'Host',
                widget.hike.creatorName.isNotEmpty
                    ? widget.hike.creatorName
                    : 'Hike host',
              ),
              const SizedBox(height: 10),
              const _HorizontalSeparator(),
              const SizedBox(height: 10),
              Row(
                children: [
                  _chip(context, Icons.schedule_rounded, '$dateText $timeText'),
                  const SizedBox(width: 8),
                  _chip(context, Icons.straighten_rounded, distText),
                  const SizedBox(width: 8),
                  _chip(
                    context,
                    Icons.people_rounded,
                    '${widget.hike.participantCount}',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.timeline_rounded,
                    size: 13,
                    color: _AppColors.secondaryTextFor(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.hike.distanceKm.toStringAsFixed(1)} km \u00b7 ${widget.hike.durationMinutes} min \u00b7 ${widget.hike.difficulty}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _AppColors.secondaryTextFor(context),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Material(
                color: _AppColors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _openDirections,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Get a route to this hike',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: _AppColors.green,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                        ),
                        const Icon(
                          Icons.navigation_rounded,
                          size: 19,
                          color: _AppColors.green,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (participating) ...[
                const SizedBox(height: 10),
                const _HorizontalSeparator(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      isCreator
                          ? Icons.star_rounded
                          : Icons.check_circle_rounded,
                      size: 16,
                      color: isCreator ? _AppColors.orange : _AppColors.green,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isCreator ? 'Created by you' : 'You joined this hike',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isCreator ? _AppColors.orange : _AppColors.green,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _editReminders,
                      icon: const Icon(Icons.notifications_outlined, size: 17),
                      label: const Text('Reminders'),
                    ),
                  ],
                ),
                if (!isCreator && isUrgent) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          _remindingHost ||
                              _departureReminderSentByMe ||
                              _departureReminderCount >= 3
                          ? (_departureReminderCount >= 3 &&
                                    !_departureReminderSentByMe
                                ? () => _showMessage(
                                    'A few reminders were already sent to the host.',
                                    tone: HikerCircleToastTone.warning,
                                  )
                                : null)
                          : _remindHost,
                      icon: _remindingHost
                          ? const Icon(Icons.hourglass_top_rounded)
                          : const Icon(Icons.notification_important_rounded),
                      label: Text(
                        _departureReminderSentByMe ||
                                _departureReminderCount >= 3
                            ? 'Reminders sent'
                            : 'Remind host',
                      ),
                    ),
                  ),
                ],
              ] else ...[
                const SizedBox(height: 12),
                const _HorizontalSeparator(),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _joining ||
                            ((widget.hike.hikeType != 'team' ||
                                    widget.hike.requiresJoinApproval) &&
                                _joinRequestStatus.isNotEmpty)
                        ? null
                        : _join,
                    icon: Icon(
                      widget.hike.hikeType == 'team' &&
                              !widget.hike.requiresJoinApproval
                          ? Icons.person_add_rounded
                          : _joinRequestStatus == 'pending'
                          ? Icons.hourglass_top_rounded
                          : _joinRequestStatus == 'accepted'
                          ? Icons.check_circle_rounded
                          : _joinRequestStatus == 'rejected'
                          ? Icons.block_rounded
                          : Icons.how_to_reg_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _joining
                          ? widget.hike.hikeType == 'team' &&
                                    !widget.hike.requiresJoinApproval
                                ? 'Joining...'
                                : 'Sending request...'
                          : widget.hike.hikeType == 'team' &&
                                !widget.hike.requiresJoinApproval
                          ? 'Join Group Hike'
                          : switch (_joinRequestStatus) {
                              'pending' => 'Request pending',
                              'accepted' => 'Request accepted',
                              'rejected' => 'Request declined',
                              'expired' => 'Request expired',
                              _ => 'Request to join',
                            },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    final card = Stack(
      children: [
        cardBody,
        if (_joining)
          HikerCircleLoadingToastOverlay(
            compact: true,
            message:
                widget.hike.hikeType == 'team' &&
                    !widget.hike.requiresJoinApproval
                ? 'Joining group hike…'
                : 'Sending join request…',
            detail: 'Confirming the hike and updating the participant list.',
            timeout: const Duration(seconds: 30),
            onTimeout: () {
              if (mounted) {
                setState(() => _joining = false);
                _showError('The join request timed out. Please try again.');
              }
            },
          ),
        if (_remindingHost)
          HikerCircleLoadingToastOverlay(
            compact: true,
            message: 'Sending reminder…',
            detail: 'Notifying the host about your arrival.',
            timeout: const Duration(seconds: 30),
            onTimeout: () {
              if (mounted) {
                setState(() => _remindingHost = false);
                _showError('The reminder timed out. Please try again.');
              }
            },
          ),
      ],
    );
    if (!isUrgent || _reduceMotion) return card;

    return AnimatedBuilder(
      animation: _wiggleController,
      child: card,
      builder: (context, child) {
        final wave = math.sin(_wiggleController.value * math.pi * 2);
        return Transform.translate(
          key: const ValueKey('upcoming-hike-urgent-wiggle'),
          offset: Offset(wave * 1.8, 0),
          child: Transform.rotate(angle: wave * 0.006, child: child),
        );
      },
    );
  }

  /// Computes info row.
  Widget _infoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _AppColors.secondaryTextFor(context)),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _AppColors.secondaryTextFor(context),
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _AppColors.textFor(context),
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Computes chip.
  Widget _chip(BuildContext context, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _AppColors.chipBackgroundFor(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _AppColors.secondaryTextFor(context)),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _AppColors.textFor(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the detail header.
class _DetailHeader extends StatelessWidget {
  /// Creates detail header.
  const _DetailHeader({
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
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
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _AppColors.secondaryTextFor(context),
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}
