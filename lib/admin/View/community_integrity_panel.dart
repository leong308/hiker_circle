import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/app_toast.dart';
import '../../core/widgets/loading_toast.dart';
import 'admin_ui.dart';
import 'community_moderation_rules.dart';

class CommunityIntegrityPanel extends StatefulWidget {
  const CommunityIntegrityPanel({
    super.key,
    this.onReviewed,
    this.reviews,
    this.health,
  });
  final VoidCallback? onReviewed;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? reviews;
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? health;

  @override
  State<CommunityIntegrityPanel> createState() =>
      _CommunityIntegrityPanelState();
}

class _CommunityIntegrityPanelState extends State<CommunityIntegrityPanel> {
  late final _reviews =
      widget.reviews ??
      FirebaseFirestore.instance
          .collection('communityModerationReviews')
          .where('status', isEqualTo: 'pending')
          .limit(50)
          .snapshots();
  late final _health =
      widget.health ??
      FirebaseFirestore.instance
          .doc('communityModerationStatus/current')
          .snapshots();

  Future<void> _open(QueryDocumentSnapshot<Map<String, dynamic>> flag) async {
    final reviewed = await showDialog<bool>(
      context: context,
      builder: (_) => _FlagReviewDialog(reviewId: flag.id, flag: flag.data()),
    );
    if (mounted && reviewed == true) widget.onReviewed?.call();
  }

  @override
  Widget build(BuildContext context) {
    if ((widget.reviews == null || widget.health == null) &&
        Firebase.apps.isEmpty) {
      return const AdminPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Community integrity checks are available when Firebase is connected. You can still review loaded posts below.',
            ),
            SizedBox(height: 12),
            CommunityModerationRulesButton(),
          ],
        ),
      );
    }
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, color: AdminUi.green(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Community integrity',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(label: Text('Every 30 min')),
              CommunityModerationRulesButton(),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'AI suggestions only. Content stays visible until you take action.',
            style: TextStyle(color: AdminUi.muted(context)),
          ),
          const SizedBox(height: 12),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _health,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                  'Check status is unavailable. You can still moderate posts below.',
                );
              }
              final data = snapshot.data?.data();
              final millis = data?['lastRunAtMillis'];
              if (millis is! num) {
                return const Text('Waiting for the first scheduled check.');
              }
              final date = DateTime.fromMillisecondsSinceEpoch(
                millis.toInt(),
              ).toLocal();
              final local = MaterialLocalizations.of(context);
              final time =
                  '${local.formatMediumDate(date)} · ${local.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
              final deferred = data?['status'] == 'deferred';
              return Text(
                '${deferred ? 'AI check deferred; content remains queued' : 'Last check completed'}\n$time',
                style: TextStyle(
                  color: deferred
                      ? Colors.orange.shade700
                      : AdminUi.muted(context),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _reviews,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                  'Review queue could not load. Reopen this section to retry.',
                );
              }
              if (!snapshot.hasData) {
                return const HikerCircleLoadingView(
                  message: 'Loading reviews…',
                );
              }
              final reviews = [...snapshot.data!.docs]
                ..sort(
                  (a, b) => ((b.data()['flaggedAtMillis'] as num?) ?? 0)
                      .compareTo((a.data()['flaggedAtMillis'] as num?) ?? 0),
                );
              if (reviews.isEmpty) {
                return const Text('No content currently needs review.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${reviews.length}${reviews.length == 50 ? '+' : ''} awaiting review',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  for (final flag in reviews)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        flag.data()['contentType'] == 'comment'
                            ? Icons.chat_bubble_outline
                            : Icons.article_outlined,
                        color: AdminUi.green(context),
                      ),
                      title: Text(_reasons(flag.data())),
                      subtitle: Text(
                        '${flag.data()['contentType'] == 'comment' ? 'Comment' : 'Post'} · ${flag.data()['model'] == null ? 'Manual check' : 'AI suggestion'}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _open(flag),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String _reasons(Map<String, dynamic> flag) =>
    (flag['reasons'] is List
            ? (flag['reasons'] as List).whereType<String>().join(' · ')
            : '')
        .isEmpty
    ? 'Content needs review'
    : (flag['reasons'] as List).whereType<String>().join(' · ');

class _FlagReviewDialog extends StatefulWidget {
  const _FlagReviewDialog({required this.reviewId, required this.flag});
  final String reviewId;
  final Map<String, dynamic> flag;
  @override
  State<_FlagReviewDialog> createState() => _FlagReviewDialogState();
}

class _FlagReviewDialogState extends State<_FlagReviewDialog> {
  late final _source = _loadSource();
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadSource() async {
    final source = await FirebaseFirestore.instance
        .doc(widget.flag['sourcePath'] as String)
        .get()
        .timeout(const Duration(seconds: 15));
    if (mounted) setState(() => _loaded = source.exists);
    return source;
  }

  Future<void> _review(String action) async {
    if (_saving) return;
    final isComment = widget.flag['contentType'] == 'comment';
    if (action == 'hide') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(isComment ? 'Remove this comment?' : 'Hide this post?'),
          content: Text(
            isComment
                ? 'The comment will be removed. A copy is kept in the private moderation audit.'
                : 'The post will no longer appear in the public community feed. It will not be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('reviewCommunityContentFlag')
          .call<Map<String, dynamic>>({
            'reviewId': widget.reviewId,
            'action': action,
          })
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      final changed = response.data['status'] == 'superseded';
      HikerCircleToast.show(
        context,
        changed
            ? 'The content changed. No moderation action was applied.'
            : 'Review saved.',
        tone: changed
            ? HikerCircleToastTone.info
            : HikerCircleToastTone.success,
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'Review could not be saved. Check your connection and retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      backgroundColor: AdminUi.surface(context),
      title: const Text('Review flagged content'),
      content: SizedBox(
        width: 420,
        child: _saving
            ? const HikerCircleLoadingView(message: 'Saving review…')
            : FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: _source,
                builder: (context, snapshot) {
                  if (!snapshot.hasData && !snapshot.hasError) {
                    return const HikerCircleLoadingView(
                      message: 'Opening content…',
                    );
                  }
                  final data = snapshot.data?.data();
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _reasons(widget.flag),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This is a suggestion, not a confirmed violation. Review the actual content before deciding.',
                          style: TextStyle(color: AdminUi.muted(context)),
                        ),
                        const Divider(height: 24),
                        if (snapshot.hasError)
                          const Text(
                            'Content could not load. Close and reopen to retry.',
                          )
                        else if (data == null)
                          const Text('This content has already been removed.')
                        else
                          SelectableText(
                            (widget.flag['contentType'] == 'comment'
                                        ? data['body']
                                        : data['caption'])
                                    ?.toString() ??
                                '',
                          ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: _saving
          ? []
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              OutlinedButton(
                onPressed: () => _review('dismiss'),
                child: const Text('Dismiss flag'),
              ),
              FilledButton(
                onPressed: _loaded ? () => _review('hide') : null,
                child: Text(
                  widget.flag['contentType'] == 'comment'
                      ? 'Remove comment'
                      : 'Hide post',
                ),
              ),
            ],
    ),
  );
}
