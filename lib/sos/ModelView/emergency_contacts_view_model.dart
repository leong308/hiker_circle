import 'package:flutter/foundation.dart';

import '../../app/Model/app_session.dart';
import '../../authentication/Data/phone_number_formatter.dart';
import '../Data/emergency_contacts_repository.dart';
import '../Model/sos_models.dart';

class EmergencyContactsViewModel extends ChangeNotifier {
  EmergencyContactsViewModel({
    required AppSession session,
    List<EmergencyContact> initialContacts = const [],
    EmergencyContactsRepository repository =
        const EmergencyContactsRepository(),
  }) : _session = session,
       _repository = repository,
       _contacts = List.of(initialContacts);

  static const int maxContacts = EmergencyContactsRepository.maxContacts;

  final AppSession _session;
  final EmergencyContactsRepository _repository;
  final List<EmergencyContact> _contacts;
  bool _isSaving = false;
  String? _saveErrorMessage;
  bool _isDisposed = false;

  List<EmergencyContact> get contacts => List.unmodifiable(_contacts);
  int get remainingSlots => maxContacts - _contacts.length;
  bool get canAddContact => _contacts.length < maxContacts;
  bool get isSaving => _isSaving;
  String? get saveErrorMessage => _saveErrorMessage;

  Future<bool> addContact({
    required String name,
    required String phoneNumber,
    required String relationship,
  }) async {
    if (!canAddContact || _isSaving) {
      return false;
    }

    final normalizedPhoneNumber = _normalizedPhoneNumber(phoneNumber);
    if (normalizedPhoneNumber == null) {
      return false;
    }
    if (name.trim().isEmpty) {
      _saveErrorMessage = 'Enter a name for this emergency contact.';
      notifyListeners();
      return false;
    }
    if (_contacts.any(
      (contact) => contact.phoneNumber == normalizedPhoneNumber,
    )) {
      _saveErrorMessage = 'This emergency contact is already saved.';
      notifyListeners();
      return false;
    }

    _contacts.add(
      EmergencyContact(
        name: name.trim(),
        phoneNumber: normalizedPhoneNumber,
        relationship: relationship.trim(),
      ),
    );
    notifyListeners();
    await _saveContacts();
    return true;
  }

  Future<void> updateContact(
    int index, {
    required String name,
    required String phoneNumber,
    required String relationship,
  }) async {
    if (index < 0 || index >= _contacts.length || _isSaving) {
      return;
    }

    final normalizedPhoneNumber = _normalizedPhoneNumber(phoneNumber);
    if (normalizedPhoneNumber == null) {
      return;
    }
    if (name.trim().isEmpty) {
      _saveErrorMessage = 'Enter a name for this emergency contact.';
      notifyListeners();
      return;
    }
    if (_contacts.indexed.any(
      (entry) =>
          entry.$1 != index && entry.$2.phoneNumber == normalizedPhoneNumber,
    )) {
      _saveErrorMessage = 'This emergency contact is already saved.';
      notifyListeners();
      return;
    }

    _contacts[index] = EmergencyContact(
      name: name.trim(),
      phoneNumber: normalizedPhoneNumber,
      relationship: relationship.trim(),
    );
    notifyListeners();
    await _saveContacts();
  }

  Future<void> deleteContact(int index) async {
    if (index < 0 || index >= _contacts.length || _isSaving) {
      return;
    }

    _contacts.removeAt(index);
    notifyListeners();
    await _saveContacts();
  }

  Future<void> _saveContacts() async {
    _isSaving = true;
    _saveErrorMessage = null;
    notifyListeners();

    try {
      await _repository.saveEmergencyContacts(
        session: _session,
        contacts: contacts,
      );
    } on EmergencyContactsRepositoryException catch (error) {
      _saveErrorMessage = error.message;
    } catch (_) {
      _saveErrorMessage =
          'Unable to save emergency contacts. Please check your connection and try again.';
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  String? _normalizedPhoneNumber(String phoneNumber) {
    if (!PhoneNumberFormatter.isValid(phoneNumber)) {
      _saveErrorMessage =
          'Enter a phone number with country code, for example +60123456789.';
      notifyListeners();
      return null;
    }
    final normalized = PhoneNumberFormatter.normalize(phoneNumber);
    if (EmergencyContactsRepository.isOwnPhoneNumber(
      normalized,
      _session.phoneNumber,
    )) {
      _saveErrorMessage = EmergencyContactsRepository.ownNumberMessage;
      notifyListeners();
      return null;
    }
    _saveErrorMessage = null;
    return normalized;
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
