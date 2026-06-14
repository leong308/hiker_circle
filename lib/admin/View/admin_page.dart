import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({
    super.key,
    required this.session,
    this.hikerCircleRepository,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final AppSession session;
  final HikerCircleFirebaseRepository? hikerCircleRepository;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late final HikerCircleFirebaseRepository _repository =
      widget.hikerCircleRepository ??
      HikerCircleFirebaseRepository(
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      );

  List<Map<String, dynamic>> _hazardReports = const [];
  List<Map<String, dynamic>> _communityPosts = const [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAdminData());
  }

  Future<void> _loadAdminData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait<Object>([
        _repository.loadAdminHazardReports(session: widget.session),
        _repository.loadAdminCommunityPosts(session: widget.session),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _hazardReports = results[0] as List<Map<String, dynamic>>;
        _communityPosts = results[1] as List<Map<String, dynamic>>;
      });
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Unable to load admin data: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _reviewHazard(
    Map<String, dynamic> report, {
    required bool approved,
  }) async {
    await _runAdminAction(
      successMessage: approved
          ? 'Hazard report approved.'
          : 'Hazard report rejected.',
      action: () async {
        await _repository.reviewHazardReport(
          session: widget.session,
          report: report,
          approved: approved,
        );
      },
    );
  }

  Future<void> _moderatePost(
    Map<String, dynamic> post, {
    required String status,
  }) async {
    await _runAdminAction(
      successMessage: 'Community post marked $status.',
      action: () async {
        await _repository.moderateCommunityPost(
          session: widget.session,
          postId: _stringFrom(post['postId']),
          moderationStatus: status,
        );
      },
    );
  }

  Future<void> _runAdminAction({
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      await action();
      await _loadAdminData();
      if (!mounted) {
        return;
      }
      _showSnack(successMessage);
    } on HikerCircleFirebaseRepositoryException catch (error) {
      _showSnack(error.message, isError: true);
    } catch (_) {
      _showSnack('Admin action failed. Please try again.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? _AdminColors.redFor(context)
              : _AdminColors.green,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.session.isAdmin) {
      return const _AdminLockedState();
    }

    final pendingHazards = _hazardReports.where((report) {
      final status = _stringFrom(report['status']).toLowerCase();
      return status.isEmpty || status == 'unverified' || status == 'pending';
    }).length;
    final hiddenPosts = _communityPosts.where((post) {
      final visibility = _stringFrom(post['visibility']).toLowerCase();
      return visibility == 'hidden' || visibility == 'removed';
    }).length;
    return ColoredBox(
      color: _AdminColors.backgroundFor(context),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAdminData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 100),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AdminHeader(
                      isLoading: _isLoading,
                      onRefresh: () => unawaited(_loadAdminData()),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      _AdminNotice(message: _errorMessage!),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _AdminMetric(
                            label: 'Pending Hazards',
                            value: '$pendingHazards',
                            icon: Icons.warning_amber_rounded,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _AdminMetric(
                            label: 'Moderated',
                            value: '$hiddenPosts',
                            icon: Icons.shield_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SectionTitle(label: 'Hazard Reports'),
                    const SizedBox(height: 8),
                    _InsetGroup(
                      child: Column(
                        children: [
                          if (_hazardReports.isEmpty)
                            const _EmptyState(
                              message: 'No hazard reports to review.',
                            )
                          else
                            for (
                              var index = 0;
                              index < _hazardReports.length;
                              index++
                            ) ...[
                              _HazardAdminRow(
                                report: _hazardReports[index],
                                isSaving: _isSaving,
                                onApprove: () => unawaited(
                                  _reviewHazard(
                                    _hazardReports[index],
                                    approved: true,
                                  ),
                                ),
                                onReject: () => unawaited(
                                  _reviewHazard(
                                    _hazardReports[index],
                                    approved: false,
                                  ),
                                ),
                              ),
                              if (index != _hazardReports.length - 1)
                                const _HorizontalSeparator(),
                            ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SectionTitle(label: 'Community Moderation'),
                    const SizedBox(height: 8),
                    _InsetGroup(
                      child: Column(
                        children: [
                          if (_communityPosts.isEmpty)
                            const _EmptyState(
                              message: 'No community posts to moderate.',
                            )
                          else
                            for (
                              var index = 0;
                              index < _communityPosts.length;
                              index++
                            ) ...[
                              _PostAdminRow(
                                post: _communityPosts[index],
                                isSaving: _isSaving,
                                onApprove: () => unawaited(
                                  _moderatePost(
                                    _communityPosts[index],
                                    status: 'approved',
                                  ),
                                ),
                                onHide: () => unawaited(
                                  _moderatePost(
                                    _communityPosts[index],
                                    status: 'hidden',
                                  ),
                                ),
                                onRemove: () => unawaited(
                                  _moderatePost(
                                    _communityPosts[index],
                                    status: 'removed',
                                  ),
                                ),
                              ),
                              if (index != _communityPosts.length - 1)
                                const _HorizontalSeparator(),
                            ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminLockedState extends StatelessWidget {
  const _AdminLockedState();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _AdminColors.backgroundFor(context),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Admin privilege is required.'),
        ),
      ),
    );
  }
}

class _AdminHeader extends StatelessWidget {
  const _AdminHeader({required this.isLoading, required this.onRefresh});

  final bool isLoading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _CircleIcon(icon: Icons.admin_panel_settings_rounded),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Admin Console',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _AdminColors.textFor(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              Text(
                'Manage trails, reports, and community safety.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _AdminColors.secondaryTextFor(context),
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        Tooltip(
          message: 'Refresh admin data',
          child: IconButton(
            onPressed: isLoading ? null : onRefresh,
            icon: isLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ),
      ],
    );
  }
}

class _AdminMetric extends StatelessWidget {
  const _AdminMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: _AdminColors.green, size: 22),
            const SizedBox(height: 7),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _AdminColors.textFor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _AdminColors.secondaryTextFor(context),
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HazardAdminRow extends StatelessWidget {
  const _HazardAdminRow({
    required this.report,
    required this.isSaving,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> report;
  final bool isSaving;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final status = _stringFrom(report['status']).isEmpty
        ? 'unverified'
        : _stringFrom(report['status']);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CircleIcon(icon: Icons.report_problem_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: _AdminTextBlock(
                  title: _stringFrom(report['hazardType']).isEmpty
                      ? 'Hazard report'
                      : _stringFrom(report['hazardType']),
                  subtitle:
                      '${_stringFrom(report['trailName'])} - ${_stringFrom(report['severity']).toUpperCase()} - $status',
                  body: _stringFrom(report['description']),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: isSaving ? null : onApprove,
                  icon: const Icon(Icons.verified_rounded),
                  label: const Text('Approve'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isSaving ? null : onReject,
                  icon: const Icon(Icons.block_rounded),
                  label: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PostAdminRow extends StatelessWidget {
  const _PostAdminRow({
    required this.post,
    required this.isSaving,
    required this.onApprove,
    required this.onHide,
    required this.onRemove,
  });

  final Map<String, dynamic> post;
  final bool isSaving;
  final VoidCallback onApprove;
  final VoidCallback onHide;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final visibility = _stringFrom(post['visibility']).isEmpty
        ? 'public'
        : _stringFrom(post['visibility']);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CircleIcon(icon: Icons.forum_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: _AdminTextBlock(
                  title: _stringFrom(post['authorHandle']).isEmpty
                      ? _stringFrom(post['authorPhoneNumber'])
                      : _stringFrom(post['authorHandle']),
                  subtitle:
                      '${_stringFrom(post['trailName']).isEmpty ? 'General' : _stringFrom(post['trailName'])} - $visibility',
                  body: _stringFrom(post['caption']),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: isSaving ? null : onApprove,
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('Approve'),
              ),
              OutlinedButton.icon(
                onPressed: isSaving ? null : onHide,
                icon: const Icon(Icons.visibility_off_rounded),
                label: const Text('Hide'),
              ),
              OutlinedButton.icon(
                onPressed: isSaving ? null : onRemove,
                icon: const Icon(Icons.delete_rounded),
                label: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminTextBlock extends StatelessWidget {
  const _AdminTextBlock({
    required this.title,
    required this.subtitle,
    required this.body,
  });

  final String title;
  final String subtitle;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.isEmpty ? 'Untitled' : title,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: _AdminColors.textFor(context),
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _AdminColors.secondaryTextFor(context),
            letterSpacing: 0,
          ),
        ),
        if (body.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _AdminColors.textFor(context),
              letterSpacing: 0,
            ),
          ),
        ],
      ],
    );
  }
}

class _AdminNotice extends StatelessWidget {
  const _AdminNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _AdminColors.redFor(context).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _AdminColors.redFor(context),
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: _AdminColors.secondaryTextFor(context),
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: _AdminColors.secondaryTextFor(context),
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _AdminColors.greenSoftFor(context),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: _AdminColors.green, size: 20),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(color: _AdminColors.surfaceFor(context)),
        child: child,
      ),
    );
  }
}

class _HorizontalSeparator extends StatelessWidget {
  const _HorizontalSeparator();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.7,
      color: _AdminColors.separatorFor(context),
    );
  }
}

String _stringFrom(Object? value) {
  return value is String ? value : '';
}

abstract final class _AdminColors {
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color background = Color(0xFFF2F8F4);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color separator = Color(0xFFE5EFE8);
  static const Color red = Color(0xFFE11D48);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  static Color redFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B88) : red;
}
