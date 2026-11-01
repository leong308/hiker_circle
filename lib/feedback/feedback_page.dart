// FeedbackPage provides feedback capture, composition, inbox and submission detail screens.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';

import '../core/widgets/loading_toast.dart';
import 'feedback_repository.dart';
import 'View/feedback_inbox_page.dart';
export 'View/feedback_inbox_page.dart' show FeedbackInboxPage;

/// Displays the feedback page.
class FeedbackPage extends StatelessWidget {
  /// Creates feedback page.
  const FeedbackPage({super.key, this.isAdmin = false, this.repository});
  final bool isAdmin;
  final FeedbackRepository? repository;

  /// Captures.
  void _capture(BuildContext context) {
    final navigator = Navigator.of(context);
    final feedback = BetterFeedback.of(context);
    navigator.pop();
    var previewOpened = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!navigator.mounted) return;
      feedback.show((result) {
        if (!navigator.mounted || !feedback.isVisible || previewOpened) return;
        previewOpened = true;
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => FeedbackComposePage(
                initialText: result.text,
                screenshot: result.screenshot,
                repository: repository,
              ),
            ),
          ),
        );
      });
    });
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Scaffold(
      appBar: PageHeaderAppBar(
        title: const Text('Feedback'),
        actions: [
          if (isAdmin)
            PageHeaderAction(
              tooltip: 'Feedback inbox',
              icon: Icons.inbox_outlined,
              color: colors.primary,
              surface: colors.surface,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      FeedbackInboxPage(admin: true, repository: repository),
                ),
              ),
            ),
          PageHeaderAction(
            tooltip: 'My feedback',
            icon: Icons.history_rounded,
            color: colors.primary,
            surface: colors.surface,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FeedbackInboxPage(repository: repository),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, progress, child) => Opacity(
              opacity: progress,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - progress)),
                child: child,
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.forum_outlined,
                    size: 36,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Ideas & issues',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Help make your next hike better.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _FeedbackChoiceCard(
            title: 'Write feedback',
            subtitle: 'Report a problem or share an idea.',
            icon: Icons.edit_outlined,
            prominent: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FeedbackComposePage(repository: repository),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _FeedbackChoiceCard(
            title: 'Mark a screenshot',
            subtitle: 'Show us what needs fixing.',
            icon: Icons.draw_outlined,
            onTap: () => _capture(context),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            icon: const Icon(Icons.lock_outline_rounded, size: 17),
            label: const Text('Private feedback · Not for emergencies'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (context) => SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Privacy & capture tips',
                        style: PageHeaderStyle.title(context, colors.onSurface),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Only you and HikerCircle admins can view your report. It includes your account ID and platform, not passwords, location or background recordings.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Navigate to the screen, then Draw to mark it. Review or remove the screenshot before sending. Maps and native views may be missing from captures.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Remove sensitive details from screenshots. Use SOS for emergencies.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the feedback choice card.
class _FeedbackChoiceCard extends StatefulWidget {
  /// Creates feedback choice card.
  const _FeedbackChoiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.prominent = false,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool prominent;

  /// Creates the presentation state for this widget.
  @override
  State<_FeedbackChoiceCard> createState() => _FeedbackChoiceCardState();
}

/// Manages the feedback choice card presentation and lifecycle.
class _FeedbackChoiceCardState extends State<_FeedbackChoiceCard> {
  bool pressed = false;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final ink = widget.prominent ? colors.onPrimaryContainer : colors.onSurface;
    return AnimatedScale(
      scale: pressed ? .98 : 1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 140),
      child: Material(
        color: widget.prominent
            ? colors.primaryContainer
            : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: widget.prominent
                ? Colors.transparent
                : colors.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => pressed = true),
          onTapUp: (_) => setState(() => pressed = false),
          onTapCancel: () => setState(() => pressed = false),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 26,
                  color: widget.prominent ? ink : colors.primary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ink.withValues(alpha: .8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.chevron_right_rounded, color: ink, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Review the screenshot and message together before submitting the stable FeedbackDraft.
class FeedbackComposePage extends StatefulWidget {
  /// Creates feedback compose page.
  const FeedbackComposePage({
    super.key,
    this.initialText = '',
    this.screenshot,
    this.repository,
  });
  final String initialText;
  final Uint8List? screenshot;
  final FeedbackRepository? repository;

  /// Creates the presentation state for this widget.
  @override
  State<FeedbackComposePage> createState() => _FeedbackComposePageState();
}

/// Manages the feedback compose page presentation and lifecycle.
class _FeedbackComposePageState extends State<FeedbackComposePage>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  late final _repository = widget.repository ?? FeedbackRepository();
  late final _message = TextEditingController(text: widget.initialText);
  late Uint8List? _screenshot = widget.screenshot;
  String _category = feedbackCategories.first;
  FeedbackDraft? _draft;
  FeedbackSavedDraft? _savedDraft;
  String? _draftOwner;
  Future<void> _saveChain = Future.value();
  Timer? _saveTimer;
  int _editRevision = 0;
  bool _restoring = true;
  bool _restored = false;
  bool _localSaved = false;
  bool _allowPop = false;
  bool _leaving = false;
  bool _disposed = false;
  bool _incomingCapturePending = false;
  String? _saveError;
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _message.addListener(_draftChanged);
    unawaited(_restoreSavedDraft());
  }

  Future<void> _restoreSavedDraft() async {
    try {
      _draftOwner ??= await _repository.draftOwner();
      final existing = await _repository.loadSavedDraft(
        expectedOwner: _draftOwner,
      );
      var replacedEmptyDraft = false;
      if (existing != null &&
          !existing.hasContent &&
          !existing.submissionAttempted &&
          (widget.initialText.isNotEmpty || widget.screenshot != null)) {
        if (!await _repository.discardSavedDraft(existing)) {
          throw StateError('The device draft changed while opening a capture.');
        }
        replacedEmptyDraft = true;
      }
      final saved = await _repository.openSavedDraft(
        expectedOwner: _draftOwner,
        message: widget.initialText,
        screenshot: (widget.screenshot?.length ?? 0) <= feedbackImageLimit
            ? widget.screenshot
            : null,
      );
      if (!mounted || _disposed) return;
      _savedDraft = saved;
      _message.text = saved.message;
      _category = saved.category;
      _screenshot = saved.screenshot == null
          ? null
          : Uint8List.fromList(saved.screenshot!);
      _draft = saved.submissionAttempted
          ? _repository.submissionForSavedDraft(saved)
          : null;
      _restored = existing?.hasContent == true;
      _incomingCapturePending =
          _restored &&
          (widget.initialText.isNotEmpty || widget.screenshot != null);
      if ((existing == null || replacedEmptyDraft) &&
          (widget.screenshot?.length ?? 0) > feedbackImageLimit) {
        _screenshot = widget.screenshot;
        _saveError =
            'This screenshot is too large to save. Remove it to continue.';
      }
      if (_draft != null) {
        _error =
            'Your previous send was not confirmed here. Retry delivery to check the same report.';
      }
      setState(() {
        _restoring = false;
        _localSaved = _saveError == null;
      });
    } catch (_) {
      if (!mounted || _disposed) return;
      setState(() {
        _restoring = false;
        _saveError =
            'Could not open your saved feedback on this device. Please try again.';
      });
    }
  }

  void _draftChanged() {
    if (_disposed || _restoring || _busy || _sent || _draft != null) return;
    _editRevision++;
    _saveTimer?.cancel();
    setState(() {
      _localSaved = false;
      _saveError = null;
    });
    _saveTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_persistCurrent());
    });
  }

  Future<bool> _persistCurrent({bool freezeForSubmission = false}) {
    final message = freezeForSubmission ? _message.text.trim() : _message.text;
    final category = _category;
    final screenshot = _screenshot;
    final revision = _editRevision;
    final done = Completer<bool>();
    _saveChain = _saveChain.then((_) async {
      try {
        final base = _savedDraft;
        if (base == null) throw StateError('No device draft is open.');
        if (base.submissionAttempted && !freezeForSubmission) {
          // A lifecycle save queued before Send must not change its frozen payload.
          done.complete(true);
          return;
        }
        final saved = await _repository.saveSavedDraft(
          base.copyWith(
            category: category,
            message: message,
            screenshot: screenshot,
            removeScreenshot: screenshot == null,
            submissionAttempted:
                freezeForSubmission || base.submissionAttempted,
          ),
        );
        if (saved == null) throw StateError('The device draft changed.');
        _savedDraft = saved;
        if (mounted && !_disposed && revision == _editRevision) {
          setState(() {
            _localSaved = true;
            _saveError = null;
          });
        }
        done.complete(true);
      } catch (_) {
        if (mounted && !_disposed) {
          setState(() {
            _localSaved = false;
            _saveError = (screenshot?.length ?? 0) > feedbackImageLimit
                ? 'This screenshot is too large to save. Remove it to continue.'
                : 'Could not save your draft on this device. Please try saving again before leaving.';
          });
        }
        done.complete(false);
      }
    });
    return done.future;
  }

  Future<void> _leave() async {
    if (_busy || _restoring || _leaving) return;
    setState(() => _leaving = true);
    FocusScope.of(context).unfocus();
    _saveTimer?.cancel();
    await _saveChain;
    // Attempted reports are already durable and immutable. Do not recreate one
    // that a late server acknowledgement has cleared while this page was open.
    var saved = _sent || _draft != null;
    while (!saved && mounted) {
      final revision = _editRevision;
      if (!await _persistCurrent()) break;
      saved = revision == _editRevision;
    }
    _saveTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _leaving = false;
      _allowPop = saved;
    });
    if (!saved) return;
    Navigator.of(context).pop();
  }

  Future<void> _discard() async {
    if (_busy || _restoring || _leaving || _savedDraft == null) return;
    _saveTimer?.cancel();
    setState(() => _restoring = true);
    try {
      await _saveChain;
      if (!await _repository.discardSavedDraft(_savedDraft!)) {
        final current = await _repository.loadSavedDraft(
          expectedOwner: _draftOwner,
        );
        if (current != null) throw StateError('The device draft changed.');
        // A late confirmation may already have cleared this frozen report.
      }
      final useCapture = _incomingCapturePending;
      final saved = await _repository.openSavedDraft(
        expectedOwner: _draftOwner,
        message: useCapture ? widget.initialText : '',
        screenshot:
            useCapture && (widget.screenshot?.length ?? 0) <= feedbackImageLimit
            ? widget.screenshot
            : null,
      );
      if (!mounted || _disposed) return;
      _savedDraft = saved;
      _draft = null;
      _message.text = saved.message;
      _category = saved.category;
      _screenshot = saved.screenshot == null
          ? null
          : Uint8List.fromList(saved.screenshot!);
      _error = null;
      _saveError = null;
      _restored = false;
      _incomingCapturePending = false;
      _editRevision++;
      _localSaved = true;
      if (useCapture && (widget.screenshot?.length ?? 0) > feedbackImageLimit) {
        _screenshot = widget.screenshot;
        _saveError =
            'This screenshot is too large to save. Remove it to continue.';
        _localSaved = false;
      }
    } catch (_) {
      if (mounted && !_disposed) {
        _saveError = 'Could not discard the saved draft. Please try again.';
      }
    } finally {
      if (mounted && !_disposed) setState(() => _restoring = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_restoring &&
        !_busy &&
        !_sent &&
        _draft == null &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached)) {
      _saveTimer?.cancel();
      unawaited(_persistCurrent());
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _message.removeListener(_draftChanged);
    if (!_allowPop && !_localSaved && !_restoring && !_sent && _draft == null) {
      unawaited(_persistCurrent());
    }
    _message.dispose();
    super.dispose();
  }

  /// Sends.
  Future<void> _applyDeliveryConfirmation(FeedbackDraft submitted) async {
    await _repository.checkDraftOwner(submitted.uid);
    if (!mounted ||
        _disposed ||
        _restoring ||
        _leaving ||
        _draft?.id != submitted.id ||
        _savedDraft?.id != submitted.id) {
      return;
    }
    setState(() {
      _sent = true;
      _error = null;
    });
  }

  Future<void> _send() async {
    if (_busy || _restoring || _leaving || !_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _saveTimer?.cancel();
      await _saveChain;
      if (_draft == null) {
        if (!await _persistCurrent(freezeForSubmission: true)) return;
        _draft = _repository.submissionForSavedDraft(_savedDraft!);
        _message.text = _draft!.message;
      }
      final submitted = _draft!;
      final delivery = _repository.submit(submitted);
      unawaited(
        delivery.then<void>((_) async {
          try {
            await _applyDeliveryConfirmation(submitted);
          } catch (_) {
            // A completed request for the old account must not update a new page.
          }
        }, onError: (Object _, StackTrace __) {}),
      );
      await delivery.timeout(const Duration(seconds: 30));
      await _applyDeliveryConfirmation(submitted);
    } catch (error) {
      // Log the service/code only, never report text, screenshots or credentials.
      debugPrint(
        'Feedback submission failed: ${error is FirebaseException ? '${error.plugin}/${error.code}' : error.runtimeType}',
      );
      if (mounted) {
        setState(() => _error = feedbackSubmissionError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => PopScope(
    canPop:
        !_busy &&
        !_restoring &&
        !_leaving &&
        (_allowPop || _sent || (_localSaved && _saveError == null)),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      appBar: PageHeaderAppBar(
        title: Text(_sent ? 'Thank you' : 'Review feedback'),
      ),
      body: _sent
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your feedback is on its way to a better HikerCircle.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text('You can follow its status in My feedback.'),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                Form(
                  key: _form,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        'What would you like to share?',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (_restoring || _leaving)
                        const LinearProgressIndicator(),
                      if (_restored) ...[
                        const SizedBox(height: 12),
                        const Text('Your saved feedback has been restored.'),
                      ],
                      if (_incomingCapturePending)
                        const Text(
                          'Discard the saved draft below to use your new capture.',
                        ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: feedbackCategories
                            .map(
                              (category) => ChoiceChip(
                                label: Text(category),
                                selected: _category == category,
                                onSelected:
                                    _draft != null ||
                                        _busy ||
                                        _leaving ||
                                        _restoring ||
                                        _savedDraft == null
                                    ? null
                                    : (_) {
                                        setState(() => _category = category);
                                        _draftChanged();
                                      },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _message,
                        readOnly:
                            _draft != null ||
                            _busy ||
                            _leaving ||
                            _restoring ||
                            _savedDraft == null,
                        maxLength: 4000,
                        minLines: 5,
                        maxLines: 10,
                        validator: validateFeedback,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Your feedback',
                          hintText:
                              'What happened? What did you expect? How can we reproduce it?',
                        ),
                      ),
                      if (_screenshot != null) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.memory(
                            _screenshot!,
                            height: 220,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Text(
                              'Screenshot could not be displayed. Please remove it before sending.',
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed:
                              _draft != null || _busy || _restoring || _leaving
                              ? null
                              : () {
                                  setState(() => _screenshot = null);
                                  _draftChanged();
                                },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove screenshot'),
                        ),
                        if (_screenshot!.length > feedbackImageLimit)
                          const Text(
                            'This screenshot is too large (maximum 5 MB). Remove it to continue.',
                          ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        'Sending shares this text and optional screenshot privately with the HikerCircle admin team, along with your account ID and platform.',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _localSaved
                            ? 'Draft saved on this device. It is only sent when you tap Send or Retry.'
                            : 'Saving draft on this device…',
                      ),
                      if (_saveError != null) ...[
                        Text(
                          _saveError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        TextButton(
                          onPressed: _busy || _restoring || _leaving
                              ? null
                              : () {
                                  if (_savedDraft == null) {
                                    setState(() => _restoring = true);
                                    unawaited(_restoreSavedDraft());
                                  } else {
                                    unawaited(_persistCurrent());
                                  }
                                },
                          child: const Text('Try saving again'),
                        ),
                        TextButton(
                          onPressed: _busy || _restoring || _leaving
                              ? null
                              : () {
                                  _saveTimer?.cancel();
                                  setState(() => _allowPop = true);
                                  Navigator.of(context).pop();
                                },
                          child: const Text('Leave without saving'),
                        ),
                      ],
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      if (_draft != null && _error != null)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Retry uses the same report to avoid duplicates. Discard this draft before writing different feedback. Discarding cannot recall a report already accepted by the server.',
                          ),
                        ),
                      FilledButton.icon(
                        onPressed:
                            _busy ||
                                _leaving ||
                                _restoring ||
                                _savedDraft == null ||
                                (_screenshot?.length ?? 0) > feedbackImageLimit
                            ? null
                            : _send,
                        icon: const Icon(Icons.send_outlined),
                        label: Text(
                          _draft == null ? 'Send feedback' : 'Retry delivery',
                        ),
                      ),
                      TextButton.icon(
                        onPressed:
                            _busy ||
                                _restoring ||
                                _leaving ||
                                _savedDraft == null
                            ? null
                            : _discard,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(
                          _incomingCapturePending
                              ? 'Discard saved draft and use capture'
                              : 'Discard draft',
                        ),
                      ),
                    ],
                  ),
                ),
                if (_busy)
                  const Positioned.fill(
                    child: ModalBarrier(
                      dismissible: false,
                      color: Colors.black45,
                    ),
                  ),
                if (_busy)
                  const Center(
                    child: Dialog(
                      child: HikerCircleLoadingToast(
                        message: 'Sending your feedback…',
                        detail:
                            'Sharing your report with the HikerCircle team.',
                      ),
                    ),
                  ),
              ],
            ),
    ),
  );
}
