// OnboardingProfilePage collects profile identity, hiking preferences and residential city.
import '../../authentication/Data/multi_factor_auth_service.dart';
import '../../authentication/View/recent_security_verification_page.dart';
import '../../core/widgets/password_capture_protection.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../authentication/Model/password_validator.dart';
import '../../core/widgets/loading_toast.dart';
import '../Data/google_city_geocoding_service.dart';
import '../Model/onboarding_profile.dart';
import 'residential_city_picker_page.dart';

class OnboardingProfilePage extends StatefulWidget {
  const OnboardingProfilePage({
    super.key,
    required this.initialProfile,
    required this.onSubmit,
    this.initialPasswordConfigured,
  });

  final OnboardingProfile initialProfile;
  final Future<void> Function(OnboardingProfile profile) onSubmit;
  final bool? initialPasswordConfigured;

  @override
  State<OnboardingProfilePage> createState() => _OnboardingProfilePageState();
}

class _OnboardingProfilePageState extends State<OnboardingProfilePage> {
  static const _genderValues = {
    'male',
    'female',
    'non_binary',
    'prefer_not_to_say',
  };
  static const _experienceValues = {'new', 'experienced'};
  static const _frequencyValues = {
    'rarely',
    'monthly',
    'several_times_monthly',
    'weekly',
  };
  final _formKey = GlobalKey<FormState>();
  final _residentialCityFieldKey =
      GlobalKey<FormFieldState<ResidentialCitySelection>>();
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _confirmPasswordController;
  String? _gender;
  String? _hikerExperience;
  String? _hikeFrequency;
  ResidentialCitySelection? _residentialCity;
  bool _isSaving = false;
  bool? _passwordConfigured;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(
      text: widget.initialProfile.username,
    );
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _passwordConfigured = widget.initialPasswordConfigured;
    if (_passwordConfigured == null) _loadPasswordSetupStatus();
    _gender = _normalizedChoice(
      widget.initialProfile.gender,
      _genderValues,
      aliases: const {
        'non-binary': 'non_binary',
        'prefer not to say': 'prefer_not_to_say',
      },
    );
    _hikerExperience = _normalizedChoice(
      widget.initialProfile.hikerExperience,
      _experienceValues,
      aliases: const {'new hiker': 'new', 'experienced hiker': 'experienced'},
    );
    _hikeFrequency = _normalizedChoice(
      widget.initialProfile.hikeFrequency,
      _frequencyValues,
      aliases: const {
        'a few times a year': 'rarely',
        'about once a month': 'monthly',
        'several times a month': 'several_times_monthly',
        'weekly or more': 'weekly',
      },
    );
    final latitude = widget.initialProfile.residentialLatitude;
    final longitude = widget.initialProfile.residentialLongitude;
    if (widget.initialProfile.residentialLocation.isNotEmpty &&
        latitude != null &&
        longitude != null) {
      _residentialCity = ResidentialCitySelection(
        city: widget.initialProfile.residentialLocation,
        state: '',
        country: '',
        latitude: latitude,
        longitude: longitude,
      );
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadPasswordSetupStatus() async {
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('getPasswordSetupStatus')
          .call();
      if (mounted) {
        setState(
          () => _passwordConfigured =
              (response.data as Map)['configured'] == true,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Unable to check password setup. Reopen this page to retry.',
        );
      }
    }
  }

  Future<void> _chooseResidentialCity() async {
    if (_isSaving) {
      return;
    }
    final selection = await Navigator.of(context)
        .push<ResidentialCitySelection>(
          MaterialPageRoute<ResidentialCitySelection>(
            builder: (context) => ResidentialCityPickerPage(
              initialLatitude: _residentialCity?.latitude,
              initialLongitude: _residentialCity?.longitude,
            ),
          ),
        );
    if (selection == null || !mounted) {
      return;
    }
    setState(() {
      _residentialCity = selection;
      _errorMessage = null;
    });
    _residentialCityFieldKey.currentState
      ?..didChange(selection)
      ..validate();
  }

