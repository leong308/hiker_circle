import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/firebase_user_repository.dart';
import '../../app/Data/local_session_database.dart';
import '../../app/Model/app_session.dart';
import '../../authentication/Data/phone_number_formatter.dart';
import '../Model/sos_models.dart';

class EmergencyContactsRepositoryException implements Exception {
  const EmergencyContactsRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class EmergencyContactsRepository {
  const EmergencyContactsRepository({
    FirebaseFirestore? firestore,
    LocalSessionDatabase? localDatabase,
    FirebaseBootstrapResult firebaseBootstrapResult =
        const FirebaseBootstrapResult.available(),
  }) : _firestore = firestore,
       _localDatabase = localDatabase,
       _firebaseBootstrapResult = firebaseBootstrapResult;

  static final LocalSessionDatabase _defaultLocalDatabase =
      LocalSessionDatabase();
  static const int maxContacts = 3;

  final FirebaseFirestore? _firestore;
  final LocalSessionDatabase? _localDatabase;
  final FirebaseBootstrapResult _firebaseBootstrapResult;

  FirebaseFirestore get _resolvedFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  LocalSessionDatabase get _resolvedLocalDatabase =>
      _localDatabase ?? _defaultLocalDatabase;

  CollectionReference<Map<String, dynamic>> get _users {
    return _resolvedFirestore.collection('users');
  }

  /// Returns the device copy without waiting for a Firestore round trip.
  /// Emergency dispatch uses this fast path when the SOS screen is still
  /// loading its cloud-refreshed contact list.
  Future<List<EmergencyContact>> loadCachedEmergencyContacts({
    required AppSession session,
  }) async {
    final rawLocalContacts = await _resolvedLocalDatabase.loadEmergencyContacts(
      phoneNumber: session.phoneNumber,
    );
    final localContacts = <EmergencyContact>[];
    for (final contact in rawLocalContacts) {
      final normalized = _validatedContact(contact);
      if (normalized != null &&
          !localContacts.any(
            (saved) => saved.phoneNumber == normalized.phoneNumber,
          ) &&
          localContacts.length < maxContacts) {
        localContacts.add(normalized);
      }
    }
    return localContacts;
  }

  Future<List<EmergencyContact>> loadEmergencyContacts({
    required AppSession session,
  }) async {
    final localContacts = await loadCachedEmergencyContacts(session: session);
    if (!_firebaseBootstrapResult.isAvailable) {
      return localContacts;
    }

    try {
      final snapshot = await _userDocumentFor(session).get();
      final data = snapshot.data();
      final rawContacts = data?['sos_contacts'];
      if (rawContacts is! Iterable) {
        return localContacts;
      }

      final contacts = <EmergencyContact>[];
      for (final rawContact in rawContacts) {
        if (rawContact is Map) {
          final parsed = EmergencyContact.fromFirestore(
            Map<String, dynamic>.from(rawContact),
          );
          final normalized = _validatedContact(parsed);
          if (normalized != null &&
              !contacts.any(
                (contact) => contact.phoneNumber == normalized.phoneNumber,
              ) &&
              contacts.length < maxContacts) {
            contacts.add(normalized);
          }
        }
      }

      if (contacts.isNotEmpty) {
        await _resolvedLocalDatabase.saveEmergencyContacts(
          phoneNumber: session.phoneNumber,
          contacts: contacts,
        );
        return contacts;
      }

      return localContacts;
    } on FirebaseException catch (error) {
      if (localContacts.isNotEmpty) {
        return localContacts;
      }
      throw EmergencyContactsRepositoryException(
        'Cloud sync failed (${error.code}). ${error.message ?? 'Please try again.'}',
      );
    }
  }

  Future<void> saveEmergencyContacts({
    required AppSession session,
    required List<EmergencyContact> contacts,
  }) async {
    if (contacts.length > maxContacts) {
      throw const EmergencyContactsRepositoryException(
        'You can save up to 3 emergency contacts.',
      );
    }
    final normalizedContacts = <EmergencyContact>[];
    for (final contact in contacts) {
      final normalized = _validatedContact(contact);
      if (normalized == null) {
        throw const EmergencyContactsRepositoryException(
          'Each emergency contact needs a name and a valid international phone number.',
        );
      }
      if (normalizedContacts.any(
        (saved) => saved.phoneNumber == normalized.phoneNumber,
      )) {
        throw const EmergencyContactsRepositoryException(
          'Each emergency contact phone number must be unique.',
        );
      }
      normalizedContacts.add(normalized);
    }
    await _resolvedLocalDatabase.saveEmergencyContacts(
      phoneNumber: session.phoneNumber,
      contacts: normalizedContacts,
    );
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }

    try {
      final now = DateTime.now().toUtc();
      final userDocument = _userDocumentFor(session);

      await userDocument.set({
        'sos_contacts': normalizedContacts
            .map((contact) => contact.toFirestore())
            .toList(),
        'sosContactsCount': normalizedContacts.length,
        'sosContactsUpdatedAt': FieldValue.serverTimestamp(),
        'sosContactsUpdatedAtLocal': now.toIso8601String(),
        'phoneNumber': session.phoneNumber,
      }, SetOptions(merge: true));
    } on FirebaseException catch (error) {
      throw EmergencyContactsRepositoryException(
        'Saved on this phone, but cloud sync failed (${error.code}). ${error.message ?? 'Please try again.'}',
      );
    }
  }

  DocumentReference<Map<String, dynamic>> _userDocumentFor(AppSession session) {
    return _users.doc(
      FirebaseUserRepository.documentIdForPhoneNumber(session.phoneNumber),
    );
  }

  static EmergencyContact? _validatedContact(EmergencyContact contact) {
    final name = contact.name.trim();
    final relationship = contact.relationship.trim();
    if (name.isEmpty ||
        name.length > 80 ||
        relationship.length > 80 ||
        !PhoneNumberFormatter.isValid(contact.phoneNumber)) {
      return null;
    }
    return EmergencyContact(
      name: name,
      phoneNumber: PhoneNumberFormatter.normalize(contact.phoneNumber),
      relationship: relationship,
    );
  }
}
