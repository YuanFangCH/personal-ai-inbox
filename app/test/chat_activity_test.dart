import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/chat_activity.dart';

void main() {
  test('projects only matched tool receipts in assistant call order', () {
    final tools = completedChatActivityTools([
      {
        'role': 'assistant',
        'tool_calls': [
          {
            'id': 'read-1',
            'function': {'name': 'table_list'},
          },
          {
            'id': 'read-1',
            'function': {'name': 'table_list'},
          },
          {
            'id': 'write-1',
            'function': {'name': 'content_create'},
          },
          {
            'id': 'never-dispatched',
            'function': {'name': 'content_delete'},
          },
        ],
      },
      {'role': 'tool', 'tool_call_id': 'unmatched', 'content': 'secret'},
      {'role': 'tool', 'tool_call_id': 'write-1', 'content': 'secret'},
      {'role': 'tool', 'tool_call_id': 'read-1', 'content': 'secret'},
      {
        'role': 'assistant',
        'tool_calls': [
          {
            'id': 'read-1',
            'function': {'name': 'content_read'},
          },
        ],
      },
      {'role': 'tool', 'tool_call_id': 'read-1', 'content': 'secret'},
      {'role': 'assistant', 'content': 'old record without calls'},
    ]);

    expect(tools.map((tool) => (tool.round, tool.callId, tool.wireName)), [
      (0, 'read-1', 'table_list'),
      (0, 'write-1', 'content_create'),
      (1, 'read-1', 'content_read'),
    ]);
    expect(
      () => tools.add(
        const ChatActivityTool(round: 0, callId: 'x', wireName: 'table_list'),
      ),
      throwsUnsupportedError,
    );
  });
}
