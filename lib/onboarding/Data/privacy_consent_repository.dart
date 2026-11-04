import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../app/Data/firebase_user_repository.dart';
import '../../app/Data/local_session_database.dart';
import '../../app/Data/user_module_paths.dart';
import '../Model/privacy_consent_receipt.dart';

/// Saves the positive action locally before allowing continuation. A network
/// failure leaves a durable receipt for reconnect recovery, never a false decline.
class PrivacyConsentRepository {
  PrivacyConsentRepository({
    LocalSessionDatabase? database,
    FirebaseFirestore? firestore,
    Future<String?> Function()? readOwner,
    Future<void> Function(String, PrivacyConsentReceipt)? writeReceipt,
    DateTime Function()? clock,
  }) : _database = database ?? LocalSessionDatabase(),
       _firestore = firestore,
       _readOwner = readOwner,
       _writeReceipt = writeReceipt,
       _clock = clock ?? DateTime.now;

  final LocalSessionDatabase _database;
  final FirebaseFirestore? _firestore;
  final Future<String?> Function()? _readOwner;
  final Future<void> Function(String, PrivacyConsentReceipt)? _writeReceipt;
  final DateTime Function() _clock;

  Future<PrivacyConsentReceipt?> load(String owner) async =>
      PrivacyConsentReceipt.fromMap(
        await _database.loadLocalPreference(
          ownerPhoneNumber: owner,
          key: PrivacyConsentReceipt.localKey,
        ),
      );

  Future<void> accept(String owner, {required String languageCode}) async {
    if (owner.isEmpty || !const ['en', 'ms'].contains(languageCode)) {
      throw ArgumentError('The consent owner and language must be valid.');
    }
    if (await load(owner) != null) return;
    final receipt = PrivacyConsentReceipt(
      acceptedAt: _clock().toUtc(),
      languageCode: languageCode,
    );
    await _database.saveLocalPreference(
      ownerPhoneNumber: owner,
      key: PrivacyConsentReceipt.localKey,
      value: receipt.toMap(),
      isDirty: true,
    );
  }

  Future<void> flush(String owner) async {
    final dirty = await _database.loadDirtyLocalPreferences(
      ownerPhoneNumber: owner,
    );
    final value = dirty[PrivacyConsentReceipt.localKey];
    final receipt = PrivacyConsentReceipt.fromMap(value);
    if (receipt == null) return;
    final currentOwner = _readOwner;
    if (currentOwner != null) {
      if (await currentOwner() != owner) return;
    } else if (FirebaseAuth.instance.currentUser?.uid !=
        FirebaseUserRepository.documentIdForPhoneNumber(owner)) {
      return;
    }
    final write = _writeReceipt;
    if (write != null) {
      await write(owner, receipt);
    } else {
      final account = (_firestore ?? FirebaseFirestore.instance)
          .collection('users')
          .doc(FirebaseUserRepository.documentIdForPhoneNumber(owner));
      final profile = userModuleDocument(account, UserModule.profile);
      await profile.firestore
          .runTransaction((transaction) async {
            final saved = await transaction.get(profile);
            // An accepted cloud receipt survives retries, reinstall and device changes.
            if (PrivacyConsentReceipt.fromMap(
                  saved.data()?['privacyConsent'],
                ) !=
                null) {
              return;
            }
            transaction.set(profile, {
              'privacyConsent': {
                ...receipt.toMap(),
                'recordedAt': FieldValue.serverTimestamp(),
              },
            }, SetOptions(merge: true));
          })
          .timeout(const Duration(seconds: 8));
    }
    // A late upload can only acknowledge the exact account-scoped local value.
    if (currentOwner != null && await currentOwner() != owner) return;
    await _database.markLocalPreferenceSynced(
      ownerPhoneNumber: owner,
      key: PrivacyConsentReceipt.localKey,
      expectedValue: value,
    );
  }
}