  Future<void> _submit() async {
    if (_isSaving || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final functions = FirebaseFunctions.instance;
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        throw Exception('You must be signed in to set a password.');
      }
      try {
        if (_passwordConfigured != true) {
          await functions.httpsCallable('linkPasswordToAccount').call({
            'password': _passwordController.text,
            'username': _usernameController.text.trim(),
          });
        }
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'not-found') {
          throw Exception(
            'Password setup function is not deployed. '
            'Run: firebase deploy --only functions',
          );
        }
        rethrow;
      }
      _passwordConfigured = true;
      _passwordController.clear();
      _confirmPasswordController.clear();
      await widget.onSubmit(
        OnboardingProfile(
          username: _usernameController.text,
          gender: _gender!,
          hikerExperience: _hikerExperience!,
          hikeFrequency: _hikeFrequency!,
          residentialLocation: _residentialCity!.label,
          residentialLatitude: _residentialCity!.latitude,
          residentialLongitude: _residentialCity!.longitude,
        ),
      );
    } catch (error) {
      if (mounted && requiresRecentMfaAuthentication(error)) {
        final phone = await MultiFactorAuthService().authenticatedPhoneNumber();
        if (!mounted) return;
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => RecentSecurityVerificationPage(phoneNumber: phone),
          ),
        );
      }
      if (mounted) {
        setState(() {
          _errorMessage = _friendlyError(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String _friendlyError(Object error) {
    if (error is FirebaseFunctionsException) {
      return error.message ?? 'Password setup failed. Please try again.';
    }
    return error.toString();
  }

  @override
  Widget build(BuildContext context) =>
      PasswordCaptureProtection(child: _buildPasswordPage(context));

  Widget _buildPasswordPage(BuildContext context) {
    if (_passwordConfigured == null) {
      return Scaffold(
        body: Center(
          child: _errorMessage == null
              ? const CircularProgressIndicator()
              : TextButton(
                  onPressed: _loadPasswordSetupStatus,
                  child: Text(_errorMessage!),
                ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.account_circle_rounded,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Set up your profile',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Step 1 of 3. These details are required before you can use HikerCircle.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _usernameController,
                        enabled: !_isSaving,
                        textInputAction: TextInputAction.next,
                        maxLength: 24,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          hintText: 'e.g. trailwalker',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                        ),
                        validator: (value) {
                          final username = value?.trim() ?? '';
                          if (username.length < 3) {
                            return 'Username must contain at least 3 characters.';
                          }
                          if (username.length > 24) {
                            return 'Username must contain 24 characters or fewer.';
                          }
                          if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(username)) {
                            return 'Use only letters, numbers, and underscores.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      if (_passwordConfigured != true) ...[
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          enabled: !_isSaving,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.key),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: _isSaving
                                  ? null
                                  : () {
                                      setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      );
                                    },
                            ),
                          ),
                          validator: (value) {
                            final result = PasswordValidator.validate(
                              value ?? '',
                            );
                            return result.isValid ? null : result.errorMessage;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          enabled: !_isSaving,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: const Icon(Icons.key),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              tooltip: _obscureConfirmPassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: _isSaving
                                  ? null
                                  : () {
                                      setState(
                                        () => _obscureConfirmPassword =
                                            !_obscureConfirmPassword,
                                      );
                                    },
                            ),
                          ),
                          validator: (value) {
                            if (value != _passwordController.text) {
                              return 'Passwords do not match.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                      ],
                      DropdownButtonFormField<String>(
                        initialValue: _gender,
                        decoration: const InputDecoration(
                          labelText: 'Gender',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'male', child: Text('Male')),
                          DropdownMenuItem(
                            value: 'female',
                            child: Text('Female'),
                          ),
                          DropdownMenuItem(
                            value: 'non_binary',
                            child: Text('Non-binary'),
                          ),
                          DropdownMenuItem(
                            value: 'prefer_not_to_say',
                            child: Text('Prefer not to say'),
                          ),
                        ],
                        onChanged: _isSaving
                            ? null
                            : (value) => setState(() => _gender = value),
                        validator: (value) => value == null
                            ? 'Select your gender to continue.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: _hikerExperience,
                        decoration: const InputDecoration(
                          labelText: 'Hiking experience',
                          prefixIcon: Icon(Icons.hiking_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'new',
                            child: Text('New hiker'),
                          ),
                          DropdownMenuItem(
                            value: 'experienced',
                            child: Text('Experienced hiker'),
                          ),
                        ],
                        onChanged: _isSaving
                            ? null
                            : (value) =>
                                  setState(() => _hikerExperience = value),
                        validator: (value) => value == null
                            ? 'Select your hiking experience.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: _hikeFrequency,
                        decoration: const InputDecoration(
                          labelText: 'Hike frequency',
                          prefixIcon: Icon(Icons.calendar_month_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'rarely',
                            child: Text('A few times a year'),
                          ),
                          DropdownMenuItem(
                            value: 'monthly',
                            child: Text('About once a month'),
                          ),
                          DropdownMenuItem(
                            value: 'several_times_monthly',
                            child: Text('Several times a month'),
                          ),
                          DropdownMenuItem(
                            value: 'weekly',
                            child: Text('Weekly or more'),
                          ),
                        ],
                        onChanged: _isSaving
                            ? null
                            : (value) => setState(() => _hikeFrequency = value),
                        validator: (value) => value == null
                            ? 'Select how frequently you hike.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      FormField<ResidentialCitySelection>(
                        key: _residentialCityFieldKey,
                        initialValue: _residentialCity,
                        validator: (_) => _residentialCity == null
                            ? 'Choose your residential city on the map.'
                            : null,
                        builder: (field) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: _isSaving
                                    ? null
                                    : _chooseResidentialCity,
                                borderRadius: BorderRadius.circular(8),
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Residential city',
                                    prefixIcon: const Icon(
                                      Icons.location_city_rounded,
                                    ),
                                    suffixIcon: const Icon(Icons.map_outlined),
                                    errorText: field.errorText,
                                  ),
                                  child: Text(
                                    _residentialCity?.label ??
                                        'Tap to choose on map',
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(
                                          color: _residentialCity == null
                                              ? Theme.of(context).hintColor
                                              : null,
                                        ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Only city-level location is stored, not your exact address.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          );
                        },
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _isSaving ? null : _submit,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          child: _isSaving
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: HikerCircleMinorLoadingIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Continue to emergency contacts'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _normalizedChoice(
  String raw,
  Set<String> allowed, {
  Map<String, String> aliases = const {},
}) {
  final normalized = raw.trim().toLowerCase();
  if (allowed.contains(normalized)) {
    return normalized;
  }
  final alias = aliases[normalized];
  return alias != null && allowed.contains(alias) ? alias : null;
}
