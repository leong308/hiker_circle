import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Model/app_session.dart';
import '../../sos/Data/emergency_contacts_repository.dart';
import '../../sos/Model/sos_models.dart';
import '../../sos/View/emergency_contacts_page.dart';
import '../Data/onboarding_repository.dart';
import '../Model/onboarding_profile.dart';
import 'onboarding_profile_page.dart';

class FirstTimeOnboardingFlow extends StatefulWidget {
  const FirstTimeOnboardingFlow({
    super.key,
    required this.session,
    required this.onCompleted,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final AppSession session;
  final Future<void> Function() onCompleted;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  @override
  State<FirstTimeOnboardingFlow> createState() => _FirstTimeOnboardingFlowState();
}

class _FirstTimeOnboardingFlowState extends State<FirstTimeOnboardingFlow> {
  late final OnboardingRepository _onboardingRepository;
  late final EmergencyContactsRepository _contactsRepository;
  OnboardingProfile _profile = const OnboardingProfile();
  List<EmergencyContact> _contacts = const [];
  late bool _profileComplete;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _profileComplete = widget.session.isOnboardingProfileComplete;
    _onboardingRepository = OnboardingRepository(firebaseBootstrapResult: widget.firebaseBootstrapResult);
    _contactsRepository = EmergencyContactsRepository(firebaseBootstrapResult: widget.firebaseBootstrapResult);
    unawaited(_loadSavedProgress());
  }

  Future<void> _loadSavedProgress() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait<Object>([
        _onboardingRepository.loadProfile(widget.session),
        _contactsRepository.loadEmergencyContacts(session: widget.session),
      ]);
      if (!mounted) {
        return;
      }
      final profile = results[0] as OnboardingProfile;
      setState(() {
        _profile = profile;
        _profileComplete = _profileComplete && profile.isComplete;
        _contacts = results[1] as List<EmergencyContact>;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _saveProfile(OnboardingProfile profile) async {
    await _onboardingRepository.saveProfile(session: widget.session, profile: profile);
    if (!mounted) {
      return;
    }
    setState(() {
      _profile = profile;
      _profileComplete = true;
    });
  }

  Future<void> _complete(List<EmergencyContact> contacts) async {
    await _contactsRepository.saveEmergencyContacts(session: widget.session, contacts: contacts);
    await _onboardingRepository.completeOnboarding(widget.session);
    _contacts = contacts;
    await widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 48),
                    const SizedBox(height: 14),
                    const Text('Unable to load account setup', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    FilledButton(onPressed: _loadSavedProgress, child: const Text('Try again')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (!_profileComplete) {
      return OnboardingProfilePage(initialProfile: _profile, onSubmit: _saveProfile);
    }
    return EmergencyContactsPage(
      session: widget.session,
      initialContacts: _contacts,
      repository: _contactsRepository,
      onboardingRequired: true,
      onOnboardingCompleted: _complete,
    );
  }
}
