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
  const CommunityModerationRulesButton({super.key});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    icon: const Icon(Icons.policy_outlined),
    label: const Text('Moderation rules'),
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AdminUi.surface(context),
      showDragHandle: true,
      builder: (_) => const _ModerationRulesSheet(),
    ),
  );
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
                  'Read-only reference for this app version. A flag is a request for human review, not a confirmed violation.',
                  style: TextStyle(color: AdminUi.muted(context), height: 1.5),
                ),
                const SizedBox(height: 20),
                const _RuleSection(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Sensitive phrases',
                  description:
                      'These exact phrases are checked without regard to letter case, at word boundaries. Matches go to manual review; their text stays within the app backend. They are not banned words.',
                  child: _SensitivePhraseList(),
                ),
                const SizedBox(height: 16),
                const _RuleSection(
                  icon: Icons.manage_search_rounded,
                  title: 'Sensitive patterns',
                  description:
                      'Pattern matches also go directly to manual review. Long numbers can match even when they are not a phone number.',
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
                  icon: Icons.auto_awesome_outlined,
                  title: 'Manual review categories',
                  description:
                      'Administrators review meaning and context. Local checks identify sensitive data and malformed records; these categories describe issues an administrator may review:',
                  child: _ReviewCategoryList(),
                ),
                const SizedBox(height: 16),
                const _RuleSection(
                  icon: Icons.fact_check_outlined,
                  title: 'Other checks & limits',
                  description:
                      'Missing authors, mismatched record IDs, invalid text, empty comments and oversized content require manual review. Empty post captions are allowed.',
                  child: Text(
                    'Normal hiking experiences, safety discussions, injury reports and respectful disagreement are not automatically considered violations. Sensitive-pattern checks may still send them to manual review.\n\nChecks cover public text only, not images or private chats. Local checks do not understand context and may flag harmless content; always read the original before deciding. No rule automatically removes content.',
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
