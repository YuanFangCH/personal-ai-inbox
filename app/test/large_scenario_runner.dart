import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/sync_engine.dart';
import 'package:personal_ai_inbox/data/sync_provider.dart';
import 'package:personal_ai_inbox/services/app_controller.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'large_scenario_20_cases.g.dart';
import 'test_support.dart';

List<LargeScenario> loadLargeScenarios() {
  return largeScenarioMaps.map(LargeScenario.fromMap).toList(growable: false);
}

Future<void> runLargeScenario(LargeScenario scenario) async {
  final responses = {
    for (final message in scenario.messages) message.text: message,
  };
  final requests = <Map<String, dynamic>>[];
  final model = ModelClient(
    client: MockClient.streaming((request, bodyStream) async {
      final body =
          jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>;
      requests.add(body);
      final messages = body['messages'] as List<dynamic>;
      final userText = messages
          .cast<Map<String, dynamic>>()
          .lastWhere((message) => message['role'] == 'user')['content']
          .toString();
      final response = responses[userText];
      if (response == null) {
        throw StateError('No mock response for: $userText');
      }

      final events = <String>[
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': response.assistant},
            },
          ],
        })}\n\n',
      ];
      for (var index = 0; index < response.calls.length; index++) {
        final call = response.calls[index];
        events.add(
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': index,
                      'id': 'call_${scenario.id}_${index}_$index',
                      'type': 'function',
                      'function': {'name': 'create_result', 'arguments': jsonEncode(call.toolPayload)},
                    },
                  ],
                },
              },
            ],
          })}\n\n',
        );
      }
      events.add('data: [DONE]\n\n');
      return http.StreamedResponse(
        Stream.fromIterable(events.map(utf8.encode)),
        200,
        headers: const {'content-type': 'text/event-stream'},
      );
    }),
  );

  final vault = MemoryVaultStore();
  final index = MemoryIndexDatabase();
  await index.open();
  final settings = FakeSettingsService(
    deviceId: 'scenario-device',
    modelKey: 'test-key',
  );
  final repository = ResultRepository(
    vault: vault,
    index: index,
    deviceId: 'scenario-device',
  );
  final chatRepository = ChatRepository(
    store: MemoryConversationStore(),
    attachments: MemoryAttachmentStore(),
  );
  final controller = AppController(
    repository: repository,
    indexDatabase: index,
    captureService: CaptureService(
      settings: settings,
      parser: const DeterministicParser(),
    ),
    settingsService: settings,
    syncEngine: SyncEngine(
      repository: repository,
      provider: MemorySyncProvider(),
      deviceId: 'scenario-device',
    ),
    chatRepository: chatRepository,
    chatService: ChatService(
      settings: settings,
      repository: chatRepository,
      modelClient: model,
    ),
  );

  try {
    await controller.initialize();
    final conversationId = (await controller.createConversation()).id;
    for (final message in scenario.messages) {
      await controller.sendChatMessage(conversationId, text: message.text);
      final assistant = controller.messagesFor(conversationId).last;
      expect(
        assistant.role,
        ChatRole.assistant,
        reason: '${scenario.id}: expected assistant response',
      );
      expect(
        assistant.status,
        ChatMessageStatus.complete,
        reason: '${scenario.id}: assistant response failed: ${assistant.error}',
      );
      expect(assistant.error, isNull, reason: scenario.id);
      expect(
        assistant.actions,
        hasLength(message.calls.length),
        reason: '${scenario.id}: action count for "${message.text}"',
      );
    }

    expect(requests, hasLength(scenario.messages.length));
    final actions = controller
        .messagesFor(conversationId)
        .expand((message) => message.actions)
        .toList(growable: false);
    final expectedCalls = scenario.messages
        .expand((message) => message.calls)
        .toList(growable: false);
    expect(
      actions,
      hasLength(expectedCalls.length),
      reason: '${scenario.id}: total actions',
    );
    expect(
      actions.where((action) => action.status == AutoRecordStatus.created),
      hasLength(expectedCalls.where((call) => call.expect == 'created').length),
      reason: '${scenario.id}: created actions',
    );

    for (final call in expectedCalls) {
      final matching = actions.where(
        (action) => action.type == call.type && action.title == call.title,
      );
      expect(matching, isNotEmpty, reason: '${scenario.id}: ${call.title}');
      final action = matching.first;
      expect(
        action.status.name,
        call.expect,
        reason: '${scenario.id}: ${call.title}',
      );
      if (call.expect != 'created' || action.resultId == null) {
        continue;
      }
      final document = controller.findDocument(action.resultId!);
      expect(document, isNotNull, reason: '${scenario.id}: ${call.title}');
      expect(
        document!.type,
        call.type,
        reason: '${scenario.id}: ${call.title}',
      );
      expect(document.body, call.body, reason: '${scenario.id}: ${call.title}');
      if (call.type == ResultType.event) {
        _expectMoment(
          document.start,
          call.start,
          '${scenario.id}: ${call.title}',
        );
        _expectMoment(document.end, call.end, '${scenario.id}: ${call.title}');
      } else if (call.type == ResultType.todo) {
        _expectMoment(document.due, call.due, '${scenario.id}: ${call.title}');
      }
    }

    for (final type in ResultType.values) {
      final expected = expectedCalls
          .where((call) => call.expect == 'created' && call.type == type)
          .length;
      expect(
        controller.documents.where((document) => document.type == type),
        hasLength(expected),
        reason: '${scenario.id}: ${type.wireName} count',
      );
    }

    final rebuilt = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'scenario-device',
    );
    await rebuilt.initialize();
    final rebuiltDocuments = await rebuilt.listDocuments();
    expect(
      rebuiltDocuments,
      hasLength(expectedCalls.where((call) => call.expect == 'created').length),
      reason: '${scenario.id}: Markdown rebuild',
    );
    expect(
      rebuiltDocuments.map((document) => document.title).toSet(),
      expectedCalls
          .where((call) => call.expect == 'created')
          .map((call) => call.title)
          .toSet(),
      reason: '${scenario.id}: rebuilt titles',
    );
  } finally {
    controller.dispose();
    model.close();
  }
}

