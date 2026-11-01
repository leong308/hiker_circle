import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web/web.dart' as web;

import '../Model/feedback_report.dart' show feedbackImageLimit;
import '../Model/feedback_saved_draft.dart';

extension type _DraftRecord._(JSObject _) implements JSObject {
  external factory _DraftRecord({
    required String owner,
    required String id,
    required String status,
    required int revision,
    required String category,
    required String message,
    required String screenshotHash,
    required bool submissionAttempted,
  });
  external String get owner;
  external String get id;
  external String get status;
  external int get revision;
  external String get category;
  external String get message;
  external String get screenshotHash;
  external bool get submissionAttempted;
}

/// Durable browser form storage. Images stay in IndexedDB, outside localStorage
/// limits and independent of Firebase availability. Native SQLite is never opened.
class FeedbackDraftStore {
  FeedbackDraftStore(this.database)
    : _databaseName = 'hiker_circle_feedback_drafts';

  @visibleForTesting
  FeedbackDraftStore.forTesting(this.database, {required String databaseName})
    : _databaseName = databaseName;

  // Object keeps browser-only consumers independent of native SQLite/FFI
  // imports, while accepting the existing repository's database argument.
  final Object database;
  final String _databaseName;
  static final _random = Random.secure();
  static const _drafts = 'drafts';
  static const _screenshots = 'screenshots';
  web.IDBDatabase? _connection;
  Future<web.IDBDatabase>? _opening;

