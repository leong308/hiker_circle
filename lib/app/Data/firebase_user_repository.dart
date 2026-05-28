import 'package:cloud_firestore/cloud_firestore.dart';

import '../Model/app_session.dart';
import 'firebase_bootstrap.dart';

class FirebaseUserRepositoryException implements Exception {
  const FirebaseUserRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FirebaseUserRepository {
  FirebaseUserRepository({
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

  Future<AppSession> registerOrLoadUser(AppSession session) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      throw FirebaseUserRepositoryException(
        'Firebase is not ready yet. ${_firebaseBootstrapResult.errorMessage ?? ''}'
            .trim(),
      );
    }

    try {
      final now = DateTime.now().toUtc();
      final userDocument = _users.doc(
        _documentIdForPhoneNumber(session.phoneNumber),
      );

      return _resolvedFirestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(userDocument);
        if (!snapshot.exists) {
          transaction.set(userDocument, {
            'phoneNumber': session.phoneNumber,
            'createdAt': FieldValue.serverTimestamp(),
            'createdAtLocal': now.toIso8601String(),
            'lastSignedInAt': FieldValue.serverTimestamp(),
            'lastSignedInAtLocal': now.toIso8601String(),
          });

          return session.copyWith(createdAt: now, signedInAt: now);
        }

        final data = snapshot.data();
        final createdAt =
            _dateFromValue(data?['createdAt']) ??
            _dateFromValue(data?['createdAtLocal']) ??
            now;

        transaction.set(userDocument, {
          'phoneNumber': session.phoneNumber,
          'lastSignedInAt': FieldValue.serverTimestamp(),
          'lastSignedInAtLocal': now.toIso8601String(),
        }, SetOptions(merge: true));

        return session.copyWith(createdAt: createdAt, signedInAt: now);
      });
    } on FirebaseException catch (error) {
      throw FirebaseUserRepositoryException(
        'Firestore ${error.code}: ${error.message ?? 'No details provided.'}',
      );
    }
  }

  String _documentIdForPhoneNumber(String phoneNumber) {
    return phoneNumber.replaceAll('/', '_');
  }

  DateTime? _dateFromValue(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
