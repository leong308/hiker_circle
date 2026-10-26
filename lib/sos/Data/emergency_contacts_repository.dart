// EmergencyContactsRepository keeps account-scoped emergency contacts synchronized locally and remotely.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../app/Data/user_module_paths.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/firebase_user_repository.dart';
import '../../app/Data/local_session_database.dart';
import '../../app/Model/app_session.dart';
import '../../authentication/Data/phone_number_formatter.dart';
import '../Model/sos_models.dart';

/// Represents emergency contacts repository exception.
class EmergencyContactsRepositoryException implements Exception {
  /// Creates emergency contacts repository exception.
  const EmergencyContactsRepositoryException(this.message);

  final String message;

  /// Converts to string.
  @override
  String toString() => message;
}

/// Represents emergency contacts change.
class EmergencyContactsChange {
  /// Creates emergency contacts change.
  EmergencyContactsChange(this.phoneNumber, List<EmergencyContact> contacts)
    : contacts = List.unmodifiable(contacts);

  final String phoneNumber;
  final List<EmergencyContact> contacts;
}

/// Keep device contact reads available while account-scoped cloud synchronization is pending.
class EmergencyContactsRepository {
  /// Creates emergency contacts repository.
  const EmergencyContactsRepository({
    FirebaseFirestore? firestore,
    LocalSessionDatabase? localDatabase,
    Duration cloudTimeout = const Duration(seconds: 5),
    FirebaseBootstrapResult firebaseBootstrapResult =
        const FirebaseBootstrapResult.available(),
  }) : _firestore = firestore,
       _localDatabase = localDatabase,
       _cloudTimeout = cloudTimeout,
       _firebaseBootstrapResult = firebaseBootstrapResult;

  static final LocalSessionDatabase _defaultLocalDatabase =
      LocalSessionDatabase();
  static const int maxContacts = 3;
  static const ownNumberMessage =
      'You cannot use your own phone number as an emergency contact.';

  /// Checks whether own phone number.
  static bool isOwnPhoneNumber(String number, String owner) =>
      PhoneNumberFormatter.normalize(number) ==
      PhoneNumberFormatter.normalize(owner);
  static const pendingPreferenceKey = 'pending_emergency_contacts';
  static final _changes = StreamController<EmergencyContactsChange>.broadcast();

  /// Returns changes.
  static Stream<EmergencyContactsChange> get changes => _changes.stream;
  static final Map<String, int> _revisions = {};
  static final Map<String, Future<void>> _localWrites = {};
  final Duration _cloudTimeout;

