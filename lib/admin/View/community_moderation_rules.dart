// CommunityModerationRulesButton exposes the backend moderation policy for admin review.
import 'package:flutter/material.dart';

import 'admin_ui.dart';

/// Read-only documentation of the backend policy. A regression test checks the
/// phrases and category IDs against functions/community_moderation.js.
const communitySensitivePhrases = <String>[
  'my name is',
  'nama saya',
  'password',
  'kata laluan',
  'otp',
  'verification code',
  'authenticator',
  'diagnosed',
  'diagnosis',
  'medical record',
  'my injury',
  'my illness',
  'alamat rumah',
  'home address',
  'ic number',
  'passport',
];

const communityReviewCategories = <String, String>{
  'spam_scam': 'Spam & scams',
  'harassment': 'Targeted harassment',
  'hate': 'Hate speech',
  'sexual': 'Explicit sexual content',
  'violence': 'Threats & graphic violence',
  'privacy': 'Personal information exposure',
  'unsafe_advice': 'Dangerous advice',
};

class CommunityModerationRulesButton extends StatelessWidget {
  const CommunityModerationRulesButton({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    void openRules() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AdminUi.surface(context),
      showDragHandle: true,
      builder: (_) => const _ModerationRulesSheet(),
    );
    return compact
        ? IconButton(
            tooltip: 'Moderation rules',
            onPressed: openRules,
            icon: const Icon(Icons.policy_outlined),
          )
        : OutlinedButton.icon(
            icon: const Icon(Icons.policy_outlined),
            label: const Text('Moderation rules'),
            onPressed: openRules,
          );
  }
}

class _ModerationRulesSheet extends StatelessWidget {
  const _ModerationRulesSheet();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .82,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Moderation rules',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Close moderation rules',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Use the source label and matched rule to understand a flag. Read the original content before taking action.',
                  style: TextStyle(color: AdminUi.muted(context), height: 1.5),
                ),
                const SizedBox(height: 16),
                const _DetectionSources(),
                const SizedBox(height: 16),
                const _RuleSection(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Keyword matches',
                  description:
                      'These phrases match without regard to letter case, at word boundaries. A flag shows the matched phrase; it does not mean the phrase is banned.',
                  child: _SensitivePhraseList(),
                ),
                const SizedBox(height: 16),
                const _RuleSection(
                  icon: Icons.manage_search_rounded,
                  title: 'Pattern matches',
                  description:
                      'Flags name the pattern without copying the personal value into their evidence. A long number can match even when it is not a phone number.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _RuleItem(
                        title: 'Email addresses',
                        description: 'Example: hiker@example.com',
                      ),
                      _RuleItem(
                        title: 'Phone-like numbers',
                        description:
                            'Long digit sequences, including spaces, brackets, dots or hyphens. Example: +60 12-345 6789',
                      ),
                      _RuleItem(
                        title: 'Coordinate pairs',
                        description:
                            'Two decimal numbers separated by a comma or slash, with at least three decimal places. Example: 5.1234, 100.1234',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const _RuleSection(
                  icon: Icons.checklist_rounded,
                  title: 'Review categories',
                  description:
                      'Categories describe the concern, while the source label explains how it was detected. A category alone does not mean Gemini checked the content.',
                  child: _ReviewCategoryList(),
                ),
                const SizedBox(height: 16),
                const _RuleSection(
                  icon: Icons.fact_check_outlined,
                  title: 'Record checks & limits',
                  description:
                      'Missing authors, mismatched record IDs, invalid text, empty comments and oversized content require manual review. Empty post captions are allowed.',
                  child: Text(
                    'Normal hiking experiences, injury reports and respectful disagreement are allowed. A keyword or pattern may still flag them for review.\n\nCurrent checks cover public text, not images or private chats. Local rules cannot understand context. No check automatically removes content.',
                    style: TextStyle(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _DetectionSources extends StatelessWidget {
  const _DetectionSources();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AdminUi.green(context).withValues(alpha: .07),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AdminUi.green(context).withValues(alpha: .16)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.rule_rounded, color: AdminUi.green(context)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Current checks use local rules',
                style: TextStyle(fontWeight: FontWeight.w800, height: 1.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'The server checks public text every 30 minutes. Sensitive text stays in the app backend and is not sent to Gemini by this checker.',
          style: TextStyle(color: AdminUi.muted(context), height: 1.5),
        ),
        const SizedBox(height: 14),
        const _SourceLabel(
          icon: Icons.text_fields_rounded,
          label: 'Keyword match',
          description: 'An exact policy phrase matched.',
        ),
        const _SourceLabel(
          icon: Icons.manage_search_rounded,
          label: 'Pattern match',
          description: 'An email, phone number or coordinate pattern matched.',
        ),
        const _SourceLabel(
          icon: Icons.fact_check_outlined,
          label: 'Record check',
          description: 'Required content data is missing or invalid.',
        ),
        Divider(color: AdminUi.border(context), height: 24),
        const _SourceLabel(
          icon: Icons.auto_awesome_outlined,
          label: 'Gemini',
          description:
              'Shown only when a saved flag identifies Gemini. The current checker does not use Gemini.',
        ),
        const _SourceLabel(
          icon: Icons.history_rounded,
          label: 'Local rules / Source unavailable',
          description:
              'Older flags may not include the exact rule or a recognized source. Their original reason remains available.',
        ),
        const SizedBox(height: 4),
        Text(
          'A flag is a request for review, not a confirmed violation.',
          style: TextStyle(
            color: AdminUi.green(context),
            fontWeight: FontWeight.w700,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

class _SourceLabel extends StatelessWidget {
  const _SourceLabel({
    required this.icon,
    required this.label,
    required this.description,
  });
  final IconData icon;
  final String label, description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: AdminUi.green(context)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                description,
                style: TextStyle(color: AdminUi.muted(context), height: 1.4),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SensitivePhraseList extends StatelessWidget {
  const _SensitivePhraseList();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final phrase in communitySensitivePhrases)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AdminUi.green(context).withValues(alpha: .09),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(phrase, style: TextStyle(color: AdminUi.green(context))),
        ),
    ],
  );
}

class _ReviewCategoryList extends StatelessWidget {
  const _ReviewCategoryList();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final category in communityReviewCategories.values)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                Icons.checklist_rounded,
                size: 18,
                color: AdminUi.green(context),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(category)),
            ],
          ),
        ),
    ],
  );
}

class _RuleSection extends StatelessWidget {
  const _RuleSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });
  final IconData icon;
  final String title, description;
  final Widget child;

  @override
  Widget build(BuildContext context) => AdminPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: AdminUi.green(context)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          description,
          style: TextStyle(color: AdminUi.muted(context), height: 1.5),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _RuleItem extends StatelessWidget {
  const _RuleItem({required this.title, required this.description});
  final String title, description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(color: AdminUi.muted(context), height: 1.4),
        ),
      ],
    ),
  );
}
