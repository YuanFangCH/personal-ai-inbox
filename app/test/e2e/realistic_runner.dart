/// Executes one realistic end-to-end scenario against the production widget
/// tree. The runner is shared by host smoke tests and the three device legs so
/// the same scenario data cannot drift between platforms.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/core/markdown_codec.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/index_database.dart';
import 'package:personal_ai_inbox/data/io_vault_store.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/sync_engine.dart';
import 'package:personal_ai_inbox/data/sync_provider.dart';
import 'package:personal_ai_inbox/data/vault_store.dart';
import 'package:personal_ai_inbox/modules/capture/capture_workflow.dart';
import 'package:personal_ai_inbox/modules/conversation/auto_record_processor.dart';
import 'package:personal_ai_inbox/modules/conversation/conversation_workspace.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/modules/settings/device_preferences.dart';
import 'package:personal_ai_inbox/modules/sync/sync_workspace.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/image_input_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import '../test_support.dart';
import 'realistic_scenario.dart';

/// Runs a single scenario. [simulateViewport] is false on Android devices so
/// the real emulator viewport is asserted instead of faked.
Future<void> runRealisticScenario(
  WidgetTester tester,
  RealisticScenario scenario, {
  bool simulateViewport = true,
}) async {
  final previousOnError = FlutterError.onError;
  final capturedDetails = <FlutterErrorDetails>[];
  FlutterError.onError = (details) {
    capturedDetails.add(details);
    previousOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousOnError);
  addTearDown(() => FocusManager.instance.primaryFocus?.unfocus());

  _applyViewport(tester, scenario, simulateViewport: simulateViewport);
  tester.platformDispatcher.textScaleFactorTestValue = scenario.fontScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final harness = _Harness(scenario);
  addTearDown(() async {
    await harness.dispose();
  });
  await harness.boot(useIo: scenario.category == 'persistence');
  await tester.pumpWidget(PersonalAiInboxApp(runtime: harness.runtime));
  await tester.pumpAndSettle();

  for (final step in scenario.steps) {
    await harness.execute(tester, step);
    final error = tester.takeException();
    if (error != null) {
      fail(
        '${scenario.id} step ${step.op} threw: $error\n'
        '${capturedDetails.map((item) => item.toString()).join('\n')}',
      );
    }
  }

  final error = tester.takeException();
  if (error != null) {
    fail(
      '${scenario.id} finished with an exception: $error\n'
      '${capturedDetails.map((item) => item.toString()).join('\n')}',
    );
  }
}

