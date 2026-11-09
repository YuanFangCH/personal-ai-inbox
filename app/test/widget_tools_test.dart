import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/core/ai_policy.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/modules/home_widgets/home_widgets.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';
import 'package:personal_ai_inbox/services/widget_tools.dart';

import 'test_support.dart';

void main() {
  test('widget_list returns only readable four-field summaries', () async {
    final workspace = _FakeWidgetWorkspace(
      summaries: [
        _summary('card_visible', tableId: 'tb_visible'),
        _summary('card_private', tableId: 'tb_private'),
        _summary('card_all', sourceMode: WidgetSourceMode.allTables),
      ],
    );
    final tools = WidgetTools(workspace);
    final policy = AiPolicy.forPreset(
      AiPolicyPreset.readOnly,
      tableScope: AiResourceScope.selected(const ['tb_visible']),
    );

    final decoded = jsonDecode(
      await tools.listCardsForAgent(policy),
    ) as Map<String, dynamic>;
    final cards = (decoded['data'] as Map<String, dynamic>)['cards'] as List;

    expect(workspace.lastIncludeArchived, isTrue);
    expect(cards, hasLength(1));
    expect(cards.single, {
      'card_id': 'card_visible',
      'revision': 3,
      'archived': false,
      'visibility': 'titles',
    });
    expect((cards.single as Map).containsKey('spec'), isFalse);
  });

  test(
    'widget_get wraps readable cards and hides out-of-scope cards',
    () async {
      final visible = _definition('card_visible', tableId: 'tb_visible');
      final private = _definition('card_private', tableId: 'tb_private');
      final workspace = _FakeWidgetWorkspace(
        definitions: {visible.cardId: visible, private.cardId: private},
      );
      final tools = WidgetTools(workspace);
      final policy = AiPolicy.forPreset(
        AiPolicyPreset.readOnly,
        tableScope: AiResourceScope.selected(const ['tb_visible']),
      );

      final found = jsonDecode(
        await tools.getCardForAgent('card_visible', policy),
      ) as Map<String, dynamic>;
      final hidden = jsonDecode(
        await tools.getCardForAgent('card_private', policy),
      ) as Map<String, dynamic>;

      expect(found['status'], 'ok');
      expect((found['data'] as Map)['card'], visible.toJson());
      expect(hidden, {'status': 'not_found', 'card_id': 'card_private'});
    },
  );

  test('widget_manage derives the same operation ID for replay', () async {
    final policy = AiPolicy.forPreset(AiPolicyPreset.fullAccess);
    final workspace = _FakeWidgetWorkspace();
    final tools = WidgetTools(workspace);
    final call = _manageCall(
      callId: 'call_create_widget',
      rawArguments: jsonEncode({
        'operation': 'create',
        'spec': _spec(tableId: 'tb_visible').toJson(),
      }),
    );

    final first = await tools.manage(
      call,
      resolveCurrentPolicy: () async => policy,
    );
    final replay = await tools.manage(
      call,
      resolveCurrentPolicy: () async => policy,
    );

    expect(first.succeeded, isTrue);
    expect(replay.succeeded, isTrue);
    expect(workspace.operationIds, hasLength(2));
    expect(workspace.operationIds.toSet(), hasLength(1));
    expect(workspace.authorizationChecks, greaterThanOrEqualTo(2));
  });

  test('all_tables management requires unrestricted table scope', () async {
    final workspace = _FakeWidgetWorkspace();
    final tools = WidgetTools(workspace);
    final policy = AiPolicy.forPreset(
      AiPolicyPreset.fullAccess,
      tableScope: AiResourceScope.selected(const ['tb_visible']),
    );

    final receipt = await tools.manage(
      _manageCall(
        callId: 'call_all_tables',
        rawArguments: jsonEncode({
          'operation': 'create',
          'spec': _spec(
            tableId: 'tb_visible',
            sourceMode: WidgetSourceMode.allTables,
          ).toJson(),
        }),
      ),
      resolveCurrentPolicy: () async => policy,
    );

    expect(receipt.outcome, ChatWriteToolOutcome.rejected);
    expect(receipt.code, 'forbidden');
    expect(receipt.operationId, isNotNull);
    expect(workspace.operationIds, isEmpty);
  });

  test(
    'commit-time reauthorization can deny a previously allowed write',
    () async {
      final workspace = _FakeWidgetWorkspace();
      final tools = WidgetTools(workspace);
      var policyCalls = 0;

      final receipt = await tools.manage(
        _manageCall(
          callId: 'call_revoke',
          rawArguments: jsonEncode({
            'operation': 'create',
            'spec': _spec(tableId: 'tb_visible').toJson(),
          }),
        ),
        resolveCurrentPolicy: () async => policyCalls++ == 0
            ? AiPolicy.forPreset(AiPolicyPreset.fullAccess)
            : AiPolicy.forPreset(AiPolicyPreset.standard),
      );

      expect(receipt.outcome, ChatWriteToolOutcome.failed);
      expect(receipt.code, 'forbidden');
      expect(receipt.operationId, isNotNull);
      expect(workspace.commitAuthorized, isFalse);
    },
  );

  test('ChatService exposes and executes filtered widget reads', () async {
    final chats = ChatRepository(
      store: MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    await chats.initialize();
    final conversation = await chats.createConversation(
      aiPolicy: AiPolicy.forPreset(
        AiPolicyPreset.readOnly,
        tableScope: AiResourceScope.selected(const ['tb_visible']),
      ),
    );
    await chats.saveMessage(
      ChatMessage(
        id: 'msg_widget_read_user',
        conversationId: conversation.id,
        role: ChatRole.user,
        content: '查看我的桌面卡片',
        status: ChatMessageStatus.complete,
        createdAt: conversation.createdAt,
        updatedAt: conversation.updatedAt,
      ),
    );
    final results = ResultLibrary(
      repository: ResultRepository(
        vault: MemoryVaultStore(),
        index: MemoryIndexDatabase(),
        deviceId: 'widget-tools-test',
      ),
    );
    await results.initialize();
    final workspace = _FakeWidgetWorkspace(
      summaries: [
        _summary('card_visible', tableId: 'tb_visible'),
        _summary('card_private', tableId: 'tb_private'),
      ],
    );
    Map<String, dynamic>? firstRequest;
    Map<String, dynamic>? secondRequest;
    var requests = 0;
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'widget-tools-key'),
      repository: chats,
      results: results,
      widgetTools: WidgetTools(workspace),
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          final payload =
              jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
          requests++;
          if (requests == 1) {
            firstRequest = payload;
            return _stream({
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_widget_list',
                        'function': {'name': 'widget_list', 'arguments': '{}'},
                      },
                    ],
                  },
                },
              ],
            }, finish: 'tool_calls');
          }
          secondRequest = payload;
          return _stream({
            'choices': [
              {
                'delta': {'content': '已读取桌面卡片摘要。'},
              },
            ],
          });
        }),
      ),
    );

    await (await service.streamReply(conversationId: conversation.id))
        .drain<void>();

    final toolNames = (firstRequest!['tools'] as List)
        .map((tool) => (tool as Map)['function']['name'])
        .toSet();
    expect(toolNames, containsAll(['widget_list', 'widget_get']));
    final toolMessage = (secondRequest!['messages'] as List)
        .cast<Map>()
        .singleWhere((message) => message['role'] == 'tool');
    expect(toolMessage['content'], contains('card_visible'));
    expect(toolMessage['content'], isNot(contains('card_private')));

    service.close();
    await chats.close();
    await results.shutdown();
    results.dispose();
  });
}