  String _owner(String owner) {
    final value = owner.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(owner, 'owner', 'Missing owner');
    }
    return value;
  }

  String _imageHash(Uint8List? image) =>
      image == null ? '' : crypto.sha256.convert(image).toString();

  void _validateScreenshot(Uint8List? image) {
    if (image != null && image.length > feedbackImageLimit) {
      throw ArgumentError.value(
        image.length,
        'screenshot',
        'The feedback screenshot must be at most 5 MB.',
      );
    }
  }

  Future<JSAny?> _request(web.IDBRequest request) {
    final completed = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      if (!completed.isCompleted) completed.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!completed.isCompleted) {
        completed.completeError(
          StateError(request.error?.message ?? 'Browser draft storage failed.'),
        );
      }
    }).toJS;
    return completed.future;
  }

  Future<web.IDBDatabase> _open() {
    final existing = _connection;
    if (existing != null) return Future.value(existing);
    return _opening ??= _openConnection().whenComplete(() => _opening = null);
  }

  Future<web.IDBDatabase> _openConnection() async {
    final request = web.window.indexedDB.open(_databaseName, 1);
    request.onupgradeneeded = ((web.Event _) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_drafts)) {
        db.createObjectStore(
          _drafts,
          web.IDBObjectStoreParameters(keyPath: 'owner'.toJS),
        );
      }
      if (!db.objectStoreNames.contains(_screenshots)) {
        db.createObjectStore(_screenshots);
      }
    }).toJS;
    final db = (await _request(request)) as web.IDBDatabase;
    db.onversionchange = ((web.Event _) {
      db.close();
      if (identical(_connection, db)) _connection = null;
    }).toJS;
    db.onclose = ((web.Event _) {
      if (identical(_connection, db)) _connection = null;
    }).toJS;
    _connection = db;
    return db;
  }

  Future<T> _transaction<T>(
    String mode,
    Future<T> Function(web.IDBTransaction) action,
  ) async {
    final db = await _open();
    final transaction = db.transaction(
      [_drafts.toJS, _screenshots.toJS].toJS,
      mode,
    );
    final completed = Completer<void>();
    void failed() {
      if (!completed.isCompleted) {
        completed.completeError(
          StateError(
            transaction.error?.message ??
                'Browser draft transaction was aborted.',
          ),
        );
      }
    }

    transaction.oncomplete = ((web.Event _) {
      if (!completed.isCompleted) completed.complete();
    }).toJS;
    transaction.onabort = ((web.Event _) => failed()).toJS;
    transaction.onerror = ((web.Event _) => failed()).toJS;
    // Observe failure immediately, even if a request rejects before we reach
    // the final commit wait. Never report a save before the transaction commits.
    final finished = completed.future.then<Object?>(
      (_) => null,
      onError: (Object error, StackTrace stack) => (error, stack),
    );
    try {
      final value = await action(transaction);
      final failure = await finished;
      if (failure is (Object, StackTrace)) {
        Error.throwWithStackTrace(failure.$1, failure.$2);
      }
      return value;
    } catch (error, stack) {
      try {
        transaction.abort();
      } catch (_) {
        /* Already completed or aborted. */
      }
      await finished;
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<_DraftRecord?> _record(
    web.IDBTransaction transaction,
    String owner,
  ) async {
    final value = await _request(
      transaction.objectStore(_drafts).get(owner.toJS),
    );
    return value.isUndefinedOrNull ? null : _DraftRecord._(value as JSObject);
  }

  Future<FeedbackSavedDraft> _restore(
    web.IDBTransaction transaction,
    _DraftRecord record,
  ) async {
    Uint8List? image;
    if (record.screenshotHash.isNotEmpty) {
      final value = await _request(
        transaction.objectStore(_screenshots).get(record.owner.toJS),
      );
      if (value.isUndefinedOrNull) {
        throw StateError('The saved feedback screenshot is unavailable.');
      }
      image = (value as JSUint8Array).toDart;
      if (_imageHash(image) != record.screenshotHash) {
        throw StateError(
          'The saved feedback screenshot could not be verified.',
        );
      }
    }
    return FeedbackSavedDraft(
      id: record.id,
      uid: record.owner,
      category: record.category,
      message: record.message,
      screenshot: image,
      submissionAttempted: record.submissionAttempted,
      revision: record.revision,
    );
  }

  _DraftRecord _metadata(FeedbackSavedDraft draft, int revision) =>
      _DraftRecord(
        owner: draft.uid,
        id: draft.id,
        status: 'active',
        revision: revision,
        category: draft.category,
        message: draft.message,
        screenshotHash: _imageHash(draft.screenshot),
        submissionAttempted: draft.submissionAttempted,
      );

  Future<void> _writeImage(
    web.IDBTransaction transaction,
    String owner,
    Uint8List? image,
  ) async {
    final store = transaction.objectStore(_screenshots);
    await _request(
      image == null
          ? store.delete(owner.toJS)
        : store.put(Uint8List.fromList(image).toJS, owner.toJS),
    );
  }

  Future<FeedbackSavedDraft?> load(String owner) {
    final account = _owner(owner);
    return _transaction('readonly', (transaction) async {
      final record = await _record(transaction, account);
      if (record == null || record.status != 'active') return null;
      return _restore(transaction, record);
    });
  }

  Future<FeedbackSavedDraft> open({
    required String owner,
    String category = 'Problem',
    String message = '',
    Uint8List? screenshot,
  }) {
    final account = _owner(owner);
    _validateScreenshot(screenshot);
    // Freeze caller-owned bytes before the first asynchronous database request.
    final initial = FeedbackSavedDraft(
      id: List.generate(
        10,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      uid: account,
      category: category,
      message: message,
      screenshot: screenshot,
    );
    return _transaction('readwrite', (transaction) async {
      final current = await _record(transaction, account);
      if (current != null && current.status == 'active') {
        return _restore(transaction, current);
      }
      final revision = current == null ? 0 : current.revision + 1;
      await _request(
        transaction.objectStore(_drafts).put(_metadata(initial, revision)),
      );
      await _writeImage(transaction, account, initial.screenshot);
      return FeedbackSavedDraft(
        id: initial.id,
        uid: account,
        category: category,
        message: message,
        screenshot: initial.screenshot,
        revision: revision,
      );
    });
  }

  Future<FeedbackSavedDraft?> save(FeedbackSavedDraft draft) {
    _validateScreenshot(draft.screenshot);
    return _transaction('readwrite', (transaction) async {
      final current = await _record(transaction, draft.uid);
      if (current == null ||
          current.status != 'active' ||
          current.id != draft.id ||
          current.revision != draft.revision) {
        return null;
      }
      final hash = _imageHash(draft.screenshot);
      if (current.submissionAttempted &&
          (!draft.submissionAttempted ||
              current.category != draft.category ||
              current.message != draft.message ||
              current.screenshotHash != hash)) {
        return null;
      }
      final revision = draft.revision + 1;
      await _request(
        transaction.objectStore(_drafts).put(_metadata(draft, revision)),
      );
      if (current.screenshotHash != hash) {
        await _writeImage(transaction, draft.uid, draft.screenshot);
      }
      return FeedbackSavedDraft(
        id: draft.id,
        uid: draft.uid,
        category: draft.category,
        message: draft.message,
        screenshot: draft.screenshot,
        submissionAttempted: draft.submissionAttempted,
        revision: revision,
      );
    });
  }

  Future<void> _clear(
    web.IDBTransaction transaction,
    _DraftRecord current,
  ) async {
    await _request(
      transaction
          .objectStore(_drafts)
          .put(
            _DraftRecord(
              owner: current.owner,
              id: current.id,
              status: 'cleared',
              revision: current.revision + 1,
              category: '',
              message: '',
              screenshotHash: '',
              submissionAttempted: false,
            ),
          ),
    );
    await _writeImage(transaction, current.owner, null);
  }

  Future<bool> discard(FeedbackSavedDraft expected) =>
      _transaction('readwrite', (transaction) async {
        final current = await _record(transaction, expected.uid);
        if (current == null ||
            current.status != 'active' ||
            current.id != expected.id ||
            current.revision != expected.revision) {
          return false;
        }
        await _clear(transaction, current);
        return true;
      });

  Future<bool> acknowledge({
    required String owner,
    required String id,
    required String category,
    required String message,
    Uint8List? screenshot,
  }) {
    final account = _owner(owner);
    final hash = _imageHash(screenshot);
    return _transaction('readwrite', (transaction) async {
      final current = await _record(transaction, account);
      if (current == null ||
          current.status != 'active' ||
          !current.submissionAttempted ||
          current.id != id ||
          current.category != category ||
          current.message != message ||
          current.screenshotHash != hash) {
        return false;
      }
      await _clear(transaction, current);
      return true;
    });
  }

  @visibleForTesting
  void closeForTesting() {
    _connection?.close();
    _connection = null;
  }
}
