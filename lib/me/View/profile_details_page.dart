import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Model/app_session.dart';
import '../../onboarding/Data/onboarding_repository.dart';
import '../../onboarding/Data/google_city_geocoding_service.dart';
import '../../onboarding/Model/onboarding_profile.dart';
import '../../onboarding/View/residential_city_picker_page.dart';

class ProfileDetailsPage extends StatefulWidget {
  const ProfileDetailsPage({
    super.key,
    required this.session,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
    this.repository,
  });

  final AppSession session;
  final FirebaseBootstrapResult firebaseBootstrapResult;
  final OnboardingRepository? repository;

  @override
  State<ProfileDetailsPage> createState() => _ProfileDetailsPageState();
}

class _ProfileDetailsPageState extends State<ProfileDetailsPage> {
  late final OnboardingRepository _repository;
  late Future<OnboardingProfile> _profileFuture;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        OnboardingRepository(
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
        );
    _profileFuture = _repository.loadProfile(widget.session);
  }

  void _retry() {
    setState(() {
      _profileFuture = _repository.loadProfile(widget.session);
    });
  }

  Future<void> _editExperience(OnboardingProfile profile) async {
    final value = await _showChoiceEditor(
      title: 'Hiking experience',
      currentValue: profile.hikerExperience,
      choices: const [
        ('new', 'New hiker'),
        ('experienced', 'Experienced hiker'),
      ],
    );
    if (value != null) {
      await _saveProfile(profile.copyWith(hikerExperience: value));
    }
  }

  Future<void> _editFrequency(OnboardingProfile profile) async {
    final value = await _showChoiceEditor(
      title: 'Hike frequency',
      currentValue: profile.hikeFrequency,
      choices: const [
        ('rarely', 'A few times a year'),
        ('monthly', 'About once a month'),
        ('several_times_monthly', 'Several times a month'),
        ('weekly', 'Weekly or more'),
      ],
    );
    if (value != null) {
      await _saveProfile(profile.copyWith(hikeFrequency: value));
    }
  }

  Future<void> _editResidentialCity(OnboardingProfile profile) async {
    final selection = await Navigator.of(context)
        .push<ResidentialCitySelection>(
          MaterialPageRoute<ResidentialCitySelection>(
            builder: (context) => ResidentialCityPickerPage(
              initialLatitude: profile.residentialLatitude,
              initialLongitude: profile.residentialLongitude,
              allowCancel: true,
            ),
          ),
        );
    if (selection == null || !mounted) {
      return;
    }
    await _saveProfile(
      profile.copyWith(
        residentialLocation: selection.label,
        residentialLatitude: selection.latitude,
        residentialLongitude: selection.longitude,
      ),
    );
  }

  Future<String?> _showChoiceEditor({
    required String title,
    required String currentValue,
    required List<(String, String)> choices,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                for (final choice in choices)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      choice.$1 == currentValue
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: _ProfileColors.green,
                    ),
                    title: Text(choice.$2),
                    onTap: () => Navigator.of(context).pop(choice.$1),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveProfile(OnboardingProfile profile) async {
    if (_isSaving) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      await _repository.saveProfile(session: widget.session, profile: profile);
      if (!mounted) {
        return;
      }
      setState(() {
        _profileFuture = Future.value(profile);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ProfileColors.backgroundFor(context),
      body: SafeArea(
        child: FutureBuilder<OnboardingProfile>(
          future: _profileFuture,
          builder: (context, snapshot) {
            final profile = snapshot.data ?? const OnboardingProfile();
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _Header(onBack: _close)),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _LoadError(
                      message: snapshot.error.toString(),
                      onRetry: _retry,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                    sliver: SliverList.list(
                      children: [
                        _IdentityCard(profile: profile),
                        const SizedBox(height: 18),
                        const _SectionLabel('ABOUT YOU'),
                        const SizedBox(height: 8),
                        _DetailsGroup(
                          rows: [
                            _ProfileDetail(
                              icon: CupertinoIcons.person_2_fill,
                              label: 'Gender',
                              value: _genderLabel(snapshot.data?.gender),
                            ),
                            _ProfileDetail(
                              icon: Icons.hiking_rounded,
                              label: 'Hiking experience',
                              value: _experienceLabel(
                                snapshot.data?.hikerExperience,
                              ),
                              onEdit: _isSaving
                                  ? null
                                  : () => _editExperience(profile),
                            ),
                            _ProfileDetail(
                              icon: CupertinoIcons.calendar,
                              label: 'Hike frequency',
                              value: _frequencyLabel(
                                snapshot.data?.hikeFrequency,
                              ),
                              onEdit: _isSaving
                                  ? null
                                  : () => _editFrequency(profile),
                            ),
                            _ProfileDetail(
                              icon: CupertinoIcons.location_solid,
                              label: 'Residential city',
                              value: _displayValue(
                                snapshot.data?.residentialLocation,
                              ),
                              onEdit: _isSaving
                                  ? null
                                  : () => _editResidentialCity(profile),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const _SectionLabel('ACCOUNT'),
                        const SizedBox(height: 8),
                        _DetailsGroup(
                          rows: [
                            _ProfileDetail(
                              icon: CupertinoIcons.phone_fill,
                              label: 'Phone number',
                              value: widget.session.phoneNumber,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _close() {
    Navigator.of(context).pop();
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(38),
            onPressed: onBack,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _ProfileColors.surfaceFor(context),
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(
                dimension: 38,
                child: Icon(
                  CupertinoIcons.chevron_back,
                  color: _ProfileColors.green,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Personal Profile',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: _ProfileColors.textFor(context),
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.profile});

  final OnboardingProfile profile;

  @override
  Widget build(BuildContext context) {
    final username = profile.username.trim().isEmpty
        ? 'Trail Friend'
        : profile.username.trim();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _ProfileColors.heroGradientFor(context),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x243F8F5E),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.36),
                width: 2,
              ),
            ),
            child: const Icon(
              CupertinoIcons.person_fill,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _ProfileColors.secondaryTextFor(context),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _DetailsGroup extends StatelessWidget {
  const _DetailsGroup({required this.rows});

  final List<_ProfileDetail> rows;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: _ProfileColors.surfaceFor(context),
        child: Column(
          children: [
            for (var index = 0; index < rows.length; index++) ...[
              _DetailRow(detail: rows[index]),
              if (index != rows.length - 1)
                Divider(
                  height: 1,
                  indent: 58,
                  color: _ProfileColors.separatorFor(context),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileDetail {
  const _ProfileDetail({
    required this.icon,
    required this.label,
    required this.value,
    this.onEdit,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onEdit;
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.detail});

  final _ProfileDetail detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _ProfileColors.greenSoftFor(context),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(detail.icon, color: _ProfileColors.green, size: 18),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _ProfileColors.secondaryTextFor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail.value,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _ProfileColors.textFor(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (detail.onEdit != null) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: detail.onEdit,
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Edit'),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Unable to load profile',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

String _displayValue(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? 'Not provided' : trimmed;
}

String _genderLabel(String? value) {
  return switch (value) {
    'male' => 'Male',
    'female' => 'Female',
    'non_binary' => 'Non-binary',
    'prefer_not_to_say' => 'Prefer not to say',
    _ => _displayValue(value),
  };
}

String _experienceLabel(String? value) {
  return switch (value) {
    'new' => 'New hiker',
    'experienced' => 'Experienced hiker',
    _ => _displayValue(value),
  };
}

String _frequencyLabel(String? value) {
  return switch (value) {
    'rarely' => 'A few times a year',
    'monthly' => 'About once a month',
    'several_times_monthly' => 'Several times a month',
    'weekly' => 'Weekly or more',
    _ => _displayValue(value),
  };
}

abstract final class _ProfileColors {
  static const green = Color(0xFF3F8F5E);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : const Color(0xFFF2F2F7);

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : const Color(0xFF111111);

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : const Color(0xFF6E6E73);

  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : const Color(0xFFE3E7E4);

  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : const Color(0xFFEAF7EE);

  static List<Color> heroGradientFor(BuildContext context) => isDark(context)
      ? const [Color(0xFF183625), Color(0xFF24573A)]
      : const [Color(0xFF3F8F5E), Color(0xFF2F7450)];
}
