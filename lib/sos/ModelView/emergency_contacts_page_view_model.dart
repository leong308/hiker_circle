part of '../emergency_contacts_page_feature.dart';

/// Owns the state and non-visual actions of EmergencyContactsPage.
class _EmergencyContactsPageStateViewModel extends ChangeNotifier {
  /// Creates emergency contacts page state view model.
  _EmergencyContactsPageStateViewModel({
    required this.effectPickDeviceContact,
    required this.effectSelectDeviceContact,
  });
  final Future<EmergencyContactCandidate?> Function({
    EmergencyContact? excluding,
  })
  effectPickDeviceContact;
  final void Function(EmergencyContactCandidate contact)
  effectSelectDeviceContact;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  /// Refreshes.
  void commandRefresh() {
    if (mounted) {
      _publish(() {});
    }
  }

  /// Import only the device contact explicitly selected by the hiker.
  Future<void> commandImportDeviceContact() async {
    final contact = await effectPickDeviceContact();
    if (contact != null && mounted) effectSelectDeviceContact(contact);
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final bool Function() readOnboardingRequired;

  late final Future<void> Function(List<EmergencyContact> contacts)? Function()
  readOnOnboardingCompleted;

  late final void Function() effectPresentCloseEffect1;

  late final Future<EmergencyContact?> Function(EmergencyContact contact)
  effectPresentEditContactEffect1;

  late final Future<bool?> Function(EmergencyContact contact)
  effectPresentDeleteContactEffect1;

  late final EmergencyContactsViewModel stateViewModel;

  bool stateIsCompletingOnboarding = false;

  String? stateOnboardingErrorMessage;

  /// Finish the contact editor through its result flow instead of abandoning the current save state.
  Future<void> commandClose() async {
    if (stateViewModel.isSaving) return;
    if (!readOnboardingRequired()) {
      effectPresentCloseEffect1();
      return;
    }
    if (stateViewModel.contacts.isEmpty ||
        stateViewModel.isSaving ||
        stateIsCompletingOnboarding) {
      return;
    }

    _publish(() {
      stateIsCompletingOnboarding = true;
      stateOnboardingErrorMessage = null;
    });
    try {
      await readOnOnboardingCompleted()?.call(stateViewModel.contacts);
    } catch (error) {
      if (mounted) {
        _publish(() {
          stateOnboardingErrorMessage = error.toString();
        });
      }
    } finally {
      if (mounted) {
        _publish(() {
          stateIsCompletingOnboarding = false;
        });
      }
    }
  }

  /// Computes edit contact.
  Future<void> commandEditContact(int index, EmergencyContact contact) async {
    if (stateViewModel.isSaving) {
      return;
    }

    final updatedContact = await effectPresentEditContactEffect1(contact);

    if (updatedContact == null || !mounted) {
      return;
    }

    await stateViewModel.updateContact(
      index,
      name: updatedContact.name,
      phoneNumber: updatedContact.phoneNumber,
      relationship: updatedContact.relationship,
    );
  }

  /// Deletes contact.
  Future<void> commandDeleteContact(int index, EmergencyContact contact) async {
    if (stateViewModel.isSaving) {
      return;
    }

    final shouldDelete = await effectPresentDeleteContactEffect1(contact);

    if (shouldDelete == true) {
      await stateViewModel.deleteContact(index);
    }
  }
}
