part of '../help_center_page_feature.dart';

/// Represents help step meta.
class _HelpStepMeta {
  /// Creates help step meta.
  const _HelpStepMeta({
    required this.icon,
    required this.eyebrow,
    required this.stage,
  });

  final IconData icon;
  final String eyebrow;
  final String stage;
}

/// Represents help guide.
class _HelpGuide {
  /// Creates help guide.
  const _HelpGuide({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.heroTitle,
    required this.heroSubtitle,
    required this.articles,
    required this.steps,
    required this.overview,
    required this.noticeTitle,
    required this.notice,
    this.sourceTitle,
    this.sourceUrl,
  });
  final String id, title, subtitle, badge, heroTitle, heroSubtitle;
  final List<HelpArticle> articles;
  final List<_HelpStepMeta> steps;
  final List<
    ({IconData icon, String title, String detail, String count, int start})
  >
  overview;
  final String noticeTitle, notice;
  final String? sourceTitle, sourceUrl;
}