void _expectMoment(DateTime? actual, String? expected, String reason) {
  expect(actual, isNotNull, reason: reason);
  expect(expected, isNotNull, reason: reason);
  expect(
    actual!.isAtSameMomentAs(DateTime.parse(expected!)),
    isTrue,
    reason: '$reason: expected $expected, got ${actual.toIso8601String()}',
  );
}

class LargeScenario {
  const LargeScenario({
    required this.id,
    required this.key,
    required this.name,
    required this.category,
    required this.summary,
    required this.messages,
  });

  factory LargeScenario.fromMap(Map<String, Object?> json) {
    return LargeScenario(
      id: json['id'] as String,
      key: json['key'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      summary: json['summary'] as String,
      messages: (json['messages'] as List<Object?>)
          .map(
            (value) => LargeScenarioMessage.fromMap(
              (value as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  final String id;
  final String key;
  final String name;
  final String category;
  final String summary;
  final List<LargeScenarioMessage> messages;
}

class LargeScenarioMessage {
  const LargeScenarioMessage({
    required this.text,
    required this.assistant,
    required this.calls,
  });

  factory LargeScenarioMessage.fromMap(Map<String, Object?> json) {
    return LargeScenarioMessage(
      text: json['text'] as String,
      assistant: json['assistant'] as String,
      calls: (json['calls'] as List<Object?>)
          .map(
            (value) => LargeScenarioCall.fromMap(
              (value as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  final String text;
  final String assistant;
  final List<LargeScenarioCall> calls;
}

class LargeScenarioCall {
  const LargeScenarioCall({
    required this.type,
    required this.title,
    required this.body,
    required this.confidence,
    required this.sensitive,
    required this.tags,
    required this.expect,
    this.start,
    this.end,
    this.due,
    this.allDay = false,
    this.recurrence,
  });

  factory LargeScenarioCall.fromMap(Map<String, Object?> json) {
    return LargeScenarioCall(
      type: ResultType.parse(json['type'] as String),
      title: json['title'] as String,
      body: json['body'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      sensitive: json['sensitive'] as bool,
      tags: (json['tags'] as List<Object?>).cast<String>(),
      expect: json['expect'] as String,
      start: json['start'] as String?,
      end: json['end'] as String?,
      due: json['due'] as String?,
      allDay: json['all_day'] == true,
      recurrence: json['recurrence'] as String?,
    );
  }

  final ResultType type;
  final String title;
  final String body;
  final double confidence;
  final bool sensitive;
  final List<String> tags;
  final String expect;
  final String? start;
  final String? end;
  final String? due;
  final bool allDay;
  final String? recurrence;

  Map<String, Object?> get toolPayload {
    return {
      'type': type.wireName,
      'title': title,
      'body': body,
      'confidence': confidence,
      'sensitive': sensitive,
      'tags': tags,
      'start': start,
      'end': end,
      'due': due,
      'all_day': allDay,
      'recurrence': recurrence,
    };
  }
}