void _applyViewport(
  WidgetTester tester,
  RealisticScenario scenario, {
  required bool simulateViewport,
}) {
  if (!simulateViewport) {
    final logicalWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    if (scenario.platform == RealisticPlatform.phone) {
      expect(logicalWidth, lessThan(600), reason: 'expected a phone viewport');
    } else {
      expect(
        logicalWidth,
        greaterThanOrEqualTo(600),
        reason: 'expected a tablet viewport',
      );
    }
    return;
  }
  final viewport = scenario.platform.hostViewport;
  tester.view.physicalSize = Size(
    viewport.width * viewport.pixelRatio,
    viewport.height * viewport.pixelRatio,
  );
  tester.view.devicePixelRatio = viewport.pixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _Harness {
  _Harness(this.scenario);

  final RealisticScenario scenario;
  final MarkdownCodec _codec = const MarkdownCodec();
  final ScriptedSyncProvider syncProvider = ScriptedSyncProvider();

  VaultStore? _vault;
  Directory? _ioRoot;
  IndexDatabase? _index;
  ChatRepository? _chatRepository;
  AppRuntime? _runtime;
  final MemoryConversationStore _conversationStore = MemoryConversationStore();
  final MemoryAttachmentStore _attachmentStore = MemoryAttachmentStore();

  late FakeSettingsService settings;
  late ResultRepository repository;
  late ResultLibrary results;
  late CaptureWorkflow capture;
  late ConversationWorkspace conversations;
  late SyncWorkspace sync;
  late DevicePreferences preferences;

  AppRuntime get runtime => _runtime!;
  ChatRepository get chatRepository => _chatRepository!;

  bool _storagePrepared = false;
  bool get _useIo => scenario.category == 'persistence';
  String get deviceId => 'e2e-${scenario.platform.name}';

  Future<void> boot({required bool useIo, bool rebuildIndex = false}) async {
    if (rebuildIndex) {
      _index = null;
    }
    if (useIo) {
      final base = await _resolveIoBase();
      _ioRoot ??= Directory(p.join(base.path, scenario.id));
      if (!_storagePrepared) {
        if (await _ioRoot!.exists()) {
          await _ioRoot!.delete(recursive: true);
        }
        await _ioRoot!.create(recursive: true);
        _storagePrepared = true;
      }
      _vault ??= IoVaultStore.at(_ioRoot!);
    } else {
      _vault ??= MemoryVaultStore();
    }
    _index ??= MemoryIndexDatabase();
    final index = _index!;
    final vault = _vault!;

    settings = FakeSettingsService(
      deviceId: 'e2e-${scenario.platform.name}',
      themeMode: scenario.isDark ? ThemePreference.dark : ThemePreference.light,
      modelKey: _needsModelKey ? 'e2e-test-key' : null,
    );
    final modelClient = ModelClient(client: _buildScriptedClient());

    repository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: deviceId,
    );
    final chatRepository = ChatRepository(
      store: _conversationStore,
      attachments: _attachmentStore,
    );
    _chatRepository = chatRepository;
    final chatService = ChatService(
      settings: settings,
      repository: chatRepository,
      modelClient: modelClient,
    );
    preferences = DevicePreferences(
      adapter: SettingsServiceDevicePreferencesAdapter(settings),
    );
    results = ResultLibrary(repository: repository);
    capture = CaptureWorkflow(
      repository: repository,
      results: results,
      indexDatabase: index,
      captureService: CaptureService(
        settings: settings,
        parser: const DeterministicParser(),
        modelClient: modelClient,
      ),
    );
    conversations = ConversationWorkspace(
      repository: chatRepository,
      results: results,
      chatService: chatService,
      autoRecordProcessor: AutoRecordProcessor(
        chatRepository: chatRepository,
        results: results,
        captures: capture,
        deviceId: () => repository.deviceId,
      ),
      imageInputService: ImageInputService(),
    );
    sync = SyncWorkspace(
      engine: SyncEngine(
        repository: repository,
        provider: syncProvider,
        deviceId: deviceId,
      ),
      repository: repository,
      results: results,
    );
    _runtime = AppRuntime(
      preferences: preferences,
      results: results,
      capture: capture,
      conversations: conversations,
      sync: sync,
      closeAdapters: () async {
        await chatRepository.close();
        await index.close();
      },
    );
    await _runtime!.initialize();
  }

  bool get _needsModelKey => scenario.category.startsWith('chat');

  Future<void> _timed(String label, Future<void> Function() action) async {
    try {
      await action().timeout(const Duration(seconds: 10));
    } catch (error) {
      // ignore: avoid_print
      print('E2E shutdown $label failed: $error');
    }
  }

  /// Prefers the app support directory (what the production vault uses) and
  /// falls back to the temp directory on hosts without path_provider plugins.
  Future<Directory> _resolveIoBase() async {
    try {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, 'e2e-storage'));
    } on Object {
      return Directory(p.join(Directory.systemTemp.path, 'ai_inbox_e2e'));
    }
  }

  Future<void> dispose() async {
    final runtime = _runtime;
    if (runtime != null) {
      // Shut the modules down first; the runtime shutdown is then a no-op pass
      // that still closes the storage adapters.
      await _timed('conversations', runtime.conversations.shutdown);
      await _timed('sync', runtime.sync.shutdown);
      await _timed('results', runtime.results.shutdown);
      await _timed('preferences', runtime.preferences.shutdown);
      await _timed('runtime', runtime.shutdown);
    }
    _runtime = null;
    final root = _ioRoot;
    if (root != null && await root.exists()) {
      try {
        await root.delete(recursive: true);
      } on FileSystemException {
        // Best effort cleanup only.
      }
    }
  }

  http.Client _buildScriptedClient() {
    return MockClient.streaming((request, bodyStream) async {
      final body = await bodyStream.bytesToString();
      final decoded = body.isEmpty
          ? const <String, Object?>{}
          : jsonDecode(body);
      final streaming = decoded is Map && decoded['stream'] == true;
      if (!streaming) {
        final payload = jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'type': 'knowledge',
                  'title': '云端整理结果',
                  'summary': '由脚本模型生成的整理结果。',
                  'confidence': 0.9,
                  'sensitive': false,
                  'tags': <String>[],
                }),
              },
            },
          ],
        });
        return http.StreamedResponse(
          Stream.value(utf8.encode(payload)),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return _sseResponse();
    });
  }

  http.StreamedResponse _sseResponse() {
    final chunks = <String>[];
    final reply = scenario.reply;
    switch (scenario.chatScript) {
      case ChatScript.text:
        chunks.addAll(_contentChunks(reply));
        chunks.add(
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n',
        );
        chunks.add('data: [DONE]\n\n');
      case ChatScript.tool:
        chunks.addAll(_contentChunks(reply));
        chunks.addAll(_toolChunks());
        chunks.add(
          'data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}\n\n',
        );
        chunks.add('data: [DONE]\n\n');
      case ChatScript.toolNoDone:
        chunks.addAll(_contentChunks(reply));
        chunks.addAll(_toolChunks());
      case ChatScript.noDone:
        chunks.addAll(_contentChunks(reply));
      case ChatScript.httpError:
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":"scripted failure"}')),
          500,
        );
      case ChatScript.slow:
        chunks.addAll(_contentChunks(reply));
        chunks.add('data: [DONE]\n\n');
    }
    if (scenario.chatScript == ChatScript.slow) {
      return http.StreamedResponse(_slowStream(chunks), 200);
    }
    return http.StreamedResponse(
      Stream.fromIterable(chunks.map(utf8.encode)),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  Stream<List<int>> _slowStream(List<String> chunks) async* {
    for (final chunk in chunks) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      yield utf8.encode(chunk);
    }
  }

  List<String> _toolChunks() {
    final arguments = jsonEncode(_resolveTokens(scenario.toolPayload));
    final first = arguments.substring(0, arguments.length ~/ 2);
    final second = arguments.substring(first.length);
    return [
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_e2e',
                  'function': {'name': 'create_result', 'arguments': first},
                },
              ],
            },
          },
        ],
      })}\n\n',
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': second},
                },
              ],
            },
          },
        ],
      })}\n\n',
    ];
  }

  List<String> _contentChunks(String text) {
    final chunks = <String>[];
    for (var index = 0; index < text.length; index += 6) {
      final part = text.substring(
        index,
        index + 6 > text.length ? text.length : index + 6,
      );
      chunks.add(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': part},
            },
          ],
        })}\n\n',
      );
    }
    return chunks;
  }

  Object? _resolveTokens(Object? value) {
    if (value is String) {
      final match = RegExp(r'^\{\{future:(\d+)\}\}$').firstMatch(value);
      if (match != null) {
        final days = int.parse(match.group(1)!);
        return DateTime.now().add(Duration(days: days)).toIso8601String();
      }
      final past = RegExp(r'^\{\{past:(\d+)\}\}$').firstMatch(value);
      if (past != null) {
        final days = int.parse(past.group(1)!);
        return DateTime.now().subtract(Duration(days: days)).toIso8601String();
      }
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _resolveTokens(item)),
      );
    }
    if (value is List) {
      return value.map(_resolveTokens).toList();
    }
    return value;
  }

  static const bool _verbose = bool.fromEnvironment('E2E_VERBOSE');

  Future<void> execute(WidgetTester tester, RealisticStep step) async {
    if (_verbose) {
      // ignore: avoid_print
      print('E2E ${scenario.id} -> ${step.op} ${step.args}');
    }
    switch (step.op) {
      case 'nav':
        await _goto(tester, step.args['page'] as String);
      case 'capture':
        await _capture(tester, step.args['text'] as String);
      case 'calendarMode':
        await _goto(tester, 'calendar');
        await _tapKey(tester, 'calendar_mode_${step.args['mode']}');
      case 'calendarSection':
        await _goto(tester, 'calendar');
        await _tapKey(tester, 'calendar_section_${step.args['section']}');
      case 'quickCreate':
        await _quickCreate(tester, step);
      case 'toggleTodo':
        await _toggleTodo(tester, step.args['title'] as String);
      case 'openDoc':
        await _openDocument(
          tester,
          step.args['title'] as String,
          page: step.args['page'] as String? ?? 'knowledge',
        );
      case 'searchKnowledge':
        await _searchKnowledge(tester, step.args['query'] as String);
      case 'newChat':
        await _newChat(tester, step.args['text'] as String);
      case 'startChat':
        await _startChat(tester, step.args['text'] as String);
      case 'retryChat':
        await _retryChat(tester);
      case 'stopChat':
        await _stopChat(tester);
      case 'undoAutoRecord':
        await _tapText(tester, '撤销');
      case 'tapText':
        await _tapText(tester, step.args['value'] as String);
      case 'sync':
        await _sync(tester, step.args);
      case 'resolveConflict':
        await _resolveConflict(
          tester,
          useRemote: step.args['useRemote'] == true,
        );
      case 'theme':
        await _setTheme(tester, step.args['value'] as String);
      case 'imageEgress':
        await _setImageEgress(tester, step.args['value'] == true);
      case 'restart':
        await _restart(tester);
      case 'scroll':
        await _scroll(tester, (step.args['times'] as num?)?.toInt() ?? 2);
      case 'seed':
        await _seed(tester, step.args);
      case 'assert':
        await _assert(tester, step.args);
      default:
        throw StateError('Unsupported op: ${step.op}');
    }
  }

  // ------------------------------------------------------------------ helpers

  double _logicalWidth(WidgetTester tester) =>
      tester.view.physicalSize.width / tester.view.devicePixelRatio;

  Future<void> _goto(WidgetTester tester, String page) async {
    // Pushed routes (conversation, editors) cover the shell navigation.
    for (var attempt = 0; attempt < 3; attempt++) {
      if (find.byKey(const Key('nav_home')).evaluate().isNotEmpty) break;
      await tester.pageBack();
      await _settle(tester);
    }
    const compactOnly = {'matters', 'knowledge', 'sync', 'settings'};
    final width = _logicalWidth(tester);
    if (width < 980 && compactOnly.contains(page)) {
      await _tapKey(tester, 'nav_more');
      await _tapKey(tester, 'sheet_nav_$page');
    } else {
      await _tapKey(tester, 'nav_$page');
    }
    await _settle(tester);
    expect(
      find.byKey(Key('page_$page')),
      findsOneWidget,
      reason: 'navigation to $page',
    );
  }

  Future<void> _tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    if (finder.evaluate().isEmpty) {
      throw StateError('Missing widget key: $key');
    }
    await tester.ensureVisible(finder.first);
    await tester.pump();
    await tester.tap(finder.first);
    await _settle(tester);
  }

  Future<void> _tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    if (finder.evaluate().isEmpty) {
      throw StateError('Missing text: $text');
    }
    await tester.ensureVisible(finder.first);
    await tester.pump();
    await tester.tap(finder.first);
    await _settle(tester);
  }

  Future<void> _settle(WidgetTester tester) async {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );
  }

  Future<void> _waitFor(
    WidgetTester tester,
    bool Function() predicate, {
    Duration timeout = const Duration(seconds: 30),
    String? reason,
  }) async {
    final watch = Stopwatch()..start();
    while (!predicate()) {
      if (watch.elapsed > timeout) {
        throw StateError('Timed out waiting for ${reason ?? 'condition'}');
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> _capture(WidgetTester tester, String text) async {
    final before = results.documents.length;
    final reviewsBefore = capture.reviewCaptures.length;
    final fab = find.byKey(const Key('capture_button'));
    if (fab.evaluate().isNotEmpty) {
      await tester.tap(fab);
      await _settle(tester);
    } else {
      await _goto(tester, 'home');
      await _tapText(tester, '收下内容');
    }
    await tester.enterText(find.byKey(const Key('capture_text_field')), text);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final submit = find.byKey(const Key('capture_submit'));
    await tester.scrollUntilVisible(
      submit,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(submit);
    await _waitFor(
      tester,
      () =>
          results.documents.length != before ||
          capture.reviewCaptures.length != reviewsBefore,
      reason: 'capture "$text" to settle',
    );
    await _hideSnackBars(tester);
    await _settle(tester);
  }

  /// Capture shows a bottom snack bar that overlaps the calendar action bar on
  /// compact layouts; dismiss it so later taps are not swallowed.
  Future<void> _hideSnackBars(WidgetTester tester) async {
    final messengers = find.byType(ScaffoldMessenger);
    if (messengers.evaluate().isEmpty) return;
    final state = tester.state<ScaffoldMessengerState>(messengers.first);
    state.hideCurrentSnackBar();
    await tester.pump();
  }

  Future<void> _quickCreate(WidgetTester tester, RealisticStep step) async {
    final kind = step.args['kind'] as String? ?? 'event';
    await _goto(tester, 'calendar');
    await _tapKey(
      tester,
      kind == 'todo' ? 'calendar_section_todos' : 'calendar_section_calendar',
    );
    final before = results.documents.length;
    await _tapKey(tester, 'calendar_quick_create');
    await tester.enterText(
      find.byKey(const Key('quick_create_title')),
      step.args['title'] as String,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _tapKey(tester, 'quick_create_save');
    await _waitFor(
      tester,
      () => results.documents.length > before,
      reason: 'quick create result',
    );
    await _settle(tester);
  }

  Future<void> _toggleTodo(WidgetTester tester, String title) async {
    await _goto(tester, 'calendar');
    await _tapKey(tester, 'calendar_section_todos');
    final target = find.text(title);
    if (target.evaluate().isEmpty) {
      throw StateError('Todo not visible: $title');
    }
    await tester.scrollUntilVisible(
      target.first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final row = find.ancestor(of: target.first, matching: find.byType(Row));
    final checkbox = find.descendant(
      of: row.first,
      matching: find.byType(Checkbox),
    );
    await tester.tap(checkbox.first);
    await _settle(tester);
  }

  Future<void> _openDocument(
    WidgetTester tester,
    String title, {
    String page = 'knowledge',
  }) async {
    // Re-navigating would rebuild the page and drop the active search filter.
    if (find.byKey(Key('page_$page')).evaluate().isEmpty) {
      await _goto(tester, page);
    }
    // Restrict to plain Text widgets: the search field also contains the typed
    // query, and tapping it would not open a document.
    final target = _exactText(title);
    try {
      await _waitFor(
        tester,
        () => target.evaluate().isNotEmpty,
        reason: 'document "$title" to be listed',
        timeout: const Duration(seconds: 15),
      );
    } on StateError {
      final texts = find
          .byType(Text)
          .evaluate()
          .map((element) => (element.widget as Text).data)
          .whereType<String>()
          .take(20)
          .join(' | ');
      fail('document "$title" not listed. Visible text: $texts');
    }
    await tester.scrollUntilVisible(
      target.first,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(target.first);
    await _settle(tester);
    expect(find.text(title), findsWidgets);
    await tester.pageBack();
    await _settle(tester);
  }

  Finder _exactText(String value) => find.byWidgetPredicate(
    (widget) => widget is Text && widget.data == value,
  );

  Future<void> _searchKnowledge(WidgetTester tester, String query) async {
    await _goto(tester, 'knowledge');
    final field = find.byType(TextField).first;
    // Scroll back to the field and focus it explicitly: after scrolling the
    // list, the text input client may no longer be attached on desktop.
    await tester.ensureVisible(field);
    await _settle(tester);
    await tester.tap(field);
    await _settle(tester);
    await tester.enterText(field, query);
    await tester.pump(const Duration(milliseconds: 250));
    await _settle(tester);
    final controller = tester.widget<TextField>(field).controller;
    expect(
      controller?.text,
      query,
      reason: 'search field should hold "$query"',
    );
  }

  Future<void> _newChat(WidgetTester tester, String text) async {
    final before = results.documents.length;
    final reviewsBefore = capture.reviewCaptures.length;
    await _startChat(tester, text);
    await tester.pump(const Duration(milliseconds: 300));
    if (conversations.isChatGenerating) {
      await _waitFor(
        tester,
        () => !conversations.isChatGenerating,
        reason: 'chat stream to finish',
      );
    }
    await _settle(tester);
    if (scenario.chatScript == ChatScript.tool) {
      await _waitFor(
        tester,
        () =>
            results.documents.length != before ||
            capture.reviewCaptures.length != reviewsBefore,
        reason: 'auto record to finish',
      );
      await _settle(tester);
    }
  }

  Future<void> _startChat(WidgetTester tester, String text) async {
    await _goto(tester, 'inbox');
    await _tapKey(tester, 'inbox_new_conversation');
    await tester.enterText(find.byKey(const Key('chat_input')), text);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final send = find.byKey(const Key('chat_send'));
    expect(send, findsOneWidget, reason: 'chat send button');
    await tester.tap(send);
    await tester.pump(const Duration(milliseconds: 120));
  }

  Future<void> _retryChat(WidgetTester tester) async {
    final retry = find.text('重试');
    expect(retry, findsWidgets, reason: 'retry action for a failed reply');
    await tester.ensureVisible(retry.first);
    await tester.pump();
    await tester.tap(retry.first);
    await tester.pump(const Duration(milliseconds: 300));
    if (conversations.isChatGenerating) {
      await _waitFor(
        tester,
        () => !conversations.isChatGenerating,
        reason: 'retry to finish',
      );
    }
    await _settle(tester);
  }

  Future<void> _stopChat(WidgetTester tester) async {
    await _waitFor(
      tester,
      () => conversations.isChatGenerating,
      reason: 'generation to start',
      timeout: const Duration(seconds: 15),
    );
    await tester.pump(const Duration(milliseconds: 120));
    final stop = find.byKey(const Key('chat_send'));
    expect(stop, findsOneWidget, reason: 'stop button');
    await tester.tap(stop);
    await _waitFor(
      tester,
      () => !conversations.isChatGenerating,
      reason: 'generation to stop',
    );
    await _settle(tester);
  }

  Future<void> _seed(WidgetTester tester, Map<String, Object?> args) async {
    final kind = args['kind'] as String;
    switch (kind) {
      case 'knowledgeBulk':
        final count = (args['count'] as num).toInt();
        final prefix = args['prefix'] as String? ?? '知识条目';
        for (var index = 0; index < count; index++) {
          await results.createManual(
            type: ResultType.knowledge,
            title: '$prefix $index',
            body: '第 $index 条知识正文，包含检索关键词 ${args['keyword'] ?? ''}。',
            tags: const ['批量'],
          );
        }
      case 'matterTree':
        final title = args['title'] as String? ?? '项目推进';
        final matter = await results.createManual(
          type: ResultType.matter,
          title: title,
          body: '$title 的要求与背景。',
        );
        for (var index = 0; index < 2; index++) {
          await results.createManual(
            type: ResultType.todo,
            title: '$title 待办 ${index + 1}',
            due: DateTime.now().add(Duration(days: 1 + index)),
            matterId: matter.id,
          );
        }
        await results.createManual(
          type: ResultType.event,
          title: '$title 会议',
          start: DateTime.now().add(const Duration(hours: 3)),
          end: DateTime.now().add(const Duration(hours: 4)),
          matterId: matter.id,
        );
      case 'processingCapture':
        await _index!.insertCapture(
          CaptureRecord(
            id: 'cap_processing_${scenario.id.toLowerCase()}',
            deviceId: deviceId,
            capturedAt: DateTime.now(),
            sourceType: CaptureSourceType.text,
            text: '应用在整理期间被关闭时保留的原文',
            status: CaptureStatus.processing,
          ),
        );
      case 'mixed':
        await results.createManual(
          type: ResultType.matter,
          title: '综合事项',
          body: '综合事项正文。',
        );
        await results.createManual(
          type: ResultType.todo,
          title: '综合待办',
          due: DateTime.now().add(const Duration(days: 2)),
        );
        await results.createManual(
          type: ResultType.event,
          title: '综合日程',
          start: DateTime.now().add(const Duration(days: 1, hours: 2)),
          end: DateTime.now().add(const Duration(days: 1, hours: 3)),
        );
        await results.createManual(
          type: ResultType.knowledge,
          title: '综合知识',
          body: '综合知识正文。',
        );
      default:
        throw StateError('Unsupported seed: $kind');
    }
    await results.refresh();
    await tester.pumpAndSettle();
  }

  Future<void> _sync(WidgetTester tester, Map<String, Object?> args) async {
    final seed = args['seed'] as String? ?? 'none';
    final title = args['title'] as String?;
    switch (seed) {
      case 'none':
        break;
      case 'remoteNew':
        final now = DateTime.now();
        final remoteDocument = ResultDocument(
          id: 'kn_remote_${scenario.id.toLowerCase()}',
          type: ResultType.knowledge,
          title: title ?? '远端新增知识',
          status: ResultStatus.canonical,
          originDevice: 'remote-device',
          revision: 1,
          createdAt: now,
          updatedAt: now,
          body: '远端新增正文。',
        );
        syncProvider.seed(_codec.encode(remoteDocument), remoteDocument);
      case 'conflict':
        final local = await results.createManual(
          type: ResultType.knowledge,
          title: title ?? '同步冲突对象',
          body: '本地初始正文。',
        );
        await _syncNow(tester);
        final changedLocal = local.copyWith(
          body: '${local.body}\n本地追加内容。',
          revision: local.revision + 1,
          updatedAt: DateTime.now(),
        );
        await results.saveDocument(changedLocal);
        final remote = local.copyWith(
          body: '${local.body}\n远端追加内容。',
          revision: local.revision + 1,
          updatedAt: DateTime.now(),
        );
        syncProvider.seed(_codec.encode(remote), local);
      default:
        throw StateError('Unsupported sync seed: $seed');
    }
    await _syncNow(tester);
  }

  Future<void> _syncNow(WidgetTester tester) async {
    await _goto(tester, 'sync');
    await _tapText(tester, '立即同步');
    await _waitFor(tester, () => !sync.isBusy, reason: 'sync to finish');
    await _settle(tester);
  }

  Future<void> _resolveConflict(
    WidgetTester tester, {
    required bool useRemote,
  }) async {
    await _goto(tester, 'inbox');
    final menu = find.byTooltip('裁决冲突');
    await tester.scrollUntilVisible(
      menu.first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(menu.first);
    await _settle(tester);
    await _tapText(tester, useRemote ? '使用远端版本' : '保留本地版本');
    await _waitFor(
      tester,
      () => sync.conflictFiles.isEmpty,
      reason: 'conflict to resolve',
    );
    await _settle(tester);
  }

  Future<void> _setTheme(WidgetTester tester, String value) async {
    await _goto(tester, 'settings');
    await _tapText(tester, value == 'dark' ? '深色' : '浅色');
    await _saveSettings(tester);
    final expected = value == 'dark'
        ? ThemePreference.dark
        : ThemePreference.light;
    await _waitFor(
      tester,
      () => preferences.settings.themeMode == expected,
      reason: 'theme preference to become $value',
    );
    await _settle(tester);
  }

  Future<void> _setImageEgress(WidgetTester tester, bool value) async {
    await _goto(tester, 'settings');
    final current = preferences.settings.allowImageEgress;
    if (current == value) return;
    await _tapText(tester, '允许图片发送到云端');
    await _saveSettings(tester);
    await _waitFor(
      tester,
      () => preferences.settings.allowImageEgress == value,
      reason: 'image egress preference to become $value',
    );
    await _settle(tester);
  }

  /// Settings are staged locally and persisted by the explicit save action.
  Future<void> _saveSettings(WidgetTester tester) async {
    await _tapText(tester, '保存');
    await _hideSnackBars(tester);
    await _settle(tester);
  }

  Future<void> _restart(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _runtime?.shutdown();
    await boot(useIo: _useIo, rebuildIndex: _useIo);
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
  }

  Future<void> _scroll(WidgetTester tester, int times) async {
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isEmpty) return;
    for (var index = 0; index < times; index++) {
      await tester.drag(scrollables.first, const Offset(0, -520));
      await tester.pumpAndSettle();
    }
  }

  Future<List<ChatMessage>> _allMessages() async {
    final conversations = await chatRepository.listConversations();
    final messages = <ChatMessage>[];
    for (final conversation in conversations) {
      messages.addAll(await chatRepository.listMessages(conversation.id));
    }
    return messages;
  }

  Future<void> _assert(WidgetTester tester, Map<String, Object?> args) async {
    final kind = args['kind'] as String;
    switch (kind) {
      case 'resultCount':
        expect(
          results.documents.length,
          (args['value'] as num).toInt(),
          reason: 'result count',
        );
      case 'typeCount':
        final counts = (args['counts'] as Map).cast<String, Object?>();
        for (final entry in counts.entries) {
          final type = ResultType.parse(entry.key);
          expect(
            results.documents.where((document) => document.type == type).length,
            (entry.value as num).toInt(),
            reason: 'count for ${entry.key}',
          );
        }
      case 'titleExists':
        final title = args['value'] as String;
        expect(
          results.documents.any((document) => document.title == title),
          isTrue,
          reason: 'missing result "$title"',
        );
      case 'titleMissing':
        final title = args['value'] as String;
        expect(
          results.documents.any((document) => document.title == title),
          isFalse,
          reason: 'unexpected result "$title"',
        );
      case 'reviewCount':
        expect(
          capture.reviewCaptures.length,
          (args['value'] as num).toInt(),
          reason: 'review queue',
        );
      case 'conflictCount':
        expect(
          sync.conflictFiles.length,
          (args['value'] as num).toInt(),
          reason: 'conflict queue',
        );
      case 'textVisible':
        expect(
          find.text(args['value'] as String),
          findsWidgets,
          reason: 'visible text "${args['value']}"',
        );
      case 'bodyContains':
        final title = args['title'] as String;
        final needle = args['value'] as String;
        final match = results.documents.where(
          (document) => document.title == title,
        );
        expect(match, isNotEmpty, reason: 'missing result "$title"');
        expect(match.first.body, contains(needle), reason: 'body of "$title"');
      case 'todoDone':
        final title = args['title'] as String;
        final match = results.documents.where(
          (document) => document.title == title,
        );
        expect(match, isNotEmpty, reason: 'missing todo "$title"');
        expect(match.first.done, args['value'] == true);
      case 'themeDark':
        expect(
          preferences.settings.themeMode == ThemePreference.dark,
          args['value'] == true,
          reason: 'theme mode',
        );
      case 'imageEgress':
        expect(
          preferences.settings.allowImageEgress,
          args['value'] == true,
          reason: 'image egress',
        );
      case 'conversationCount':
        final conversations = await chatRepository.listConversations();
        expect(
          conversations.length,
          (args['value'] as num).toInt(),
          reason: 'conversation count',
        );
      case 'chatReplyContains':
        final messages = await _allMessages();
        expect(
          messages.any(
            (message) =>
                !message.isUser &&
                message.content.contains(args['value'] as String),
          ),
          isTrue,
          reason: 'assistant reply contains "${args['value']}"',
        );
      case 'assistantStatus':
        final assistant = (await _allMessages())
            .where((message) => !message.isUser)
            .toList(growable: false);
        expect(assistant, isNotEmpty, reason: 'assistant message exists');
        expect(
          assistant.last.status.name,
          args['value'] as String,
          reason: 'assistant status',
        );
      case 'noException':
        expect(tester.takeException(), isNull);
      default:
        throw StateError('Unsupported assertion: $kind');
    }
  }
}

/// In-memory sync provider with explicit seeding so conflict scenarios are
/// deterministic instead of relying on sandbox randomness.
class ScriptedSyncProvider implements SyncProvider {
  final Map<String, SyncRemoteObject> _objects = {};
  int _etag = 0;

  @override
  String get displayName => '脚本同步通道';

  @override
  Future<void> connect() async {}

  @override
  Future<List<SyncRemoteObject>> listObjects() async =>
      _objects.values.toList(growable: false);

  @override
  Future<SyncRemoteObject> putObject({
    required String id,
    required String path,
    required String contents,
    required SyncWriteCondition condition,
  }) async {
    final current = _objects[id];
    final matches = switch (condition.kind) {
      SyncWriteConditionKind.createOnly => current == null,
      SyncWriteConditionKind.matchEtag =>
        current?.etag == condition.etag && condition.etag != null,
    };
    if (!matches) {
      throw SyncPreconditionFailed(id);
    }
    final object = SyncRemoteObject(
      id: id,
      path: path,
      content: contents,
      hash: _hash(contents),
      etag: 'etag-${++_etag}',
    );
    _objects[id] = object;
    return object;
  }

  @override
  Future<void> deleteObject(String id, String? etag) async {
    final current = _objects[id];
    if (etag != null && current?.etag != etag) {
      throw StateError('Remote object changed');
    }
    _objects.remove(id);
  }

  void seed(String contents, ResultDocument document) {
    _objects[document.id] = SyncRemoteObject(
      id: document.id,
      path: document.markdownPath,
      content: contents,
      hash: _hash(contents),
      etag: 'etag-${++_etag}',
    );
  }

  String _hash(String value) => 'sha256:${sha256.convert(utf8.encode(value))}';
}
