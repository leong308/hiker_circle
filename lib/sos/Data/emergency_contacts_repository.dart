import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/firebase_user_repository.dart';
import '../../app/Data/local_session_database.dart';
import '../../app/Model/app_session.dart';
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

  Future<List<EmergencyContact>> loadEmergencyContacts({
    required AppSession session,
  }) async {
    final localContacts = await _resolvedLocalDatabase.loadEmergencyContacts(
      phoneNumber: session.phoneNumber,
    );
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
          contacts.add(
            EmergencyContact.fromFirestore(
              Map<String, dynamic>.from(rawContact),
            ),
          );
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
    await _resolvedLocalDatabase.saveEmergencyContacts(
      phoneNumber: session.phoneNumber,
      contacts: contacts,
    );
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }

    try {
      final now = DateTime.now().toUtc();
      final userDocument = _userDocumentFor(session);

      await userDocument.set({
        'sos_contacts': contacts
            .map((contact) => contact.toFirestore())
            .toList(),
        'sosContactsCount': contacts.length,
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
}
