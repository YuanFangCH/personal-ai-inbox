import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/services/model_request_policy.dart';

void main() {
  const policy = ModelRequestPolicy();

  test('limits context to the last twenty non-streaming messages', () {
    final messages = [
      for (var index = 0; index < 25; index++) _message('m$index', 'text'),
      _message('pending', 'pending', status: ChatMessageStatus.streaming),
    ];

    final plan = policy.prepare(
      history: messages,
      imagesAllowed: false,
      imageBlockReason: '图片出网已关闭',
    );

    expect(plan.messages, hasLength(20));
    expect(plan.messages.first.id, 'm5');
    expect(plan.messages.last.id, 'm24');
  });

  test('filters every image message when image egress is disabled', () {
    final oldImage = _message('old', '', attachments: [_attachment('a1')]);
    final currentText = _message('current', 'local text');

    final plan = policy.prepare(
      history: [oldImage, currentText],
      imagesAllowed: false,
      imageBlockReason: '图片出网已关闭',
    );

    expect(plan.imagesAllowed, isFalse);
    expect(plan.imageMessageIds, isEmpty);
    expect(plan.blockedReason, isNull);
    expect(plan.messages.map((message) => message.id), ['old', 'current']);
  });

  test('blocks an image-only current message if it cannot be sent', () {
    final plan = policy.prepare(
      history: [
        _message('image', '', attachments: [_attachment('a1')]),
      ],
      imagesAllowed: false,
      imageBlockReason: '图片出网已关闭',
    );

    expect(plan.blockedReason, contains('出网已关闭'));
    expect(plan.messages.single.attachments, hasLength(1));
  });

  test(
    'never feeds failed or interrupted assistant text into later context',
    () {
      final plan = policy.prepare(
        history: [
          _message('user', 'original request'),
          _message(
            'failed',
            'partial response',
            role: ChatRole.assistant,
            status: ChatMessageStatus.failed,
          ),
          _message(
            'interrupted',
            'stopped response',
            role: ChatRole.assistant,
            status: ChatMessageStatus.interrupted,
          ),
          _message('complete', 'finished response', role: ChatRole.assistant),
        ],
        imagesAllowed: false,
        imageBlockReason: '图片出网已关闭',
      );

      expect(plan.messages.map((message) => message.id), ['user', 'complete']);
    },
  );
}

ChatMessage _message(
  String id,
  String text, {
  ChatRole role = ChatRole.user,
  ChatMessageStatus status = ChatMessageStatus.complete,
  List<ChatAttachment> attachments = const [],
}) {
  final time = DateTime(2026, 1, 1);
  return ChatMessage(
    id: id,
    conversationId: 'conversation',
    role: role,
    content: text,
    status: status,
    createdAt: time,
    updatedAt: time,
    attachments: attachments,
  );
}

ChatAttachment _attachment(String id) {
  return ChatAttachment(
    id: id,
    storageKey: id,
    fileName: '$id.png',
    mimeType: 'image/png',
    createdAt: DateTime(2026, 1, 1),
  );
}
