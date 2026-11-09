import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/services/agent_context_manager.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

void main() {
  test(
    'compacts an oversized latest tool result without splitting its call pair',
    () {
      const maxChars = 4000;
      final oversizedResult = jsonEncode({
        'status': 'success',
        'message': 'content read completed',
        'data': {
          'entries': [
            {
              'id': 'entry_large_context',
              'revision': 7,
              'body': '完整正文。' * 1200,
            },
          ],
        },
      });
      final history = <ChatRequestMessage>[
        const ChatRequestMessage(role: 'user', text: '检查表内全部内容。'),
        const ChatRequestMessage(role: 'assistant', text: '开始读取。'),
        const ChatRequestMessage(
          role: 'assistant',
          text: '',
          toolCalls: [
            {
              'id': 'call_large_context',
              'type': 'function',
              'function': {
                'name': 'content_read',
                'arguments': '{"entry_id":"entry_large_context"}',
              },
            },
          ],
        ),
        ChatRequestMessage(
          role: 'tool',
          toolCallId: 'call_large_context',
          name: 'content_read',
          text: oversizedResult,
        ),
      ];

      final compaction = const AgentContextManager().compact(
        history,
        maxChars: maxChars,
      );

      expect(compaction.blockedReason, isNull);
      expect(compaction.messages.length, 3);
      final summary = compaction.messages.first;
      expect(summary.text, contains('本地安全前缀摘要'));
      expect(summary.text, contains('entry_large_context'));

      final call = compaction.messages[1];
      expect(call.role, 'assistant');
      expect(call.toolCalls.single['id'], 'call_large_context');
      final toolStart = compaction.messages.indexWhere(
        (message) => message.role == 'tool',
      );
      expect(toolStart, isNot(-1));
      expect(compaction.messages[toolStart].toolCallId, 'call_large_context');
      final compactedResult =
          jsonDecode(compaction.messages[toolStart].text) as Map;
      expect(compactedResult['_context_compacted'], isTrue);
      expect(compactedResult['_original_chars'], oversizedResult.runes.length);

      final totalChars = compaction.messages.fold<int>(
        0,
        (total, message) =>
            total +
            message.text.runes.length +
            message.reasoningContent.runes.length +
            message.toolCalls.fold<int>(
              0,
              (count, toolCall) => count + jsonEncode(toolCall).runes.length,
            ),
      );
      expect(totalChars, lessThanOrEqualTo(maxChars));
    },
  );
}
