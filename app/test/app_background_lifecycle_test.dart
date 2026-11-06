import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/data/index_database.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/services/agent_background_service.dart';
import 'package:personal_ai_inbox/services/voice_service.dart';

import 'test_support.dart';

void main() {
  test(
    'lifecycle shutdown waits for an active task to pause or finish',
    () async {
      final background = _FakeBackgroundPort(
        const AgentBackgroundSnapshot(
          state: AgentBackgroundState.running,
          taskId: 'task_lifecycle',
        ),
      );
      var shutdownCount = 0;
      final gate = AgentBackgroundLifecycleGate(
        backgroundAgent: background,
        shutdownRuntime: () async {
          shutdownCount++;
        },
        shutdownGracePeriod: Duration.zero,
      );

      await gate.scheduleShutdown();
      expect(shutdownCount, 0);

      background.value = const AgentBackgroundSnapshot(
        state: AgentBackgroundState.paused,
        taskId: 'task_lifecycle',
      );
      await Future<void>.delayed(Duration.zero);
      expect(shutdownCount, 1);
    },
  );

  test('lifecycle shutdown remains immediate when no task is active', () async {
    final background = _FakeBackgroundPort(
      const AgentBackgroundSnapshot(state: AgentBackgroundState.idle),
    );
    var shutdownCount = 0;
    final gate = AgentBackgroundLifecycleGate(
      backgroundAgent: background,
      shutdownRuntime: () async {
        shutdownCount++;
      },
      shutdownGracePeriod: Duration.zero,
    );

    await gate.scheduleShutdown();
    await Future<void>.delayed(Duration.zero);

    expect(shutdownCount, 1);
  });

  testWidgets('shutdown rechecks task status when the grace timer expires', (
    tester,
  ) async {
    final background = _FakeBackgroundPort(
      const AgentBackgroundSnapshot(
        state: AgentBackgroundState.completed,
        taskId: 'task_restarts_during_grace',
      ),
    );
    var shutdownCount = 0;
    final gate = AgentBackgroundLifecycleGate(
      backgroundAgent: background,
      shutdownRuntime: () async {
        shutdownCount++;
      },
      shutdownGracePeriod: const Duration(milliseconds: 200),
    );

    await gate.scheduleShutdown();
    background.value = const AgentBackgroundSnapshot(
      state: AgentBackgroundState.running,
      taskId: 'task_restarts_during_grace',
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(shutdownCount, 0);

    background.value = const AgentBackgroundSnapshot(
      state: AgentBackgroundState.completed,
      taskId: 'task_restarts_during_grace',
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(shutdownCount, 1);
  });

  testWidgets(
    'resuming a shared-engine app cancels deferred shutdown after activity recreation',
    (tester) async {
      final conversationStore = _TrackingConversationStore();
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        conversationStoreOverride: conversationStore,
        settingsOverride: FakeSettingsService(deviceId: 'lifecycle-recreate'),
        voiceService: _NoopVoiceService(),
      );
      addTearDown(runtime.dispose);
      final background = _FakeBackgroundPort(
        const AgentBackgroundSnapshot(
          state: AgentBackgroundState.running,
          taskId: 'task_recreated',
        ),
      );

      await tester.pumpWidget(
        PersonalAiInboxApp(runtime: runtime, backgroundAgent: background),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      background.value = const AgentBackgroundSnapshot(
        state: AgentBackgroundState.completed,
        taskId: 'task_recreated',
      );
      await tester.pump();
      await tester.pump();

      expect(conversationStore.closed, isFalse);
      background.value = const AgentBackgroundSnapshot(
        state: AgentBackgroundState.running,
        taskId: 'task_recreated',
      );
    },
  );

  testWidgets(
    'idle activity recreation keeps the shared runtime open for the new root',
    (tester) async {
      final index = _TrackingIndexDatabase();
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: index,
        conversationStoreOverride: _TrackingConversationStore(),
        settingsOverride: FakeSettingsService(
          deviceId: 'lifecycle-idle-recreate',
        ),
        voiceService: _NoopVoiceService(),
      );
      addTearDown(runtime.dispose);
      final background = _FakeBackgroundPort(
        const AgentBackgroundSnapshot(state: AgentBackgroundState.idle),
      );

      await tester.pumpWidget(
        PersonalAiInboxApp(runtime: runtime, backgroundAgent: background),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        PersonalAiInboxApp(runtime: runtime, backgroundAgent: background),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      await runtime.tables.refresh();

      expect(index.closeCount, 0);
      background.value = const AgentBackgroundSnapshot(
        state: AgentBackgroundState.running,
        taskId: 'task_after_idle_recreate',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'terminal status during root recreation is cancelled by the resumed root',
    (tester) async {
      final index = _TrackingIndexDatabase();
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: index,
        conversationStoreOverride: _TrackingConversationStore(),
        settingsOverride: FakeSettingsService(
          deviceId: 'lifecycle-terminal-recreate',
        ),
        voiceService: _NoopVoiceService(),
      );
      addTearDown(runtime.dispose);
      final background = _FakeBackgroundPort(
        const AgentBackgroundSnapshot(
          state: AgentBackgroundState.running,
          taskId: 'task_terminal_recreated',
        ),
      );

      await tester.pumpWidget(
        PersonalAiInboxApp(runtime: runtime, backgroundAgent: background),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      background.value = const AgentBackgroundSnapshot(
        state: AgentBackgroundState.completed,
        taskId: 'task_terminal_recreated',
      );
      await tester.pump();
      await tester.pumpWidget(
        PersonalAiInboxApp(runtime: runtime, backgroundAgent: background),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(index.closeCount, 0);
      await runtime.tables.refresh();

      background.value = const AgentBackgroundSnapshot(
        state: AgentBackgroundState.running,
        taskId: 'task_terminal_recreated',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _FakeBackgroundPort implements AgentBackgroundPort {
  _FakeBackgroundPort(AgentBackgroundSnapshot initial)
    : _status = ValueNotifier<AgentBackgroundSnapshot>(initial);

  final ValueNotifier<AgentBackgroundSnapshot> _status;

  set value(AgentBackgroundSnapshot next) => _status.value = next;

  @override
  Stream<AgentBackgroundCommand> get commands => const Stream.empty();

  @override
  ValueListenable<AgentBackgroundSnapshot> get status => _status;

  @override
  Future<void> initialize() async {}
}

class _TrackingConversationStore extends MemoryConversationStore {
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
    await super.close();
  }
}

class _TrackingIndexDatabase extends MemoryIndexDatabase {
  int closeCount = 0;

  @override
  Future<void> close() async {
    closeCount++;
    await super.close();
  }

  @override
  Future<List<IndexedTable>> listTables({bool includeDeleted = false}) {
    if (closeCount > 0) throw StateError('database closed');
    return super.listTables(includeDeleted: includeDeleted);
  }
}

class _NoopVoiceService extends VoiceService {
  @override
  bool get canTrySpeechInput => false;

  @override
  bool get canSpeak => false;

  @override
  bool get isListening => false;

  @override
  bool get isSpeaking => false;

  @override
  String? get lastError => null;

  @override
  Future<bool> startListening(SpeechTextCallback onResult) async => false;

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stopSpeaking() async {}

  @override
  Future<void> close() async {}
}
