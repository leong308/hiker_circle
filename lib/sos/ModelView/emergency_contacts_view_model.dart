import 'package:flutter/foundation.dart';

import '../Model/sos_models.dart';

class EmergencyContactsViewModel extends ChangeNotifier {
  EmergencyContactsViewModel({
    List<EmergencyContact> initialContacts = const [],
  }) : _contacts = List.of(initialContacts);

  static const int maxContacts = 5;

  final List<EmergencyContact> _contacts;

  List<EmergencyContact> get contacts => List.unmodifiable(_contacts);
  int get remainingSlots => maxContacts - _contacts.length;
  bool get canAddContact => _contacts.length < maxContacts;

  bool addContact({
    required String name,
    required String phoneNumber,
    required String relationship,
  }) {
    if (!canAddContact) {
      return false;
    }

    _contacts.add(
      EmergencyContact(
        name: name.trim(),
        phoneNumber: phoneNumber.trim(),
        relationship: relationship.trim(),
      ),
    );
    notifyListeners();
    return true;
  }

  void updateContact(
    int index, {
    required String name,
    required String phoneNumber,
    required String relationship,
  }) {
    if (index < 0 || index >= _contacts.length) {
      return;
    }

    _contacts[index] = EmergencyContact(
      name: name.trim(),
      phoneNumber: phoneNumber.trim(),
      relationship: relationship.trim(),
    );
    notifyListeners();
  }

  void deleteContact(int index) {
    if (index < 0 || index >= _contacts.length) {
      return;
    }

    _contacts.removeAt(index);
    notifyListeners();
  }
}