CardDefinition _definition(
  String cardId, {
  required String tableId,
  WidgetSourceMode sourceMode = WidgetSourceMode.selectedTables,
}) => CardDefinition(
  cardId: cardId,
  revision: 3,
  archived: false,
  spec: _spec(tableId: tableId, sourceMode: sourceMode),
);

CardSpec _spec({
  String? tableId,
  WidgetSourceMode sourceMode = WidgetSourceMode.selectedTables,
}) => CardSpec(
  title: '首页',
  sourceMode: sourceMode,
  sections: [if (tableId != null) SectionSpec(tableId: tableId)],
);

CardSummary _summary(
  String cardId, {
  String? tableId,
  WidgetSourceMode sourceMode = WidgetSourceMode.selectedTables,
}) => CardSummary(
  cardId: cardId,
  revision: 3,
  archived: false,
  visibility: WidgetVisibility.titles,
  spec: _spec(tableId: tableId, sourceMode: sourceMode),
);

ChatWriteToolCall _manageCall({
  required String callId,
  required String rawArguments,
}) => ChatWriteToolCall(
  turnId: 'msg_assistant_widget',
  conversationId: 'conv_widget',
  round: 1,
  index: 0,
  callId: callId,
  name: 'widget.manage',
  wireName: 'widget_manage',
  rawArguments: rawArguments,
  arguments: jsonDecode(rawArguments) as Map<String, dynamic>,
);

class _FakeWidgetWorkspace extends ChangeNotifier implements WidgetWorkspace {
  _FakeWidgetWorkspace({
    List<CardSummary> summaries = const [],
    Map<String, CardDefinition> definitions = const {},
  }) : _summaries = summaries,
       _definitions = definitions;

  final List<CardSummary> _summaries;
  final Map<String, CardDefinition> _definitions;
  final List<String> operationIds = [];
  bool? lastIncludeArchived;
  int authorizationChecks = 0;
  bool? commitAuthorized;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<CardSummary>> listCards({bool includeArchived = false}) async {
    lastIncludeArchived = includeArchived;
    return _summaries;
  }

  @override
  Future<CardDefinition?> getCard(String cardId) async => _definitions[cardId];

  @override
  Future<CardPreview> previewCard(CardSpec spec, {String? cardId}) {
    throw UnimplementedError();
  }

  @override
  Future<CardWriteReceipt> applyCardCommand(
    CardCommand command, {
    required String operationId,
    required Future<bool> Function() authorize,
  }) async {
    operationIds.add(operationId);
    authorizationChecks++;
    final authorized = await authorize();
    commitAuthorized = authorized;
    if (!authorized) {
      return CardWriteReceipt(
        operationId: operationId,
        status: CardWriteStatus.failed,
        cardId: command.cardId ?? 'unknown',
        revision: 0,
        publishStatus: WidgetPublishStatus.pending,
        error: WidgetCommandError.forbidden,
      );
    }
    return CardWriteReceipt(
      operationId: operationId,
      status: CardWriteStatus.applied,
      cardId: command.cardId ?? 'card_created',
      revision: command.expectedRevision == null
          ? 1
          : command.expectedRevision! + 1,
      publishStatus: WidgetPublishStatus.pending,
    );
  }

  @override
  Future<WidgetPublishResult> refreshWidgets() async =>
      const WidgetPublishResult.published();
}

http.StreamedResponse _stream(Map<String, dynamic> event, {String? finish}) {
  final choices = (event['choices'] as List)
      .map((choice) => Map<String, dynamic>.from(choice as Map))
      .toList();
  if (finish != null) choices.first['finish_reason'] = finish;
  final payload = {...event, 'choices': choices};
  return http.StreamedResponse(
    Stream.fromIterable([
      utf8.encode('data: ${jsonEncode(payload)}\n\n'),
      utf8.encode('data: [DONE]\n\n'),
    ]),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}
