import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/circle/View/circle_page.dart';
import 'package:hiker_circle/circle/View/group_chat_detail_page.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';

void main() {
  for (final receiptFails in [false, true]) {
    testWidgets(
      'chat opens before a slow read receipt ${receiptFails ? 'fails' : 'completes'}',
      (tester) async {
        final repository = _SlowReceiptRepository();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CirclePage(
                session: AppSession(
                  phoneNumber: _phone,
                  signedInAt: DateTime.utc(2026),
                ),
                hikerCircleRepository: repository,
                firebaseBootstrapResult:
                    const FirebaseBootstrapResult.unavailable('Test'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chats'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Weekend hikers'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(GroupChatDetailPage), findsOneWidget);
        expect(
          find.text('Cached trail meeting point', findRichText: true),
          findsOneWidget,
        );
        expect(repository.receipt.isCompleted, isFalse);
        expect(repository.receiptCalls, 1);
        expect(repository.cutoffOwner, _phone);

        // Simulate the delay that previously held navigation on the chat list.
        await tester.pump(const Duration(seconds: 11));
        expect(find.byType(GroupChatDetailPage), findsOneWidget);
        if (receiptFails) {
          repository.receipt.completeError(StateError('Connection lost'));
        } else {
          repository.receipt.complete();
        }
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}

const _phone = '+60123456789';

class _SlowReceiptRepository extends HikerCircleFirebaseRepository {
  _SlowReceiptRepository()
    : super(
        firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
          'Test',
        ),
      );

  final receipt = Completer<void>();
  int receiptCalls = 0;
  String? cutoffOwner;

  @override
  Stream<List<GroupChat>> userGroupChatsStream(String phoneNumber) =>
      Stream.value([
        GroupChat(
          id: 'chat-1',
          hikeSessionId: '',
          trailName: 'Bukit Gasing',
          customName: 'Weekend hikers',
          participantPhones: const [_phone, '+60987654321'],
          creatorPhone: _phone,
          createdAt: DateTime.utc(2026),
        ),
      ]);

  @override
  Future<void> markGroupChatAsRead({
    required String chatId,
    required String phoneNumber,
  }) {
    receiptCalls++;
    return receipt.future;
  }

  @override
  Future<DateTime?> loadLocalLastReadAt(
    String chatId, {
    required String ownerPhoneNumber,
  }) async {
    cutoffOwner = ownerPhoneNumber;
    return DateTime.utc(2026);
  }

  @override
  Future<Map<String, DateTime>> loadAllLocalLastReadAt({
    required String ownerPhoneNumber,
  }) async => {};

  @override
  Future<void> syncPendingReadReceipts({required String phoneNumber}) async {}

  @override
  Stream<List<ChatMessage>> groupChatMessagesStream(String chatId) =>
      const Stream.empty();

  @override
  Future<List<ChatMessage>> loadAllLocalMessagesForChat(
    String chatId, {
    required String ownerPhoneNumber,
  }) async => [
    ChatMessage(
      id: 'cached-1',
      chatId: chatId,
      senderPhone: '+60987654321',
      senderName: 'Hiker',
      text: 'Cached trail meeting point',
      sentAt: DateTime.utc(2026, 9, 14),
    ),
  ];

  @override
  Future<UpcomingHike?> loadUpcomingHikeForChat(String hikeSessionId) async =>
      null;

  @override
  Future<bool> loadGroupChatNotificationsEnabled({
    required AppSession session,
  }) async => true;

  @override
  Future<DateTime?> loadGroupChatMutedUntil({
    required AppSession session,
    required String chatId,
  }) async => null;

  @override
  Future<Set<String>> loadPinnedChats({required AppSession session}) async =>
      {};

  @override
  Future<List<Map<String, dynamic>>> loadCommunityPosts({
    int limit = 30,
  }) async => [];
}
