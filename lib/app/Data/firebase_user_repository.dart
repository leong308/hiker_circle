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

  static String documentIdForPhoneNumber(String phoneNumber) {
    return phoneNumber.replaceAll('/', '_');
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
        documentIdForPhoneNumber(session.phoneNumber),
      );

      return _resolvedFirestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(userDocument);
        final appInstanceId = session.appInstanceId;
        if (!snapshot.exists) {
          transaction.set(userDocument, {
            'phoneNumber': session.phoneNumber,
            'boundAppInstanceId': appInstanceId,
            'boundAppInstanceUpdatedAtLocal': now.toIso8601String(),
            'createdAt': FieldValue.serverTimestamp(),
            'createdAtLocal': now.toIso8601String(),
            'lastSignedInAt': FieldValue.serverTimestamp(),
            'lastSignedInAtLocal': now.toIso8601String(),
          });

          return session.copyWith(
            createdAt: now,
            signedInAt: now,
            appInstanceId: appInstanceId,
          );
        }

        final data = snapshot.data();
        final createdAt =
            _dateFromValue(data?['createdAt']) ??
            _dateFromValue(data?['createdAtLocal']) ??
            now;
        final existingAppInstanceId = _stringFrom(data?['boundAppInstanceId']);
        final isRebinding =
            appInstanceId.isNotEmpty &&
            existingAppInstanceId.isNotEmpty &&
            existingAppInstanceId != appInstanceId;

        transaction.set(userDocument, {
          'phoneNumber': session.phoneNumber,
          'boundAppInstanceId': appInstanceId,
          'boundAppInstanceUpdatedAt': FieldValue.serverTimestamp(),
          'boundAppInstanceUpdatedAtLocal': now.toIso8601String(),
          if (isRebinding) ...{
            'previousBoundAppInstanceId': existingAppInstanceId,
            'deviceReboundAt': FieldValue.serverTimestamp(),
            'deviceReboundAtLocal': now.toIso8601String(),
            'deviceRebindVerifiedBy': 'whatsapp_otp',
          },
          'lastSignedInAt': FieldValue.serverTimestamp(),
          'lastSignedInAtLocal': now.toIso8601String(),
        }, SetOptions(merge: true));

        return session.copyWith(
          createdAt: createdAt,
          signedInAt: now,
          appInstanceId: appInstanceId,
          isAdmin: _isAdmin(data),
        );
      });
    } on FirebaseException catch (error) {
      throw FirebaseUserRepositoryException(
        'Firestore ${error.code}: ${error.message ?? 'No details provided.'}',
      );
    }
  }

  Future<AppSession> refreshBoundSession(AppSession session) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return session;
    }

    try {
      final snapshot = await _users
          .doc(documentIdForPhoneNumber(session.phoneNumber))
          .get();
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        return session;
      }

      final boundAppInstanceId = _stringFrom(data['boundAppInstanceId']);
      if (boundAppInstanceId.isNotEmpty &&
          session.appInstanceId.isNotEmpty &&
          boundAppInstanceId != session.appInstanceId) {
        throw const FirebaseUserRepositoryException(
          'This account is now bound to another phone. Request a new WhatsApp code to use it here again.',
        );
      }

      return session.copyWith(isAdmin: _isAdmin(data));
    } on FirebaseUserRepositoryException {
      rethrow;
    } on FirebaseException catch (error) {
      throw FirebaseUserRepositoryException(
        'Firestore ${error.code}: ${error.message ?? 'No details provided.'}',
      );
    }
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

  bool _isAdmin(Map<String, dynamic>? data) {
    if (data == null) {
      return false;
    }
    final role = _stringFrom(data['role']).toLowerCase();
    final roles = data['roles'];
    return data['isAdmin'] == true ||
        role == 'admin' ||
        role == 'super_admin' ||
        (roles is Iterable &&
            roles.any((value) => _stringFrom(value).toLowerCase() == 'admin'));
  }

  String _stringFrom(Object? value) {
    return value is String ? value : '';
  }
}
