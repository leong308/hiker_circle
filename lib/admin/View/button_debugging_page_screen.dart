part of '../button_debugging_page_feature.dart';

/// Keep the live capture session separate from saved diagnostic logs opened for review.
class ButtonDebuggingPage extends StatefulWidget {
  /// Creates button debugging page.
  const ButtonDebuggingPage({
    super.key,
    required this.session,
    this.controller,
  });
  final AppSession session;
  final ButtonDebugController? controller;

  /// Creates the presentation state for this widget.
  @override
  State<ButtonDebuggingPage> createState() => _ButtonDebuggingPageState();
}

/// Manages the button debugging page presentation and lifecycle.
class _ButtonDebuggingPageState extends State<ButtonDebuggingPage> {
  late final _ButtonDebuggingPageStateViewModel _screenModel;

  /// Returns debug.
  ButtonDebugController get _debug => _screenModel.stateDebug;

  /// Updates debug.
  set _debug(ButtonDebugController value) => _screenModel.stateDebug = value;

  /// Returns loading.
  bool get _loading => _screenModel.stateLoading;

  /// Returns command busy.
  bool get _commandBusy => _screenModel.stateCommandBusy;

  /// Returns buttons.
  List<PairedSosButton> get _buttons => _screenModel.stateButtons;

  /// Returns device id.
  String? get _deviceId => _screenModel.stateDeviceId;

  /// Updates device id.
  set _deviceId(String? value) => _screenModel.stateDeviceId = value;

  /// Returns message.
  String? get _message => _screenModel.stateMessage;

  /// Returns show history.
  bool get _showHistory => _screenModel.stateShowHistory;

  /// Updates show history.
  set _showHistory(bool value) => _screenModel.stateShowHistory = value;

  /// Returns direction.
  String get _direction => _screenModel.stateDirection;

  /// Updates direction.
  set _direction(String value) => _screenModel.stateDirection = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _ButtonDebuggingPageStateViewModel()
      ..addListener(_renderScreenModel);
    _screenModel.effectPresentOpenLogEffect1 = _presentOpenLogEffect1;

