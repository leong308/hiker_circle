import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../authentication/Model/password_validator.dart';
import '../Data/google_city_geocoding_service.dart';
import '../Model/onboarding_profile.dart';
import 'residential_city_picker_page.dart';

class OnboardingProfilePage extends StatefulWidget {
  const OnboardingProfilePage({
    super.key,
    required this.initialProfile,
    required this.onSubmit,
  });

  final OnboardingProfile initialProfile;
  final Future<void> Function(OnboardingProfile profile) onSubmit;

  @override
  State<OnboardingProfilePage> createState() => _OnboardingProfilePageState();
}

class _OnboardingProfilePageState extends State<OnboardingProfilePage> {
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
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(
      text: widget.initialProfile.username,
    );
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _gender = widget.initialProfile.gender.isEmpty
        ? null
        : widget.initialProfile.gender;
    _hikerExperience = widget.initialProfile.hikerExperience.isEmpty
        ? null
        : widget.initialProfile.hikerExperience;
    _hikeFrequency = widget.initialProfile.hikeFrequency.isEmpty
        ? null
        : widget.initialProfile.hikeFrequency;
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
        await functions.httpsCallable('linkPasswordToAccount').call({
          'password': _passwordController.text,
          'username': _usernameController.text.trim(),
        });
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'not-found') {
          throw Exception(
            'Password setup function is not deployed. '
            'Run: firebase deploy --only functions',
          );
        }
        rethrow;
      }
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
  Widget build(BuildContext context) {
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
                        'Step 1 of 2. These details are required before you can use HikerCircle.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _usernameController,
                        enabled: !_isSaving,
                        textInputAction: TextInputAction.next,
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
                          if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(username)) {
                            return 'Use only letters, numbers, and underscores.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        enabled: !_isSaving,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.key),
                        ),
                        validator: (value) {
                          final result = PasswordValidator.validate(value ?? '');
                          return result.isValid ? null : result.errorMessage;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: true,
                        enabled: !_isSaving,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: Icon(Icons.key),
                        ),
                        validator: (value) {
                          if (value != _passwordController.text) {
                            return 'Passwords do not match.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
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
                                  child: CircularProgressIndicator(
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
