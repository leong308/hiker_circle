import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/firebase_user_repository.dart';
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
    FirebaseBootstrapResult firebaseBootstrapResult =
        const FirebaseBootstrapResult.available(),
  }) : _firestore = firestore,
       _firebaseBootstrapResult = firebaseBootstrapResult;

  final FirebaseFirestore? _firestore;
  final FirebaseBootstrapResult _firebaseBootstrapResult;

  FirebaseFirestore get _resolvedFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users {
    return _resolvedFirestore.collection('users');
  }

  Future<List<EmergencyContact>> loadEmergencyContacts({
    required AppSession session,
  }) async {
    _throwIfFirebaseUnavailable();

    try {
      final snapshot = await _userDocumentFor(session).get();
      final data = snapshot.data();
      final rawContacts = data?['sos_contacts'];
      if (rawContacts is! Iterable) {
        return const [];
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

      return contacts;
    } on FirebaseException catch (error) {
      throw EmergencyContactsRepositoryException(
        'Firestore ${error.code}: ${error.message ?? 'No details provided.'}',
      );
    }
  }

  Future<void> saveEmergencyContacts({
    required AppSession session,
    required List<EmergencyContact> contacts,
  }) async {
    _throwIfFirebaseUnavailable();

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
        'Firestore ${error.code}: ${error.message ?? 'No details provided.'}',
      );
    }
  }

  DocumentReference<Map<String, dynamic>> _userDocumentFor(AppSession session) {
    return _users.doc(
      FirebaseUserRepository.documentIdForPhoneNumber(session.phoneNumber),
    );
  }

  void _throwIfFirebaseUnavailable() {
    if (_firebaseBootstrapResult.isAvailable) {
      return;
    }

    throw EmergencyContactsRepositoryException(
      'Firebase is not ready yet. ${_firebaseBootstrapResult.errorMessage ?? ''}'
          .trim(),
    );
  }
}