    _debug =
        widget.controller ??
        ButtonDebugController(
          owner: widget.session.phoneNumber,
          database: LocalSessionDatabase(),
        );
    if (widget.session.isAdmin) unawaited(_initialize());
  }

  /// Delegates initialize to the ViewModel.
  Future<void> _initialize() => _screenModel.commandInitialize();

  /// Delegates stop to the ViewModel.
  Future<void> _stop(String reason) => _screenModel.commandStop(reason);

  /// Delegates start to the ViewModel.
  Future<void> _start() => _screenModel.commandStart();

  /// Delegates open log to the ViewModel.
  Future<void> _openLog(Map<String, Object?> session) =>
      _screenModel.commandOpenLog(session);

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    unawaited(_stop('page_left'));
    _debug.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates arm test to the ViewModel.
  Future<void> _armTest() => _screenModel.commandArmTest();

  /// Delegates read device log to the ViewModel.
  Future<void> _readDeviceLog() => _screenModel.commandReadDeviceLog();

  /// Delegates session date to the ViewModel.
  String _sessionDate(Object? value) => _screenModel.commandSessionDate(value);

  /// Captures panel.
  Widget _capturePanel(BuildContext context) {
    final enabled = _debug.recording && !_commandBusy && _deviceId != null;
    return AdminPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AdminTag(
                      label: _debug.busy
                          ? 'Preparing / saving'
                          : _debug.recording
                          ? 'Recording'
                          : 'Ready to capture',
                      icon: _debug.recording
                          ? Icons.fiber_manual_record
                          : Icons.sensors_rounded,
                    ),
                    AdminTag(
                      label: 'Stored on this phone',
                      color: AdminUi.muted(context),
                      icon: Icons.phone_iphone_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_debug.entryCount}',
                      style: TextStyle(
                        fontSize: 34,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: AdminUi.green(context),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'captured entries',
                        style: TextStyle(
                          color: AdminUi.muted(context),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.graphic_eq_rounded,
                      size: 32,
                      color: AdminUi.green(context).withValues(alpha: .5),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _debug.recording
                      ? 'Capturing button traffic. Use Arm safe test before a test press.'
                      : 'Start a session to inspect button messages and their decoded values.',
                  style: TextStyle(
                    color: AdminUi.muted(context),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AdminUi.border(context)),
          ExpansionTile(
            key: const PageStorageKey('debug-device-commands'),
            initiallyExpanded: false,
            leading: Icon(
              Icons.bluetooth_rounded,
              color: AdminUi.blue(context),
            ),
            title: const Text(
              'Device commands',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _buttons.isEmpty
                  ? 'No paired button · passive capture available'
                  : '${_buttons.length} paired button${_buttons.length == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 12, color: AdminUi.muted(context)),
            ),
            shape: const Border(),
            collapsedShape: const Border(),
            childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_buttons.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _deviceId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Paired button',
                    border: OutlineInputBorder(),
                  ),
                  items: _buttons
                      .map(
                        (b) => DropdownMenuItem(
                          value: b.deviceId,
                          child: Text(
                            '${b.displayName} · ${b.deviceId}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _commandBusy
                      ? null
                      : (id) => setState(() => _deviceId = id),
                )
              else
                Text(
                  'Pair a button in SOS button settings to use these commands.',
                  style: TextStyle(color: AdminUi.muted(context), fontSize: 13),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: enabled ? _armTest : null,
                    icon: const Icon(Icons.touch_app_outlined, size: 18),
                    label: const Text('Arm safe test (30s)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: enabled ? _readDeviceLog : null,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Read device log'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Start recording before sending commands. Pairing keys are redacted from captured payloads.',
                style: TextStyle(
                  color: AdminUi.muted(context),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Computes session row.
  Widget _sessionRow(Map<String, Object?> session) => AdminPanel(
    key: ValueKey('debug-session-${session['id']}'),
    onTap: () => _openLog(session),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AdminUi.blue(context).withValues(alpha: .08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.description_outlined,
            color: AdminUi.blue(context),
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _sessionDate(session['started_at']),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${session['end_reason'] ?? session['status']}'.replaceAll(
                  '_',
                  ' ',
                ),
                style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          Icons.chevron_right_rounded,
          color: AdminUi.muted(context),
          size: 20,
        ),
      ],
    ),
  );

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (!widget.session.isAdmin) {
      return Scaffold(
        appBar: PageHeaderAppBar(title: const Text('Button Debugging')),
        body: const Center(child: Text('Administrator access required.')),
      );
    }
    return ListenableBuilder(
      listenable: _debug,
      builder: (context, _) {
        final entries = _debug.liveEntries.reversed
            .where(
              (row) => _direction == 'All' || row['direction'] == _direction,
            )
            .toList();
        final saved = _debug.sessions
            .where((s) => s['status'] != 'recording')
            .toList();
        return Scaffold(
          backgroundColor: AdminUi.background(context),
          bottomNavigationBar: _loading
              ? null
              : Material(
                  color: AdminUi.surface(context),
                  child: SafeArea(
                    top: false,
                    child: Center(
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 960),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed:
                                    _debug.busy ||
                                        (!_debug.recording && _commandBusy)
                                    ? null
                                    : _debug.recording
                                    ? () => _stop('manual_stop')
                                    : _start,
                                icon: Icon(
                                  _debug.recording
                                      ? Icons.stop_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                label: Text(
                                  _debug.busy
                                      ? 'Saving / preparing…'
                                      : _debug.recording
                                      ? 'Stop and save session'
                                      : 'Start debug session',
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                'Closing this page stops capture and saves your log.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AdminUi.muted(context),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          body: SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  AdminHeading(
                                    title: 'Button Debugging',
                                    subtitle:
                                        'Capture, inspect and understand device activity.',
                                    onBack: () => Navigator.of(context).pop(),
                                  ),
                                  const SizedBox(height: 22),
                                  _capturePanel(context),
                                  if (_message != null ||
                                      _debug.error != null) ...[
                                    const SizedBox(height: 12),
                                    AdminPanel(
                                      child: Text(
                                        _debug.error ?? _message!,
                                        style: TextStyle(
                                          color: _debug.error == null
                                              ? AdminUi.green(context)
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 22),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _viewTab(
                                          'Live capture',
                                          Icons.sensors_rounded,
                                          !_showHistory,
                                          () => setState(
                                            () => _showHistory = false,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _viewTab(
                                          'Saved sessions',
                                          Icons.history_rounded,
                                          _showHistory,
                                          () => setState(
                                            () => _showHistory = true,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  if (_showHistory)
                                    AdminSectionHeading(
                                      title: 'Session history',
                                      subtitle:
                                          '${saved.length} saved · this account, this phone',
                                    )
                                  else ...[
                                    AdminSectionHeading(
                                      title: 'Packet stream',
                                      subtitle:
                                          'Newest first · latest 300 shown · all entries saved',
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 7,
                                      runSpacing: 6,
                                      children: [
                                        for (final direction in [
                                          'All',
                                          'RX',
                                          'TX',
                                          'LOCAL',
                                        ])
                                          ChoiceChip(
                                            key: ValueKey(
                                              'debug-filter-$direction',
                                            ),
                                            label: Text(
                                              direction == 'LOCAL'
                                                  ? 'Local'
                                                  : direction,
                                            ),
                                            selected: _direction == direction,
                                            showCheckmark: false,
                                            onSelected: (_) => setState(
                                              () => _direction = direction,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                            sliver: _showHistory
                                ? saved.isEmpty
                                      ? const SliverToBoxAdapter(
                                          child: AdminEmptyState(
                                            title: 'No saved sessions yet',
                                            message:
                                                'Stop a capture to save it here. Sessions stay available offline.',
                                            icon: Icons.history_rounded,
                                          ),
                                        )
                                      : SliverList.separated(
                                          itemCount: saved.length,
                                          separatorBuilder: (_, _) =>
                                              const SizedBox(height: 10),
                                          itemBuilder: (_, i) =>
                                              _sessionRow(saved[i]),
                                        )
                                : entries.isEmpty
                                ? SliverToBoxAdapter(
                                    child: AdminEmptyState(
                                      title: _debug.liveEntries.isNotEmpty
                                          ? 'No matching entries'
                                          : _debug.recording
                                          ? 'Listening for BLE traffic…'
                                          : 'Your next capture starts here',
                                      message: _debug.liveEntries.isNotEmpty
                                          ? 'Choose another direction to inspect captured traffic.'
                                          : 'HEX bytes and their meanings will appear together as messages arrive.',
                                      icon: Icons.graphic_eq_rounded,
                                    ),
                                  )
                                : SliverList.separated(
                                    itemCount: entries.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 14),
                                    itemBuilder: (_, i) => ButtonDebugEntryCard(
                                      key: ValueKey(
                                        '${entries[i]['session_id']}-${entries[i]['sequence']}',
                                      ),
                                      row: entries[i],
                                    ),
                                  ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Computes view tab.
  Widget _viewTab(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) => Material(
    color: selected
        ? AdminUi.green(context).withValues(alpha: .1)
        : AdminUi.surface(context),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: selected
            ? AdminUi.green(context).withValues(alpha: .3)
            : AdminUi.border(context),
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? AdminUi.green(context) : AdminUi.muted(context),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? AdminUi.green(context)
                    : AdminUi.muted(context),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// Presents the open log effect1 UI.
  Future<void> _presentOpenLogEffect1(
    List<Map<String, Object?>> entries,
    String text,
    Map<String, Object?> session,
  ) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (logContext) => _SavedDebugLog(
        entries: entries,
        fallbackText: text,
        startedAt: _sessionDate(session['started_at']),
        conclusion: '${session['end_reason'] ?? session['status']}'.replaceAll(
          '_',
          ' ',
        ),
        onExport: () async {
          try {
            final savedPath = await FilePicker.saveFile(
              dialogTitle: 'Save button debug log',
              fileName: 'button_debug_${session['id']}.log',
              bytes: Uint8List.fromList(utf8.encode(text)),
            );
            if (savedPath != null && logContext.mounted) {
              ScaffoldMessenger.of(
                logContext,
              ).showSnackBar(const SnackBar(content: Text('Debug log saved.')));
            }
          } catch (e) {
            if (logContext.mounted) {
              ScaffoldMessenger.of(
                logContext,
              ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
            }
          }
        },
      ),
    ),
  );
}

/// Displays the saved debug log.
class _SavedDebugLog extends StatelessWidget {
  /// Creates saved debug log.
  const _SavedDebugLog({
    required this.entries,
    required this.fallbackText,
    required this.startedAt,
    required this.conclusion,
    required this.onExport,
  });
  final List<Map<String, Object?>> entries;
  final String fallbackText, startedAt, conclusion;
  final VoidCallback onExport;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AdminUi.background(context),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AdminHeading(
                        title: 'Button debug log',
                        subtitle: 'Saved session · available offline',
                        onBack: () => Navigator.of(context).pop(),
                        action: IconButton(
                          tooltip: 'Save log file',
                          onPressed: onExport,
                          icon: Icon(
                            Icons.ios_share_rounded,
                            color: AdminUi.green(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      AdminPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              startedAt,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                AdminTag(
                                  label: '${entries.length} entries',
                                  icon: Icons.layers_outlined,
                                ),
                                AdminTag(
                                  label: conclusion,
                                  color: AdminUi.muted(context),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Times shown in local time. Pairing keys remain redacted.',
                              style: TextStyle(
                                color: AdminUi.muted(context),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const AdminSectionHeading(
                        title: 'Recorded activity',
                        subtitle: 'In capture order · full payloads retained',
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                sliver: entries.isEmpty
                    ? SliverToBoxAdapter(
                        child: AdminPanel(child: SelectableText(fallbackText)),
                      )
                    : SliverList.separated(
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (_, i) =>
                            ButtonDebugEntryCard(row: entries[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
