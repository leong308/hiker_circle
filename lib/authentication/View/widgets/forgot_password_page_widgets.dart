part of '../../forgot_password_page_feature.dart';

/// Displays the reset password header.
class _ResetPasswordHeader extends StatelessWidget {
  /// Creates reset password header.
  const _ResetPasswordHeader({required this.onBack});

  final VoidCallback onBack;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        children: [
          PageHeaderAction(
            tooltip: 'Back',
            icon: CupertinoIcons.chevron_back,
            onPressed: onBack,
            color: scheme.primary,
            surface: scheme.surfaceContainerHigh,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reset password',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PageHeaderStyle.title(context, scheme.onSurface),
                ),
                Text(
                  'Verify your identity and secure your account',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PageHeaderStyle.subtitle(
                    context,
                    scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
