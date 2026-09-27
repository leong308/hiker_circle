import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/local_session_database.dart';
import 'package:hiker_circle/assistant/Data/hiker_circle_assistant_history_store.dart';

void main() {
  test('local saves and clear complete while a cloud upload is slow', () async {
    final directory = await Directory.systemTemp.createTemp(
      'assistant_slow_cloud_',
    );
    final database = LocalSessionDatabase(
      databasePath: '${directory.path}${Platform.pathSeparator}history.db',
    );
    final gate = Completer<void>();
    final cloud = _SlowCloudHistory(gate.future);
    final store = HikerCircleAssistantHistoryStore(
      ownerPhoneNumber: 'same-account',
      database: database,
      cloud: cloud,
    );
    await store.save([
      {
        'id': 'pending',
        'createdAtMicros': 10,
        'text': 'Pending upload',
        'isUser': true,
      },
    ]);
    expect((await store.load()).single['id'], 'pending');
    await store.clear();
    expect(await store.load(), isEmpty);
    gate.complete();
    await store.waitForCloudSync();
    expect(cloud.messages, isEmpty);
    await database.close();
    await directory.delete(recursive: true);
  });

  test('Firestore sync merges devices and propagates a cleared chat', () async {
    final firstDirectory = await Directory.systemTemp.createTemp(
      'assistant_device_a_',
    );
    final secondDirectory = await Directory.systemTemp.createTemp(
      'assistant_device_b_',
    );
    final firstDatabase = LocalSessionDatabase(
      databasePath: '${firstDirectory.path}${Platform.pathSeparator}history.db',
    );
    final secondDatabase = LocalSessionDatabase(
      databasePath:
          '${secondDirectory.path}${Platform.pathSeparator}history.db',
    );
    final cloud = _MemoryCloudHistory();
    final first = HikerCircleAssistantHistoryStore(
      ownerPhoneNumber: 'same-account',
      database: firstDatabase,
      cloud: cloud,
    );
    final second = HikerCircleAssistantHistoryStore(
      ownerPhoneNumber: 'same-account',
      database: secondDatabase,
      cloud: cloud,
    );
    final firstMessage = {
      'id': 'first',
      'createdAtMicros': 10,
      'text': 'Find a trail',
      'isUser': true,
    };
    final secondMessage = {
      'id': 'second',
      'createdAtMicros': 20,
      'text': 'Here is one',
      'isUser': false,
    };
    await first.save([firstMessage]);
    await first.waitForCloudSync();
    expect((await second.synchronize()).single['id'], 'first');
    await second.save([firstMessage, secondMessage]);
    await second.waitForCloudSync();
    expect((await first.synchronize()).map((item) => item['id']), [
      'first',
      'second',
    ]);
    await first.clear();
    await first.waitForCloudSync();
    expect(await second.synchronize(), isEmpty);
    final newer = {
      'id': 'after-clear',
      'createdAtMicros': cloud.clearedAtMicros + 1,
      'text': 'A new chat',
      'isUser': true,
    };
    await second.save([newer]);
    await second.waitForCloudSync();
    expect((await first.synchronize()).single['id'], 'after-clear');
    await firstDatabase.close();
    await secondDatabase.close();
    await firstDirectory.delete(recursive: true);
    await secondDirectory.delete(recursive: true);
  });

  test(
    'history persists locally and stays separate for each account',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'assistant_history_',
      );
      final databasePath =
          '${directory.path}${Platform.pathSeparator}history.db';
      final firstDatabase = LocalSessionDatabase(databasePath: databasePath);
      final first = HikerCircleAssistantHistoryStore(
        ownerPhoneNumber: 'account-a',
        database: firstDatabase,
      );
      await first.save([
        {'text': 'Find a trail', 'isUser': true},
      ]);
      await firstDatabase.close();

      final reopenedDatabase = LocalSessionDatabase(databasePath: databasePath);
      final reopened = HikerCircleAssistantHistoryStore(
        ownerPhoneNumber: 'account-a',
        database: reopenedDatabase,
      );
      final other = HikerCircleAssistantHistoryStore(
        ownerPhoneNumber: 'account-b',
        database: reopenedDatabase,
      );
      expect((await reopened.load()).single['text'], 'Find a trail');
      expect(await other.load(), isEmpty);
      await reopened.clear();
      expect(await reopened.load(), isEmpty);
      await reopenedDatabase.close();
      await directory.delete(recursive: true);
    },
  );
}

class _MemoryCloudHistory implements AssistantHistoryCloud {
  final Map<String, Map<String, dynamic>> messages = {};
  int clearedAtMicros = 0;

  @override
  Future<AssistantCloudHistory> load() async => AssistantCloudHistory(
    messages: messages.values.toList(),
    clearedAtMicros: clearedAtMicros,
  );

  @override
  Future<void> saveMessages(List<Map<String, dynamic>> values) async {
    for (final value in values) {
      messages[value['id'] as String] = value;
    }
  }

  @override
  Future<void> clear(int value) async {
    clearedAtMicros = value;
    messages.removeWhere(
      (_, message) => (message['createdAtMicros'] as int) <= value,
    );
  }
}

class _SlowCloudHistory extends _MemoryCloudHistory {
  _SlowCloudHistory(this.gate);
  final Future<void> gate;

  @override
  Future<void> saveMessages(List<Map<String, dynamic>> values) async {
    await gate;
    await super.saveMessages(values);
  }
}