  /// Applies local lock.
  Future<T> _withLocalLock<T>(String owner, Future<T> Function() action) async {
    final previous = _localWrites[owner] ?? Future<void>.value();
    final done = Completer<void>();
    _localWrites[owner] = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
      if (identical(_localWrites[owner], done.future)) {
        _localWrites.remove(owner);
      }
    }
  }

  /// Computes emit.
  void _emit(String phone, List<EmergencyContact> contacts) {
    _changes.add(EmergencyContactsChange(phone, contacts));
  }

  final FirebaseFirestore? _firestore;
  final LocalSessionDatabase? _localDatabase;
  final FirebaseBootstrapResult _firebaseBootstrapResult;

  /// Returns resolved firestore.
  FirebaseFirestore get _resolvedFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  /// Returns resolved local database.
  LocalSessionDatabase get _resolvedLocalDatabase =>
      _localDatabase ?? _defaultLocalDatabase;

  /// Returns users.
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

  /// Loads emergency contacts.
  Future<List<EmergencyContact>> loadEmergencyContacts({
    required AppSession session,
  }) async {
    final owner = session.phoneNumber;
    final revision = _revisions[owner] ?? 0;
    final pending = await _resolvedLocalDatabase.loadLocalPreference(
      ownerPhoneNumber: owner,
      key: pendingPreferenceKey,
    );
    if (pending is Map && pending['contacts'] is List) {
      final contacts = _parseContacts(pending['contacts']);
      await _withLocalLock(owner, () async {
        if ((_revisions[owner] ?? 0) != revision) return;
        await _resolvedLocalDatabase.saveEmergencyContacts(
          phoneNumber: owner,
          contacts: contacts,
        );
      });
      if (_firebaseBootstrapResult.isAvailable) {
        try {
          await _pushPending(session, pending, contacts);
        } catch (_) {
          // Unsynced local changes, including deletion of every contact, win.
        }
      }
      return loadCachedEmergencyContacts(session: session);
    }
    final localContacts = await loadCachedEmergencyContacts(session: session);
    if (!_firebaseBootstrapResult.isAvailable) return localContacts;
    try {
      final contacts = await fetchCloudContacts(session).timeout(_cloudTimeout);
      if (contacts == null) return localContacts;
      return await _withLocalLock(owner, () async {
        if ((_revisions[owner] ?? 0) != revision) {
          return loadCachedEmergencyContacts(session: session);
        }
        await _resolvedLocalDatabase.saveEmergencyContacts(
          phoneNumber: owner,
          contacts: contacts,
        );
        _emit(owner, contacts);
        return contacts;
      });
    } catch (_) {
      return loadCachedEmergencyContacts(session: session);
    }
  }

  /// Parses contacts.
  List<EmergencyContact> _parseContacts(Object? rawContacts) {
    final contacts = <EmergencyContact>[];
    if (rawContacts is! Iterable) return contacts;
    for (final raw in rawContacts.whereType<Map>()) {
      final contact = _validatedContact(
        EmergencyContact.fromFirestore(Map<String, dynamic>.from(raw)),
      );
      if (contact != null &&
          contacts.length < maxContacts &&
          !contacts.any((saved) => saved.phoneNumber == contact.phoneNumber)) {
        contacts.add(contact);
      }
    }
    return contacts;
  }

  /// Fetches cloud contacts.
  @protected
  Future<List<EmergencyContact>?> fetchCloudContacts(AppSession session) async {
    final data = (await _userDocumentFor(session).get()).data();
    final raw = data?['sos_contacts'];
    return raw is Iterable ? _parseContacts(raw) : null;
  }

  /// Computes push cloud contacts.
  @protected
  Future<void> pushCloudContacts(
    AppSession session,
    List<EmergencyContact> contacts,
  ) async {
    await _userDocumentFor(session).set({
      'sos_contacts': contacts.map((contact) => contact.toFirestore()).toList(),
      'sosContactsCount': contacts.length,
      'sosContactsUpdatedAt': FieldValue.serverTimestamp(),
      'sosContactsUpdatedAtLocal': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Computes push pending.
  Future<void> _pushPending(
    AppSession session,
    Map pending,
    List<EmergencyContact> contacts,
  ) async {
    final current = await _resolvedLocalDatabase.loadLocalPreference(
      ownerPhoneNumber: session.phoneNumber,
      key: pendingPreferenceKey,
    );
    if (current is! Map || current['revision'] != pending['revision']) return;
    await pushCloudContacts(session, contacts).timeout(_cloudTimeout);
    await _withLocalLock(session.phoneNumber, () async {
      final latest = await _resolvedLocalDatabase.loadLocalPreference(
        ownerPhoneNumber: session.phoneNumber,
        key: pendingPreferenceKey,
      );
      if (latest is Map && latest['revision'] == pending['revision']) {
        await _resolvedLocalDatabase.saveLocalPreference(
          ownerPhoneNumber: session.phoneNumber,
          key: pendingPreferenceKey,
          value: null,
        );
      }
    });
  }

  /// Saves emergency contacts.
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
      if (isOwnPhoneNumber(normalized.phoneNumber, session.phoneNumber)) {
        throw const EmergencyContactsRepositoryException(ownNumberMessage);
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
    final owner = session.phoneNumber;
    final revision = (_revisions[owner] ?? 0) + 1;
    _revisions[owner] = revision;
    final pending = <String, Object?>{
      'revision': '${DateTime.now().microsecondsSinceEpoch}:$revision',
      'contacts': normalizedContacts
          .map((contact) => contact.toFirestore())
          .toList(),
    };
    await _withLocalLock(owner, () async {
      await _resolvedLocalDatabase.saveLocalPreference(
        ownerPhoneNumber: owner,
        key: pendingPreferenceKey,
        value: pending,
      );
      await _resolvedLocalDatabase.saveEmergencyContacts(
        phoneNumber: owner,
        contacts: normalizedContacts,
      );
      _emit(owner, normalizedContacts);
    });
    if (!_firebaseBootstrapResult.isAvailable) return;
    try {
      await _pushPending(session, pending, normalizedContacts);
    } catch (_) {
      throw const EmergencyContactsRepositoryException(
        'Saved on this phone. Cloud sync is pending and will retry when connected.',
      );
    }
  }

  /// Computes user document for.
  DocumentReference<Map<String, dynamic>> _userDocumentFor(AppSession session) {
    return userModuleDocument(
      _users.doc(
        FirebaseUserRepository.documentIdForPhoneNumber(session.phoneNumber),
      ),
      UserModule.sos,
    );
  }

  /// Computes validated contact.
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
