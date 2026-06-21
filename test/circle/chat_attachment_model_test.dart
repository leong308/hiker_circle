import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';

void main() {
  test('chat attachment survives Firestore serialization', () {
    final message = ChatMessage(
      id: 'message-1',
      chatId: 'chat-1',
      senderPhone: '+60123456789',
      senderName: 'Hiker',
      text: 'Trail photo https://example.com',
      sentAt: DateTime.utc(2026, 6, 20),
      attachment: const ChatAttachment(
        type: ChatAttachmentType.image,
        url: 'https://example.com/photo.jpg',
        fileName: 'photo.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 1024,
      ),
    );

    final restored = ChatMessage.fromFirestore(
      message.id,
      message.toFirestore(),
    );

    expect(restored.attachment?.type, ChatAttachmentType.image);
    expect(restored.attachment?.url, 'https://example.com/photo.jpg');
    expect(restored.attachment?.fileName, 'photo.jpg');
    expect(restored.text, contains('https://example.com'));
  });
}
