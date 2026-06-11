import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../Model/me_models.dart';
import '../ModelView/me_view_model.dart';
import 'location_sharing_page.dart';

class MePage extends StatefulWidget {
  const MePage({
    super.key,
    required this.phoneNumber,
    required this.onSignOut,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final String phoneNumber;
  final VoidCallback onSignOut;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  late final MeViewModel viewModel;

  @override
  void initState() {
    super.initState();
    viewModel = MeViewModel(phoneNumber: widget.phoneNumber);
  }

  @override
  void dispose() {
    viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _MeColors.background,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(profile: viewModel.profile),
                  const SizedBox(height: 16),
                  _ProfileCell(profile: viewModel.profile),
                  const SizedBox(height: 14),
                  _StatsGroup(stats: viewModel.stats),
                  const SizedBox(height: 22),
                  for (final section in viewModel.sections) ...[
                    _SettingsSection(
                      section: section,
                      onItemTap: _openActionItem,
                    ),
                    const SizedBox(height: 18),
                  ],
                  _SignOutCell(onSignOut: widget.onSignOut),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openActionItem(MeActionItem item) {
    if (item.title != 'Location sharing') {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LocationSharingPage(
          phoneNumber: widget.phoneNumber,
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.profile});

  final MeProfile profile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: _MeColors.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Welcome back, ${profile.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _MeColors.secondaryText,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const _HeaderAction(tooltip: 'QR code', icon: Icons.qr_code_rounded),
          const SizedBox(width: 8),
          const _HeaderAction(
            tooltip: 'Settings',
            icon: CupertinoIcons.gear_alt_fill,
          ),
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.tooltip, required this.icon});

  final String tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(36),
        onPressed: () {},
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: _MeColors.green, size: 19),
        ),
      ),
    );
  }
}

class _ProfileCell extends StatelessWidget {
  const _ProfileCell({required this.profile});

  final MeProfile profile;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: _TapSurface(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _MeColors.greenSoft,
                ),
                child: const Icon(
                  CupertinoIcons.person_fill,
                  color: _MeColors.green,
                  size: 31,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _MeColors.text,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _MeColors.secondaryText,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.qr_code_rounded,
                color: _MeColors.green,
                size: 22,
              ),
              const SizedBox(width: 12),
              const Icon(
                CupertinoIcons.chevron_forward,
                color: _MeColors.chevron,
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsGroup extends StatelessWidget {
  const _StatsGroup({required this.stats});

  final List<MeStat> stats;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            for (var index = 0; index < stats.length; index++) ...[
              Expanded(child: _StatCell(stat: stats[index])),
              if (index != stats.length - 1) const _VerticalSeparator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.stat});

  final MeStat stat;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          stat.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _MeColors.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          stat.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: _MeColors.secondaryText,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.section, required this.onItemTap});

  final MeSection section;
  final ValueChanged<MeActionItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 14, bottom: 7),
          child: Text(
            section.title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _MeColors.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ),
        _InsetGroup(
          child: Column(
            children: [
              for (var index = 0; index < section.items.length; index++) ...[
                _SettingsCell(
                  item: section.items[index],
                  onTap: () => onItemTap(section.items[index]),
                ),
                if (index != section.items.length - 1)
                  const Padding(
                    padding: EdgeInsets.only(left: 58),
                    child: _HorizontalSeparator(),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsCell extends StatelessWidget {
  const _SettingsCell({required this.item, required this.onTap});

  final MeActionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TapSurface(
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          child: Row(
            children: [
              _Glyph(icon: item.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _MeColors.text,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                CupertinoIcons.chevron_forward,
                color: _MeColors.chevron,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignOutCell extends StatelessWidget {
  const _SignOutCell({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: _TapSurface(
        onTap: onSignOut,
        child: SizedBox(
          height: 52,
          child: Center(
            child: Text(
              'Sign Out',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: _MeColors.destructive,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: _MeColors.green,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _TapSurface extends StatelessWidget {
  const _TapSurface({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap ?? () {}, child: child),
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
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }
}

class _HorizontalSeparator extends StatelessWidget {
  const _HorizontalSeparator();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 0.7, color: _MeColors.separator);
  }
}

class _VerticalSeparator extends StatelessWidget {
  const _VerticalSeparator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 32,
      child: VerticalDivider(
        width: 1,
        thickness: 0.7,
        color: _MeColors.separator,
      ),
    );
  }
}

abstract final class _MeColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color chevron = Color(0xFFC7C7CC);
  static const Color destructive = Color(0xFFFF3B30);
}
