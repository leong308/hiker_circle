// FeedbackPage provides feedback capture, composition, inbox and submission detail screens.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';

import '../core/widgets/loading_toast.dart';
import 'feedback_repository.dart';

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
class _FeedbackComposePageState extends State<FeedbackComposePage> {
  final _form = GlobalKey<FormState>();
  late final _repository = widget.repository ?? FeedbackRepository();
  late final _message = TextEditingController(text: widget.initialText);
  late Uint8List? _screenshot = widget.screenshot;
  String _category = feedbackCategories.first;
  FeedbackDraft? _draft;
  bool _busy = false;
  bool _sent = false;
  String? _error;

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  /// Sends.
  Future<void> _send() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _draft ??= _repository.draft(_category, _message.text, _screenshot);
      await _repository.submit(_draft!).timeout(const Duration(seconds: 30));
      if (mounted) setState(() => _sent = true);
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
    canPop: !_busy,
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
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: feedbackCategories
                            .map(
                              (category) => ChoiceChip(
                                label: Text(category),
                                selected: _category == category,
                                onSelected: _draft != null || _busy
                                    ? null
                                    : (_) =>
                                          setState(() => _category = category),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _message,
                        readOnly: _draft != null || _busy,
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
                          onPressed: _draft != null || _busy
                              ? null
                              : () => setState(() => _screenshot = null),
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
                            'Retry uses the same report to avoid duplicates. To write different feedback, go back and start a new report.',
                          ),
                        ),
                      FilledButton.icon(
                        onPressed:
                            _busy ||
                                (_screenshot?.length ?? 0) > feedbackImageLimit
                            ? null
                            : _send,
                        icon: const Icon(Icons.send_outlined),
                        label: Text(
                          _draft == null ? 'Send feedback' : 'Retry delivery',
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

/// Displays the feedback inbox page.
class FeedbackInboxPage extends StatefulWidget {
  /// Creates feedback inbox page.
  const FeedbackInboxPage({super.key, this.admin = false, this.repository});
  final bool admin;
  final FeedbackRepository? repository;

  /// Creates the presentation state for this widget.
  @override
  State<FeedbackInboxPage> createState() => _FeedbackInboxPageState();
}

/// Manages the feedback inbox page presentation and lifecycle.
class _FeedbackInboxPageState extends State<FeedbackInboxPage> {
  late final _repository = widget.repository ?? FeedbackRepository();
  late Stream<QuerySnapshot<Map<String, dynamic>>> _reports;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _reports = _repository.reports(admin: widget.admin);
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PageHeaderAppBar(
      title: Text(widget.admin ? 'Feedback inbox' : 'My feedback'),
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _reports,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unable to load feedback.'),
                TextButton(
                  onPressed: () => setState(
                    () => _reports = _repository.reports(admin: widget.admin),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const HikerCircleLoadingView(message: 'Loading feedback…');
        }
        final reports = snapshot.data!.docs;
        if (reports.isEmpty) {
          return const Center(child: Text('No feedback submitted yet.'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Most recent 100 reports'),
            ),
            for (final report in reports)
              Card(
                child: ListTile(
                  leading: Icon(
                    report.data()['category'] == 'Problem'
                        ? Icons.bug_report_outlined
                        : Icons.lightbulb_outline,
                  ),
                  title: Text(
                    report.data()['message'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${report.data()['category']} · ${report.data()['status']}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _FeedbackDetailPage(
                        id: report.id,
                        data: report.data(),
                        admin: widget.admin,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// Displays the feedback detail page.
class _FeedbackDetailPage extends StatefulWidget {
  /// Creates feedback detail page.
  const _FeedbackDetailPage({
    required this.id,
    required this.data,
    required this.admin,
  });
  final String id;
  final Map<String, dynamic> data;
  final bool admin;

  /// Creates the presentation state for this widget.
  @override
  State<_FeedbackDetailPage> createState() => _FeedbackDetailPageState();
}

/// Manages the feedback detail page presentation and lifecycle.
class _FeedbackDetailPageState extends State<_FeedbackDetailPage> {
  final _repository = FeedbackRepository();
  late String _status = widget.data['status'] as String;
  late final Future<Uint8List?>? _image =
      (widget.data['screenshotPath'] as String).isEmpty
      ? null
      : _repository
            .screenshot(widget.data['screenshotPath'] as String)
            .timeout(const Duration(seconds: 30));
  bool _busy = false;

  /// Computes change status.
  Future<void> _changeStatus(String status) async {
    setState(() => _busy = true);
    try {
      await _repository
          .setStatus(widget.id, status)
          .timeout(const Duration(seconds: 30));
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not confirm the status update. Please retry.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PageHeaderAppBar(title: const Text('Feedback details')),
    body: Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text(widget.data['category'] as String)),
                Chip(label: Text(_status)),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              widget.data['message'] as String,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            Text('Platform: ${widget.data['platform']}'),
            if (widget.data['createdAt'] is Timestamp)
              Text(
                'Submitted: ${_feedbackDate(context, widget.data['createdAt'] as Timestamp)}',
              ),
            if (_image != null)
              FutureBuilder<Uint8List?>(
                future: _image,
                builder: (_, snapshot) {
                  if (snapshot.hasError ||
                      (snapshot.connectionState == ConnectionState.done &&
                          !snapshot.hasData)) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Screenshot unavailable. Reopen this report to retry.',
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const SizedBox(
                      height: 230,
                      child: HikerCircleLoadingView(
                        message: 'Loading screenshot…',
                      ),
                    );
                  }
                  return SizedBox(
                    height: 420,
                    child: InteractiveViewer(
                      child: Image.memory(
                        snapshot.data!,
                        errorBuilder: (_, _, _) => const Center(
                          child: Text(
                            'This screenshot could not be displayed.',
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            if (widget.admin) ...[
              const SizedBox(height: 24),
              const Text('Review status'),
              Wrap(
                spacing: 8,
                children: feedbackStatuses
                    .map(
                      (status) => ChoiceChip(
                        label: Text(status),
                        selected: _status == status,
                        onSelected: _busy ? null : (_) => _changeStatus(status),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
        if (_busy)
          const Positioned.fill(
            child: ModalBarrier(dismissible: false, color: Colors.black45),
          ),
        if (_busy)
          const Center(
            child: Dialog(
              child: HikerCircleLoadingToast(message: 'Updating feedback…'),
            ),
          ),
      ],
    ),
  );
}

/// Computes feedback date.
String _feedbackDate(BuildContext context, Timestamp timestamp) {
  final date = timestamp.toDate().toLocal();
  return '${MaterialLocalizations.of(context).formatMediumDate(date)} · ${TimeOfDay.fromDateTime(date).format(context)}';
}
