/// Runtime-only progress information for a single assistant response.
///
/// This metadata is deliberately separate from model reasoning and tool
/// arguments. Completed tool activity is projected from the persisted tool
/// transcript without interpreting tool result contents.
enum ChatActivityPhase {
  preparing,
  waitingForModel,
  thinking,
  runningTools,
  writingReply,
  waitingToRetry,
}

typedef ChatActivityToolKey = ({int round, String callId});
typedef ChatActivitySink = void Function(ChatActivityEvent event);

sealed class ChatActivityEvent {
  const ChatActivityEvent();
}

final class ChatActivityPhaseChanged extends ChatActivityEvent {
  const ChatActivityPhaseChanged(this.phase);

  final ChatActivityPhase phase;
}

final class ChatActivityToolDispatched extends ChatActivityEvent {
  const ChatActivityToolDispatched(this.tool);

  final ChatActivityTool tool;
}

final class ChatActivityTool {
  const ChatActivityTool({
    required this.round,
    required this.callId,
    required this.wireName,
  });

  final int round;
  final String callId;
  final String wireName;

  ChatActivityToolKey get key => (round: round, callId: callId);
}

final class ChatLiveActivity {
  ChatLiveActivity({
    required this.phase,
    List<ChatActivityTool> runningTools = const [],
  }) : runningTools = List.unmodifiable(runningTools);

  final ChatActivityPhase phase;
  final List<ChatActivityTool> runningTools;
}

List<ChatActivityTool> completedChatActivityTools(
  List<Map<String, dynamic>> transcript,
) {
  final completed = <ChatActivityTool>[];
  final seen = <ChatActivityToolKey>{};
  var round = -1;
  List<dynamic> calls = const [];
  final replies = <String>{};

  void flushRound() {
    for (final rawCall in calls) {
      if (rawCall is! Map || rawCall['id'] is! String) continue;
      final id = rawCall['id'] as String;
      final function = rawCall['function'];
      if (!replies.contains(id) || function is! Map) continue;
      final name = function['name'];
      if (name is! String) continue;
      final tool = ChatActivityTool(round: round, callId: id, wireName: name);
      if (seen.add(tool.key)) completed.add(tool);
    }
    calls = const [];
    replies.clear();
  }

  for (final item in transcript) {
    if (item['role'] == 'assistant') {
      flushRound();
      round++;
      final rawCalls = item['tool_calls'];
      calls = rawCalls is List ? rawCalls : const [];
    } else if (item['role'] == 'tool' && item['tool_call_id'] is String) {
      replies.add(item['tool_call_id'] as String);
    }
  }
  flushRound();

  return List.unmodifiable(completed);
}
