// HikerCircleAssistantHistoryStore synchronizes account-scoped local and cloud assistant history.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart';

import '../../app/Data/local_session_database.dart';

class AssistantCloudHistory {
  const AssistantCloudHistory({
    required this.messages,
    required this.clearedAtMicros,
  });
  final List<Map<String, dynamic>> messages;
  final int clearedAtMicros;
}

abstract class AssistantHistoryCloud {
  Future<AssistantCloudHistory> load();
  Future<void> saveMessages(List<Map<String, dynamic>> messages);
  Future<void> clear(int clearedAtMicros);
}

/// Firestore history is private to the authenticated UID.
class FirebaseAssistantHistoryCloud implements AssistantHistoryCloud {
  FirebaseAssistantHistoryCloud({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> get _conversation {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sign in to sync assistant chat.');
    }
    return _firestore.collection('assistantConversations').doc(uid);
  }

  @override
  Future<AssistantCloudHistory> load() async {
    final conversation = _conversation;
    final results = await Future.wait([
      conversation.get(),
      conversation.collection('messages').get(),
    ]);
    final metadata = (results[0] as DocumentSnapshot<Map<String, dynamic>>)
        .data();
    final messages = (results[1] as QuerySnapshot<Map<String, dynamic>>).docs
        .map((doc) {
          try {
            final decoded = jsonDecode(doc.data()['payload']?.toString() ?? '');
            return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
          } catch (_) {
            return null;
          }
        })
        .whereType<Map<String, dynamic>>()
        .toList();
    return AssistantCloudHistory(
      messages: messages,
      clearedAtMicros: (metadata?['clearedAtMicros'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> saveMessages(List<Map<String, dynamic>> messages) async {
    if (messages.isEmpty) return;
    final collection = _conversation.collection('messages');
    for (var start = 0; start < messages.length; start += 400) {
      final batch = _firestore.batch();
      for (final message in messages.skip(start).take(400)) {
        final id = message['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        batch.set(collection.doc(id), {
          'id': id,
          'createdAtMicros': message['createdAtMicros'],
          'payload': jsonEncode(message),
        });
      }
      await batch.commit();
    }
  }

  @override
  Future<void> clear(int clearedAtMicros) async {
    final conversation = _conversation;
    await conversation.set({
      'clearedAtMicros': clearedAtMicros,
    }, SetOptions(merge: true));
    while (true) {
      final snapshot = await conversation
          .collection('messages')
          .where('createdAtMicros', isLessThanOrEqualTo: clearedAtMicros)
          .limit(400)
          .get();
      if (snapshot.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }
}

/// Local-first chat history, optionally synchronized with Firestore.
class HikerCircleAssistantHistoryStore {
  HikerCircleAssistantHistoryStore({
    required this.ownerPhoneNumber,
    LocalSessionDatabase? database,
    this.cloud,
  }) : _database = database ?? LocalSessionDatabase();

  static const _preferenceKey = 'assistant_conversation_v1';
  static const _clearedKey = 'assistant_conversation_cleared_v1';
  final String ownerPhoneNumber;
  final LocalSessionDatabase _database;
  final AssistantHistoryCloud? cloud;
  final Set<String> _uploadedIds = {};
  Future<void> _cloudQueue = Future<void>.value();

  void _queueCloud(Future<void> Function() operation) {
    _cloudQueue = _cloudQueue.then((_) => operation()).catchError((_) {
      // Local history remains authoritative until the next sync attempt.
    });
  }

  Future<void> waitForCloudSync() => _cloudQueue;

  Future<int> _localClearedAt() async {
    final value = await _database.loadLocalPreference(
      ownerPhoneNumber: ownerPhoneNumber,
      key: _clearedKey,
    );
    return value is num ? value.toInt() : 0;
  }

  Future<List<Map<String, dynamic>>> load() async {
    final value = await _database.loadLocalPreference(
      ownerPhoneNumber: ownerPhoneNumber,
      key: _preferenceKey,
    );
    if (value is! List) return const [];
    final now = DateTime.now().microsecondsSinceEpoch;
    final messages = value.whereType<Map>().toList();
    final normalized = <Map<String, dynamic>>[];
    var migrated = false;
    for (var index = 0; index < messages.length; index++) {
      final item = Map<String, dynamic>.from(messages[index]);
      if (item['id'] is! String || (item['id'] as String).isEmpty) {
        item['id'] = sha256
            .convert(utf8.encode('$ownerPhoneNumber:$index:${item['text']}'))
            .toString();
        migrated = true;
      }
      if (item['createdAtMicros'] is! int) {
        item['createdAtMicros'] = now - (messages.length - index) * 1000;
        migrated = true;
      }
      normalized.add(item);
    }
    if (migrated) await _saveLocal(normalized);
    final clearedAt = await _localClearedAt();
    return normalized
        .where((item) => (item['createdAtMicros'] as int) > clearedAt)
        .toList(growable: false);
  }

  Future<void> _saveLocal(List<Map<String, dynamic>> messages) =>
      _database.saveLocalPreference(
        ownerPhoneNumber: ownerPhoneNumber,
        key: _preferenceKey,
        value: messages,
      );

  /// Merge messages by ID after the newest clear-history cutoff so deleted history cannot reappear.
  Future<List<Map<String, dynamic>>> synchronize() async {
    final local = await load();
    final remote = await cloud?.load().timeout(const Duration(seconds: 7));
    if (remote == null) return local;
    final localCutoff = await _localClearedAt();
    final cutoff = localCutoff > remote.clearedAtMicros
        ? localCutoff
        : remote.clearedAtMicros;
    if (cutoff > localCutoff) {
      await _database.saveLocalPreference(
        ownerPhoneNumber: ownerPhoneNumber,
        key: _clearedKey,
        value: cutoff,
      );
    }
    final hasOldCloudMessages = remote.messages.any(
      (item) => ((item['createdAtMicros'] as num?)?.toInt() ?? 0) <= cutoff,
    );
    if (cutoff > 0 &&
        (localCutoff > remote.clearedAtMicros || hasOldCloudMessages)) {
      await cloud!.clear(cutoff).timeout(const Duration(seconds: 7));
    }
    final remoteIds = remote.messages
        .map((item) => item['id']?.toString())
        .toSet();
    _uploadedIds.addAll(remoteIds.whereType<String>());
    final byId = <String, Map<String, dynamic>>{};
    for (final message in [...remote.messages, ...local]) {
      final id = message['id']?.toString() ?? '';
      final created = (message['createdAtMicros'] as num?)?.toInt() ?? 0;
      if (id.isNotEmpty && created > cutoff) byId[id] = message;
    }
    final merged = byId.values.toList()
      ..sort(
        (a, b) => (a['createdAtMicros'] as int).compareTo(
          b['createdAtMicros'] as int,
        ),
      );
    await _saveLocal(merged);
    final missing = merged
        .where((item) => !_uploadedIds.contains(item['id']))
        .toList();
    if (missing.isNotEmpty) {
      await cloud!.saveMessages(missing).timeout(const Duration(seconds: 7));
      _uploadedIds.addAll(missing.map((item) => item['id'] as String));
    }
    return merged;
  }

  /// Save locally first, then queue only message IDs not yet uploaded to the private cloud history.
  Future<void> save(List<Map<String, dynamic>> messages) async {
    await _saveLocal(messages);
    if (cloud != null) {
      _queueCloud(() async {
        final missing = messages
            .where((item) => !_uploadedIds.contains(item['id']))
            .toList();
        if (missing.isEmpty) return;
        await cloud!.saveMessages(missing).timeout(const Duration(seconds: 7));
        _uploadedIds.addAll(missing.map((item) => item['id'] as String));
      });
    }
  }

  Future<void> clear() async {
    final clearedAt = DateTime.now().microsecondsSinceEpoch;
    await _database.saveLocalPreference(
      ownerPhoneNumber: ownerPhoneNumber,
      key: _clearedKey,
      value: clearedAt,
    );
    await _saveLocal(const []);
    _uploadedIds.clear();
    if (cloud != null) {
      _queueCloud(
        () => cloud!.clear(clearedAt).timeout(const Duration(seconds: 7)),
      );
    }
  }
}
