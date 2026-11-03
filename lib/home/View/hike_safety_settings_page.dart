import 'package:flutter/material.dart';
import '../../core/widgets/page_header_style.dart';
import '../Model/hike_session_models.dart';
import '../Model/hike_safety_preferences.dart';
import 'hike_safety_settings_form.dart';
import 'hike_start_navigation.dart';

/// Keep safety choices on the stack so Back from preparation can edit them.
class HikeSafetySettingsPage extends StatefulWidget {
  /// Creates hike safety settings page.
  const HikeSafetySettingsPage({
    super.key,
    required this.initialDraft,
    required this.onContinue,
    this.loadDraft,
    this.onSave,
    this.onEditContacts,
    this.onDelete,
    this.onRemoved,
  });
  final HikeSessionDraft initialDraft;
  final Future<HikeSessionDraft> Function()? loadDraft;
  final Future<void> Function(HikeSessionDraft)? onSave;
  final Future<List<String>> Function()? onEditContacts;
  final Future<void> Function()? onDelete;
  final VoidCallback? onRemoved;
  final Future<String?> Function(HikeSessionDraft) onContinue;

  /// Creates the presentation state for this widget.
  @override
  State<HikeSafetySettingsPage> createState() => _HikeSafetySettingsPageState();
}

/// Manages the hike safety settings page presentation and lifecycle.
class _HikeSafetySettingsPageState extends State<HikeSafetySettingsPage> {
  late HikeSessionDraft _draft = HikeSafetyPreferences.normalized(
    widget.initialDraft,
  );
  bool _loading = false,
      _continuing = false,
      _editingContacts = false,
      _complete = false,
      _loadFailed = false;
  bool _deleting = false;
  String? _error;

  /// Returns busy.
  bool get _busy => _loading || _continuing || _editingContacts || _deleting;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads.
  Future<void> _load() async {
    final load = widget.loadDraft;
    if (load == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _loadFailed = false;
    });
    try {
      final draft = await load().timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(() => _draft = HikeSafetyPreferences.normalized(draft));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadFailed = true;
          _error =
              'Could not load your safety choices. Retry before continuing.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Computes edit contacts.
  Future<void> _editContacts() async {
    if (_busy || widget.onEditContacts == null) return;
    setState(() {
      _editingContacts = true;
      _error = null;
    });
    try {
      final names = await widget.onEditContacts!();
      if (mounted) {
        setState(() => _draft = _draft.copyWith(emergencyContactNames: names));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not refresh emergency contacts. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _editingContacts = false);
    }
  }

  /// Computes continue.
  Future<void> _continue() async {
    if (_busy || _loadFailed) return;
    final route = ModalRoute.of<String>(context);
    setState(() {
      _continuing = true;
      _error = null;
    });
    try {
      await widget.onSave?.call(_draft);
      if (!mounted || route?.isActive != true) return;
      final result = await widget.onContinue(_draft);
      if (mounted && result != null) {
        setState(() => _complete = true);
        _presentContinueEffect1(route, result);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save your safety choices. Your changes are kept; try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  /// Builds this widget from its current presentation state.
  Future<void> _delete() async {
    if (_busy || widget.onDelete == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this hike?'),
        content: Text(
          _draft.hikeType == HikeType.team
              ? 'This cancels the upcoming hike for everyone and moves it to Expired history. It will sync when connected.'
              : 'This removes the upcoming hike and moves it to Expired history. It will sync when connected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep hike'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove hike'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final route = ModalRoute.of<String>(context);
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.onDelete!();
      if (!mounted) return;
      setState(() => _complete = true);
      HikeStartNavigation.closeOwnedRoute(route, 'removed');
      widget.onRemoved?.call();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save the removal on this phone. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _complete || !_busy,
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLow,
        appBar: PageHeaderAppBar(
          title: const Text('Safety Settings'),
          actions: [
            if (widget.onDelete != null)
              IconButton(
                key: const ValueKey('delete-upcoming-hike'),
                tooltip: 'Remove upcoming hike',
                onPressed: _busy ? null : _delete,
                icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text(
                            _draft.trail.name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Review your safety tools before packing and checking conditions.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          AbsorbPointer(
                            absorbing: _busy,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: HikeSafetySettingsForm(
                                draft: _draft,
                                onChanged: (value) =>
                                    setState(() => _draft = value),
                                onEditContacts: widget.onEditContacts == null
                                    ? null
                                    : _editContacts,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Text(_error!, style: TextStyle(color: scheme.error)),
                      if (_loadFailed)
                        TextButton(
                          onPressed: _busy ? null : _load,
                          child: const Text('Retry'),
                        ),
                    ],
                    FilledButton.icon(
                      key: const ValueKey('safety-continue-to-preparation'),
                      onPressed: _busy || _loadFailed ? null : _continue,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward_rounded),
                      label: Text(
                        _continuing ? 'Saving…' : 'Continue to preparation',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Presents the continue effect1 UI.
  void _presentContinueEffect1(ModalRoute<String>? route, String result) =>
      HikeStartNavigation.closeOwnedRoute(route, result);
}
