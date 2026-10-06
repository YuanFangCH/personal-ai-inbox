import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/sqlite_conversation_store.dart';

void main() {
  test(
    'sqlite conversation store persists messages and auto actions',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'conversation-store',
      );
      final path = '${directory.path}${Platform.pathSeparator}chat.sqlite3';
      final store = SqliteConversationStore(path);
      await store.open();
      await store.open();

      final now = DateTime(2026, 10, 4, 23, 30);
      final conversation = Conversation(
        id: 'cnv_test',
        title: '测试会话',
        createdAt: now,
        updatedAt: now,
        autoTitle: false,
        preview: '你好',
      );
      await store.upsertConversation(conversation);
      await store.upsertMessage(
        ChatMessage(
          id: 'msg_test',
          conversationId: conversation.id,
          role: ChatRole.assistant,
          content: '已记录',
          status: ChatMessageStatus.complete,
          createdAt: now,
          updatedAt: now,
          attachments: [
            ChatAttachment(
              id: 'att_test',
              storageKey: 'cnv_test/msg_test/att_test.jpg',
              fileName: 'test.jpg',
              mimeType: 'image/jpeg',
              createdAt: now,
            ),
          ],
          actions: [
            AutoRecordAction(
              id: 'act_test',
              type: ResultType.todo,
              title: '测试待办',
              status: AutoRecordStatus.created,
              createdAt: now,
              resultId: 'td_test',
              undoUntil: now.add(const Duration(minutes: 10)),
            ),
          ],
        ),
      );

      await store.close();
      final reopened = SqliteConversationStore(path);
      await reopened.open();

      expect((await reopened.listConversations()).single.title, '测试会话');
      final message = (await reopened.listMessages('cnv_test')).single;
      expect(message.content, '已记录');
      expect(message.attachments.single.fileName, 'test.jpg');
      expect(message.actions.single.resultId, 'td_test');
      expect((await reopened.findAutoRecordAction('act_test'))?.title, '测试待办');

      await reopened.deleteConversation('cnv_test');
      expect(await reopened.listConversations(), isEmpty);
      expect(await reopened.listMessages('cnv_test'), isEmpty);
      await reopened.close();
      await directory.delete(recursive: true);
    },
  );
}
