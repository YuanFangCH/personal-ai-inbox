import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/agent_usage.dart';
import '../../core/chat_models.dart';
import '../../core/models.dart';
import '../../data/chat_repository.dart';
import '../../data/share_payload.dart';
import '../../services/agent_background_service.dart';
import '../../services/chat_service.dart';
import '../../services/image_input_service.dart';
import '../../services/model_client.dart';
import '../results/result_library.dart';
import 'agent_background_control.dart';
import 'agent_task_store.dart';
import 'auto_record_processor.dart';
import 'table_action_processor.dart';

/// Application module that owns the local AI conversation lifecycle.
///
/// The rest of the app sees immutable conversation/message snapshots and
/// commands. Persistence, model streaming, attachment storage and guarded
/// automatic recording remain implementation details behind this seam.
class ConversationWorkspace extends ChangeNotifier {
  ConversationWorkspace({
    required ChatRepository repository,
    required ResultLibrary results,
    required ChatService chatService,
    required AutoRecordProcessor autoRecordProcessor,
    TableActionProcessor? tableActionProcessor,
    AiPermissions Function()? defaultPermissions,
    AiPolicy Function()? defaultPolicy,
    AgentTaskStore? taskStore,
    AgentBackgroundControl? backgroundAgent,
    ImageInputService? imageInputService,
    Duration streamUiBatchInterval = const Duration(milliseconds: 50),
    Duration streamPersistenceInterval = const Duration(milliseconds: 500),
    Duration Function()? activeUsageElapsedDuration,
  }) : _repository = repository,
       _results = results,
       _chatService = chatService,
       _autoRecordProcessor = autoRecordProcessor,
       _tableActionProcessor = tableActionProcessor,
       _defaultPermissions =
           defaultPermissions ?? (() => const AiPermissions()),
       _defaultPolicy = defaultPolicy,
       _taskStore = taskStore ?? MemoryAgentTaskStore(),
       _backgroundAgent = backgroundAgent ?? DisabledAgentBackgroundControl(),
       _imageInputService = imageInputService ?? ImageInputService(),
       _streamUiBatchInterval = streamUiBatchInterval,
       _streamPersistenceInterval = streamPersistenceInterval,
       _activeUsageElapsedDuration = activeUsageElapsedDuration;

  final ChatRepository _repository;
  final ResultLibrary _results;
  final ChatService _chatService;
  final AutoRecordProcessor _autoRecordProcessor;
  final TableActionProcessor? _tableActionProcessor;
  final AiPermissions Function() _defaultPermissions;
  final AiPolicy Function()? _defaultPolicy;
  final AgentTaskStore _taskStore;
  final AgentBackgroundControl _backgroundAgent;
  final ImageInputService _imageInputService;
  final Duration _streamUiBatchInterval;
  final Duration _streamPersistenceInterval;
  final Duration Function()? _activeUsageElapsedDuration;

  List<Conversation> _conversations = const [];
  final Map<String, List<ChatMessage>> _messagesByConversation = {};
  String? _activeConversationId;
  final Queue<String> _pendingOpenConversationIds = Queue<String>();
  final List<_ChatTurnRequest> _conversationQueue = [];
  final Queue<_ChatTurnRequest> _steeringQueue = Queue<_ChatTurnRequest>();
  _ChatTurnRequest? _activeTurn;
  AgentUsageMeter? _activeUsageMeter;
  String? _runningConversationId;
  Future<void>? _turnWorker;
  Future<void> _taskPersistTail = Future<void>.value();
  Future<void> _auxiliaryUsageTail = Future<void>.value();
  StreamSubscription<AgentBackgroundCommand>? _backgroundCommands;
  String? _backgroundTaskId;
  String? _backgroundWarning;
  bool _backgroundTaskStarted = false;
  AgentUsage _agentUsage = const AgentUsage();
  final Map<String, AgentUsage> _runUsage = {};
  String? _activeRunId;
  bool _hasAssignedUsage = false;
  int _taskSequence = 0;
  bool _taskSchedulerPaused = false;
  bool _handlingIntakeRetry = false;
  final Set<String> _reviewTaskIds = {};
  final Set<String> _recoveredRunningTaskIds = {};
  bool _shuttingDown = false;
  String? _shutdownError;
  StreamSubscription<ChatStreamDelta>? _chatSubscription;
  Completer<void>? _chatStreamDone;
  Completer<void>? _chatGenerationFinished;
  Completer<void>? _generationCancellation;
  final Map<String, Future<void>> _messageSaveQueues = {};
  final Map<String, Future<void>> _generationSaveQueues = {};
  final Map<String, List<AutoRecordAction>> _liveAutoActions = {};
  final Map<String, List<TableChatAction>> _liveTableActions = {};
  Timer? _streamUiFlushTimer;
  Timer? _streamPersistenceTimer;
  Timer? _activeUsageCheckpointTimer;
  bool _cancelChatRequested = false;
  _TaskStopReason? _taskStopReason;
  String? _taskInterruptionReason;
  bool _isChatGenerating = false;
  bool _disposed = false;
  Future<void>? _shutdownFuture;
  bool _chatServiceClosed = false;

  List<Conversation> get conversations => List.unmodifiable(_conversations);

  String? get activeConversationId => _activeConversationId;

  bool get isChatGenerating => _isChatGenerating;

  String? get generatingConversationId => _runningConversationId;

  Future<AiPolicy?> currentRunningPolicy() async {
    final conversationId = _activeTurn?.conversationId;
    if (conversationId == null) return null;
    final conversation = await _repository.findConversation(conversationId);
    return conversation?.effectiveAiPolicy;
  }

  Future<bool> recordAuxiliaryModelRequest() {
    final requestedTurn = _activeTurn;
    final reservation = _auxiliaryUsageTail.then((_) async {
      if (requestedTurn == null || !identical(_activeTurn, requestedTurn)) {
        return false;
      }
      final activeMeter = _activeUsageMeter;
      activeMeter?.recordRequest();
      final candidate =
          activeMeter?.snapshot() ??
          _agentUsage.copyWith(usedRequests: _agentUsage.usedRequests + 1);
      final snapshot = _taskCheckpointSnapshot();
      try {
        await _persistTaskCheckpoint(
          checkpoint: AgentTaskCheckpoint(
            usage: candidate,
            turns: snapshot.turns,
            runUsage: {...snapshot.runUsage, ?_activeRunId: candidate},
            activeRunId: _activeRunId,
          ),
        );
      } catch (_) {
        // Usage is diagnostic; a failed checkpoint must not block execution.
      }
      if (!identical(_activeTurn, requestedTurn)) return false;
      _agentUsage = candidate;
      notifyListeners();
      return true;
    });
    _auxiliaryUsageTail = reservation.then<void>((_) {}, onError: (_, _) {});
    return reservation;
  }

  Future<void> activeCancellationFuture() {
    if (_activeTurn == null) return Future<void>.value();
    return _generationCancellation?.future ?? Future<void>.value();
  }

  bool get hasPendingChatTurns =>
      _steeringQueue.isNotEmpty || _conversationQueue.isNotEmpty;

  AgentUsage get agentUsage => _agentUsage;

  bool get hasTasksNeedingReview => _reviewTaskIds.isNotEmpty;

  Set<String> get tasksNeedingReview => Set.unmodifiable(_reviewTaskIds);

  bool get isTaskSchedulerPaused => _taskSchedulerPaused;

  bool get isHandlingIntakeRetry => _handlingIntakeRetry;

  List<AgentTaskSummary> get tasksNeedingAction {
    final grouped = <String, List<_ChatTurnRequest>>{};
    for (final turn in [..._steeringQueue, ..._conversationQueue]) {
      if (turn.status == AgentTurnCheckpointStatus.paused ||
          turn.status == AgentTurnCheckpointStatus.waitingInput ||
          turn.status == AgentTurnCheckpointStatus.needsReview) {
        grouped.putIfAbsent(turn.effectiveRunId, () => []).add(turn);
      }
    }
    return List.unmodifiable([
      for (final entry in grouped.entries)
        AgentTaskSummary(
          runId: entry.key,
          conversationId: entry.value.first.conversation.id,
          taskIds: List.unmodifiable(entry.value.map((turn) => turn.taskId)),
          needsReview: entry.value.any(
            (turn) => _reviewTaskIds.contains(turn.taskId),
          ),
          awaitingInput: entry.value.any(
            (turn) => turn.status == AgentTurnCheckpointStatus.waitingInput,
          ),
          usage:
              _runUsage[entry.key] ??
              (entry.key == _activeRunId ? _agentUsage : const AgentUsage()),
        ),
    ]);
  }

  AgentUsage usageForTask(String taskId) {
    final turn = _findQueuedTask(taskId);
    if (turn == null) throw StateError('任务已不在等待队列中。');
    return _usageForRun(turn.effectiveRunId);
  }

  AgentTaskStore get taskStore => _taskStore;

  String? get shutdownError => _shutdownError;

  List<String> get pendingChatConversationIds => List.unmodifiable([
    ?_runningConversationId,
    ..._steeringQueue.map((turn) => turn.conversationId),
    ..._conversationQueue.map((turn) => turn.conversationId),
  ]);

  bool isConversationSteering(String conversationId) =>
      _runningConversationId == conversationId &&
      _steeringQueue.any((turn) => turn.conversationId == conversationId);

  bool isConversationQueued(String conversationId) =>
      _steeringQueue.any((turn) => turn.conversationId == conversationId) ||
      _conversationQueue.any((turn) => turn.conversationId == conversationId);

  Future<void> resumeTasks({
    String? taskId,
    bool approveUncertainEffects = false,
  }) async {
    final targetRunId = _targetRunId(taskId);
    final targetTaskIds = _taskIdsForRun(targetRunId);
    final reviewIds = _reviewTaskIds.intersection(targetTaskIds);
    if (reviewIds.isNotEmpty && !approveUncertainEffects) {
      throw AgentTaskReviewRequiredException(Set.unmodifiable(reviewIds));
    }
    final snapshot = _taskCheckpointSnapshot();
    await _persistTaskCheckpoint(
      checkpoint: AgentTaskCheckpoint(
        usage: _agentUsage,
        runUsage: snapshot.runUsage,
        activeRunId: _activeRunId,
        turns: [
          for (final turn in snapshot.turns)
            if (turn.effectiveRunId == targetRunId &&
                (turn.status == AgentTurnCheckpointStatus.paused ||
                    turn.status == AgentTurnCheckpointStatus.waitingInput ||
                    (approveUncertainEffects &&
                        _reviewTaskIds.contains(turn.taskId))))
              turn.copyWith(status: AgentTurnCheckpointStatus.queued)
            else
              turn,
        ],
      ),
    );
    if (approveUncertainEffects) {
      for (final turn in [..._steeringQueue, ..._conversationQueue]) {
        if (turn.effectiveRunId == targetRunId &&
            (_reviewTaskIds.contains(turn.taskId) ||
                turn.status == AgentTurnCheckpointStatus.paused ||
                turn.status == AgentTurnCheckpointStatus.waitingInput)) {
          turn.status = AgentTurnCheckpointStatus.queued;
        }
      }
      _reviewTaskIds.removeAll(reviewIds);
    } else {
      for (final turn in [..._steeringQueue, ..._conversationQueue]) {
        if (turn.effectiveRunId == targetRunId &&
            (turn.status == AgentTurnCheckpointStatus.paused ||
                turn.status == AgentTurnCheckpointStatus.waitingInput)) {
          turn.status = AgentTurnCheckpointStatus.queued;
        }
      }
    }
    _refreshTaskSchedulerPaused();
    _scheduleTurnWorker();
    notifyListeners();
  }

  _ChatTurnRequest? _findQueuedTask(String taskId) {
    for (final turn in [..._steeringQueue, ..._conversationQueue]) {
      if (turn.taskId == taskId) return turn;
    }
    if (_activeTurn?.taskId == taskId) return _activeTurn;
    return null;
  }

  Set<String> _taskIdsForRun(String runId) => {
    for (final turn in [..._steeringQueue, ..._conversationQueue])
      if (turn.effectiveRunId == runId) turn.taskId,
    if (_activeTurn?.effectiveRunId == runId) _activeTurn!.taskId,
  };

  String _targetRunId(String? taskId) {
    if (taskId != null) {
      final turn = _findQueuedTask(taskId);
      if (turn == null) throw StateError('任务已不在等待队列中。');
      return turn.effectiveRunId;
    }
    final actionTasks = tasksNeedingAction;
    if (actionTasks.length == 1) return actionTasks.single.runId;
    if (actionTasks.length > 1) {
      throw StateError('有多个暂停任务，请指定要继续的任务。');
    }
    if (_activeRunId != null) return _activeRunId!;
    return _defaultRunId;
  }

  AgentUsage _usageForRun(String runId) => runId == _defaultRunId
      ? _agentUsage
      : _runUsage[runId] ??
            (runId == _activeRunId ? _agentUsage : const AgentUsage());

  static const _defaultRunId = '__default__';

  void _refreshTaskSchedulerPaused() {
    _taskSchedulerPaused = [..._steeringQueue, ..._conversationQueue].any(
      (turn) =>
          turn.status == AgentTurnCheckpointStatus.paused ||
          turn.status == AgentTurnCheckpointStatus.waitingInput ||
          turn.status == AgentTurnCheckpointStatus.needsReview,
    );
  }

  bool _assistantNeedsUserInput(ChatMessage assistant) {
    if (assistant.tableActions.any(
          (action) =>
              action.status == TableChatActionStatus.pendingConfirmation ||
              action.status == TableChatActionStatus.pendingRetry ||
              action.retryableIntake,
        ) ||
        assistant.actions.any(
          (action) => action.status == AutoRecordStatus.review,
        )) {
      return true;
    }
    for (final item in assistant.toolTranscript) {
      if (item['role'] != 'tool' || item['content'] is! String) continue;
      try {
        final decoded = jsonDecode(item['content'] as String);
        if (decoded is Map &&
            const {
              'waitingConfirmation',
              'waiting_confirmation',
              'conflict',
              'needs_input',
            }.contains(decoded['status'])) {
          return true;
        }
      } on FormatException {
        continue;
      }
    }
    return false;
  }

  List<ChatMessage> messagesFor(String conversationId) {
    return List.unmodifiable(
      _messagesByConversation[conversationId] ?? const [],
    );
  }

  Conversation? findConversation(String id) {
    for (final conversation in _conversations) {
      if (conversation.id == id) {
        return conversation;
      }
    }
    return null;
  }

  Future<void> initialize() async {
    await _repository.initialize();
    await _tableActionProcessor?.reconcileInboxAssignmentJournal();
    await _initializeTaskInfrastructure();
    await _recoverPendingGenerations();
    await _settleRecoveredCompletedTurns();
    await _repository.deleteEmptyConversations();
    await refresh();
  }

  Future<void> _initializeTaskInfrastructure() async {
    await _backgroundAgent.initialize();
    _backgroundCommands ??= _backgroundAgent.commands.listen(
      (command) => unawaited(_handleBackgroundCommand(command)),
    );
    final checkpoint = await _taskStore.load();
    _agentUsage = checkpoint.usage;
    _runUsage.addAll(checkpoint.runUsage);
    _activeRunId = checkpoint.activeRunId;
    _hasAssignedUsage = _runUsage.isNotEmpty;
    var checkpointNeedsSave = false;
    for (final saved in checkpoint.turns) {
      final conversation = await _repository.findConversation(
        saved.conversationId,
      );
      if (conversation == null) continue;
      _taskSequence = saved.sequence >= _taskSequence
          ? saved.sequence + 1
          : _taskSequence;
      var recoveredStatus = saved.status;
      if ((saved.status == AgentTurnCheckpointStatus.running ||
              saved.status == AgentTurnCheckpointStatus.needsReview) &&
          saved.assistantMessageId != null) {
        final completedAssistant = await _completedAssistantForTurn(
          assistantMessageId: saved.assistantMessageId!,
          conversationId: saved.conversationId,
          userMessageId: saved.userMessageId,
        );
        if (completedAssistant != null) {
          if (_assistantNeedsUserInput(completedAssistant)) {
            recoveredStatus = AgentTurnCheckpointStatus.waitingInput;
          } else if (saved.status == AgentTurnCheckpointStatus.running) {
            continue;
          }
        }
      }
      if (saved.status == AgentTurnCheckpointStatus.running &&
          recoveredStatus != AgentTurnCheckpointStatus.waitingInput) {
        _recoveredRunningTaskIds.add(saved.taskId);
      }
      final turn = _ChatTurnRequest(
        taskId: saved.taskId,
        runId: saved.effectiveRunId,
        sequence: saved.sequence,
        conversation: conversation,
        userMessageId: saved.userMessageId,
        thinkingEnabled: saved.thinkingEnabled,
        excludedMessageIds: saved.excludedMessageIds,
        assistantMessageId: saved.assistantMessageId,
        kind: saved.kind,
        status: recoveredStatus == AgentTurnCheckpointStatus.running
            ? AgentTurnCheckpointStatus.needsReview
            : recoveredStatus,
      );
      if (turn.status != saved.status) checkpointNeedsSave = true;
      if (turn.status == AgentTurnCheckpointStatus.needsReview) {
        _reviewTaskIds.add(turn.taskId);
      }
      if (turn.kind == AgentTurnQueueKind.steering) {
        _steeringQueue.addLast(turn);
      } else {
        _conversationQueue.add(turn);
      }
    }
    _refreshTaskSchedulerPaused();
    if (checkpointNeedsSave) await _persistTaskCheckpoint();
  }

  Future<void> _recoverPendingGenerations() async {
    for (final recoveredGeneration
        in await _repository.listRecoverableGenerations()) {
      var generation = recoveredGeneration;
      final assistant = await _repository.findMessage(
        generation.assistantMessageId,
      );
      if (generation.status == GenerationStatus.requesting) {
        if (assistant != null &&
            assistant.status == ChatMessageStatus.streaming) {
          await _repository.saveMessage(
            assistant.copyWith(
              status: ChatMessageStatus.interrupted,
              error: '应用在模型响应完成前关闭；保留原消息，请手动重试。',
              updatedAt: DateTime.now(),
            ),
          );
        }
        await _repository.saveGeneration(
          generation.copyWith(
            status: GenerationStatus.interrupted,
            error: '应用在模型响应完成前关闭；未自动重发请求。',
            updatedAt: DateTime.now(),
          ),
        );
        continue;
      }

      final calls = _toolCallsFrom(generation.toolCalls);
      if (calls.isNotEmpty && assistant == null) {
        await _saveGeneration(
          generation.copyWith(
            error: '工具回执缺少原助手消息；操作未自动重放，任务等待核对。',
            updatedAt: DateTime.now(),
          ),
        );
        continue;
      }
      final executed = await _executePendingToolCalls(
        generation,
        calls,
        completedAt: generation.updatedAt,
        updateVisibleMessages: false,
      );
      generation = executed.generation;
      if (!_hasCompleteToolReceipts(generation, calls)) {
        if (assistant != null) {
          await _repository.saveMessage(
            assistant.copyWith(
              status: ChatMessageStatus.interrupted,
              error: '恢复时未取得每个工具调用的完整持久回执；任务等待核对。',
              updatedAt: DateTime.now(),
            ),
          );
        }
        await _saveGeneration(
          generation.copyWith(
            status: GenerationStatus.responseReady,
            error: '恢复时未取得每个工具调用的完整持久回执；任务等待核对。',
            updatedAt: DateTime.now(),
          ),
        );
        continue;
      }
      final completedMessage =
          (assistant ??
                  ChatMessage(
                    id: generation.assistantMessageId,
                    conversationId: generation.conversationId,
                    role: ChatRole.assistant,
                    content: generation.responseText,
                    status: ChatMessageStatus.streaming,
                    createdAt: generation.createdAt,
                    updatedAt: generation.updatedAt,
                  ))
              .copyWith(
                content: generation.responseText,
                status: ChatMessageStatus.complete,
                actions: executed.autoActions,
                tableActions: executed.tableActions,
                updatedAt: DateTime.now(),
                error: null,
              );
      await _repository.saveMessage(completedMessage);
      await _repository.saveGeneration(
        generation.copyWith(
          status: GenerationStatus.completed,
          updatedAt: DateTime.now(),
          error: null,
        ),
      );
    }

    // Cover a crash after the streaming message was saved but before the
    // generation row was inserted. It is never safe to resend automatically.
    for (final conversation in await _repository.listConversations()) {
      for (final message in await _repository.listMessages(conversation.id)) {
        if (message.role == ChatRole.assistant &&
            message.status == ChatMessageStatus.streaming &&
            await _repository.findGeneration(message.id) == null) {
          await _repository.saveMessage(
            message.copyWith(
              status: ChatMessageStatus.interrupted,
              error: '应用在模型响应完成前关闭；保留原消息，请手动重试。',
              updatedAt: DateTime.now(),
            ),
          );
        }
      }
    }
  }

  Future<ChatMessage?> _completedAssistantForTurn({
    required String assistantMessageId,
    required String conversationId,
    required String userMessageId,
  }) async {
    final assistant = await _repository.findMessage(assistantMessageId);
    final user = await _repository.findMessage(userMessageId);
    final generation = await _repository.findGeneration(assistantMessageId);
    if (assistant?.id == assistantMessageId &&
        assistant?.conversationId == conversationId &&
        assistant?.role == ChatRole.assistant &&
        assistant?.status == ChatMessageStatus.complete &&
        user?.id == userMessageId &&
        user?.conversationId == conversationId &&
        user?.role == ChatRole.user &&
        generation?.assistantMessageId == assistantMessageId &&
        generation?.conversationId == conversationId &&
        generation?.userMessageId == userMessageId &&
        generation?.status == GenerationStatus.completed) {
      return assistant;
    }
    return null;
  }

  Future<void> _settleRecoveredCompletedTurns() async {
    var changed = false;
    for (final turn in [..._steeringQueue, ..._conversationQueue]) {
      if (turn.assistantMessageId == null) continue;
      var completedAssistant = await _completedAssistantForTurn(
        assistantMessageId: turn.assistantMessageId!,
        conversationId: turn.conversationId,
        userMessageId: turn.userMessageId,
      );
      if (completedAssistant == null) {
        continue;
      }
      if (!await _reconcileRecoveredIntakeReceipts(completedAssistant)) {
        turn.status = AgentTurnCheckpointStatus.needsReview;
        _reviewTaskIds.add(turn.taskId);
        _recoveredRunningTaskIds.remove(turn.taskId);
        changed = true;
        continue;
      }
      completedAssistant =
          await _repository.findMessage(completedAssistant.id) ??
          completedAssistant;
      if (_assistantNeedsUserInput(completedAssistant)) {
        if (turn.status != AgentTurnCheckpointStatus.waitingInput) {
          turn.status = AgentTurnCheckpointStatus.waitingInput;
          _reviewTaskIds.remove(turn.taskId);
          changed = true;
        }
        _recoveredRunningTaskIds.remove(turn.taskId);
        continue;
      }
      if (turn.status == AgentTurnCheckpointStatus.waitingInput) {
        // A crash may happen after a waiting action was resolved and its tool
        // receipt saved but before the turn was moved back to queued. Keep the
        // turn visible for an explicit user resume; never dispatch on startup.
        turn.status = AgentTurnCheckpointStatus.paused;
        _recoveredRunningTaskIds.remove(turn.taskId);
        changed = true;
        continue;
      }
      if (!_recoveredRunningTaskIds.contains(turn.taskId)) continue;
      _steeringQueue.remove(turn);
      _conversationQueue.remove(turn);
      _reviewTaskIds.remove(turn.taskId);
      _recoveredRunningTaskIds.remove(turn.taskId);
      changed = true;
    }
    if (changed) {
      _refreshTaskSchedulerPaused();
      await _persistTaskCheckpoint();
    }
  }

  Future<bool> _reconcileRecoveredIntakeReceipts(ChatMessage assistant) async {
    final appliedRetries = assistant.tableActions.where(
      (action) =>
          action.operation == 'content.create' &&
          action.status == TableChatActionStatus.applied &&
          !action.retryableIntake &&
          !action.intakeRetryPending &&
          action.intakeRetryOperationId?.isNotEmpty == true,
    );
    for (final action in appliedRetries) {
      final fingerprint = action.requestFingerprint;
      final generation = await _repository.findGeneration(assistant.id);
      if (fingerprint == null || fingerprint.isEmpty || generation == null) {
        return false;
      }
      final matches =
          <(Map<String, String>, Map<String, dynamic>, Map<String, dynamic>)>[];
      for (final stored in generation.toolCalls) {
        final rawAction = stored['completed_action_json'];
        final rawReceipt = stored['completed_receipt_json'];
        if (rawAction == null) {
          if (stored['name'] == 'content.create') return false;
          continue;
        }
        final Map<String, dynamic> decodedAction;
        try {
          decodedAction = Map<String, dynamic>.from(
            jsonDecode(rawAction) as Map,
          );
        } on Object {
          if (stored['name'] == 'content.create') return false;
          continue;
        }
        if (decodedAction['id'] != action.id) continue;
        if (rawReceipt == null) return false;
        try {
          final decodedReceipt = Map<String, dynamic>.from(
            jsonDecode(rawReceipt) as Map,
          );
          matches.add((stored, decodedAction, decodedReceipt));
        } on Object {
          return false;
        }
      }
      if (matches.length != 1) return false;
      final (stored, decodedAction, receipt) = matches.single;
      final callId = stored['id'];
      final matchingGenerationCalls = generation.toolCalls
          .where((toolCall) => toolCall['id'] == callId)
          .length;
      final matchingTranscript = assistant.toolTranscript
          .where(
            (item) => item['role'] == 'tool' && item['tool_call_id'] == callId,
          )
          .length;
      if (stored['name'] != 'content.create' ||
          stored['completed_action_kind'] != 'table' ||
          callId == null ||
          callId.isEmpty ||
          matchingGenerationCalls != 1 ||
          matchingTranscript != 1 ||
          decodedAction['request_fingerprint'] != fingerprint) {
        return false;
      }

      final receiptStatus = receipt['status'];
      if (receiptStatus == 'conflict') {
        final priorOperationId =
            decodedAction['intake_retry_operation_id']?.toString() ??
            decodedAction['id']?.toString();
        final data = receipt['data'];
        if (decodedAction['retryable_intake'] != true ||
            priorOperationId == null ||
            receipt['operation_id'] != priorOperationId ||
            data is! Map ||
            data['id'] != action.id ||
            data['request_fingerprint'] != fingerprint ||
            data['intake_retry_operation_id'] !=
                decodedAction['intake_retry_operation_id']) {
          return false;
        }
      } else if (receiptStatus == 'succeeded') {
        final data = receipt['data'];
        if (receipt['operation_id'] != action.id ||
            decodedAction['status'] != TableChatActionStatus.applied.name ||
            decodedAction['intake_retry_operation_id'] !=
                action.intakeRetryOperationId ||
            data is! Map ||
            data['id'] != action.id ||
            data['request_fingerprint'] != fingerprint ||
            data['intake_retry_operation_id'] !=
                action.intakeRetryOperationId) {
          return false;
        }
      } else {
        return false;
      }
      await _replacePersistedToolReceipt(assistant.id, action);
    }
    return true;
  }

  List<ToolCallAccumulator> _toolCallsFrom(List<Map<String, String>> values) {
    return [
      for (final value in values)
        ToolCallAccumulator()
          ..index = int.tryParse(value['index'] ?? '')
          ..id = value['id']
          ..name = value['name']
          ..arguments.write(value['arguments'] ?? ''),
    ];
  }

  bool _hasCompleteToolReceipts(
    GenerationRun generation,
    List<ToolCallAccumulator> calls,
  ) {
    return calls.every((call) {
      final storedCall = _findStoredCall(generation, call);
      final rawReceipt = storedCall?['completed_receipt_json'];
      if (rawReceipt == null || rawReceipt.isEmpty) return false;
      try {
        final decoded = jsonDecode(rawReceipt);
        if (decoded is! Map) return false;
        final status = decoded['status'];
        if (status is! String ||
            !ChatWriteToolOutcome.values.any(
              (outcome) => outcome.name == status,
            ) ||
            decoded['message'] is! String ||
            decoded['retryable'] is! bool ||
            decoded['data'] is! Map) {
          return false;
        }
        return switch (status) {
          'succeeded' || 'waitingConfirmation' || 'conflict' =>
            decoded['operation_id'] is String &&
                (decoded['operation_id'] as String).isNotEmpty,
          'failed' || 'rejected' =>
            decoded['code'] is String && (decoded['code'] as String).isNotEmpty,
          _ => false,
        };
      } on FormatException {
        return false;
      }
    });
  }

  List<Map<String, String>> _mergeToolLedger(
    List<Map<String, String>> persisted,
    Iterable<ToolCallAccumulator> streamed,
  ) {
    final values = <Map<String, String>>[
      for (final call in persisted) Map<String, String>.from(call),
    ];
    for (final call in streamed) {
      final incoming = <String, String>{
        'index': (call.index ?? values.length).toString(),
        if (call.id != null) 'id': call.id!,
        if (call.name != null) 'name': call.name!,
        'arguments': call.arguments.toString(),
      };
      final index = values.indexWhere((stored) {
        final sameId =
            incoming['id'] != null &&
            incoming['id']!.isNotEmpty &&
            stored['id'] == incoming['id'];
        final sameIndex =
            stored['index'] != null && stored['index'] == incoming['index'];
        return sameId || (incoming['id'] == null && sameIndex);
      });
      if (index < 0) {
        values.add(incoming);
      } else {
        values[index] = {...values[index], ...incoming};
      }
    }
    return List.unmodifiable(values);
  }

  Future<void> refresh() async {
    _conversations = await _repository.listConversations();
    if (_activeConversationId != null &&
        findConversation(_activeConversationId!) == null) {
      _activeConversationId = null;
    }
    notifyListeners();
  }

  Future<Conversation> createConversation({
    AiPermissions? permissions,
    AiPolicy? policy,
  }) async {
    final effectivePolicy =
        policy ??
        (permissions == null
            ? _defaultPolicy?.call() ??
                  AiPolicy.fromLegacyPermissions(_defaultPermissions())
            : AiPolicy.fromLegacyPermissions(permissions));
    final conversation = await _repository.createConversation(
      aiPermissions:
          permissions ?? effectivePolicy.legacyCompatibilityPermissions,
      aiPolicy: effectivePolicy,
    );
    _conversations = [
      conversation,
      ..._conversations.where((item) => item.id != conversation.id),
    ];
    _messagesByConversation[conversation.id] = [];
    _activeConversationId = conversation.id;
    notifyListeners();
    return conversation;
  }

  Future<void> setAiPolicy(String conversationId, AiPolicy policy) async {
    final updated = await _repository.setAiPolicy(conversationId, policy);
    if (updated == null) throw StateError('对话不存在：$conversationId');
    _replaceConversation(updated);
    notifyListeners();
  }

  Future<void> setConversationPermissions(
    String conversationId,
    AiPermissions permissions,
  ) async {
    await setAiPolicy(
      conversationId,
      AiPolicy.fromLegacyPermissions(permissions),
    );
  }

  /// Executes one write tool at the point ChatService receives its receipt.
  ///
  /// [ChatWriteToolCall.turnId] is the assistant message ID. The action is
  /// saved on the message and in the generation ledger before the receipt is
  /// returned to the model, so a later request or restart can reuse it.
  Future<ChatWriteToolReceipt> executeWriteTool(ChatWriteToolCall call) async {
    final callIndex = ToolCallAccumulator()
      ..index = call.index
      ..id = call.callId
      ..name = call.name
      ..arguments.write(call.rawArguments);
    final result = await _executeToolAction(call.turnId, callIndex);
    return result.receipt;
  }

  Future<List<ChatAttachmentInput>> pickImagesFromGallery({
    int limit = ImageInputService.maxImagesPerMessage,
  }) => _imageInputService.pickFromGallery(limit: limit);

  Future<List<ChatAttachmentInput>> pickImageFromCamera() =>
      _imageInputService.pickFromCamera();

  String? consumePendingConversationId() {
    return _pendingOpenConversationIds.isEmpty
        ? null
        : _pendingOpenConversationIds.removeFirst();
  }

  Future<void> openConversation(String id) async {
    _activeConversationId = id;
    _messagesByConversation[id] = await _repository.listMessages(id);
    notifyListeners();
  }

  Future<void> renameConversation(String id, String title) async {
    final conversation = await _repository.findConversation(id);
    final normalized = title.trim();
    if (conversation == null || normalized.isEmpty) {
      return;
    }
    final updated = conversation.copyWith(
      title: normalized,
      autoTitle: false,
      updatedAt: DateTime.now(),
    );
    await _repository.saveConversation(updated);
    await refresh();
  }

  Future<void> deleteConversation(String id) async {
    await cancelGeneration(conversationId: id);
    await _repository.deleteConversation(id);
    _messagesByConversation.remove(id);
    if (_activeConversationId == id) {
      _activeConversationId = null;
    }
    await refresh();
  }

  Future<void> handleSharedPayload(SharedCapturePayload payload) async {
    if (payload.isEmpty) {
      return;
    }
    final rawImages = await payload.readImages();
    final images = await _imageInputService.fromBytes(rawImages);
    final conversation = await createConversation();
    _pendingOpenConversationIds.addLast(conversation.id);
    unawaited(
      sendChatMessage(conversation.id, text: payload.text, attachments: images),
    );
    notifyListeners();
  }

  Future<void> sendChatMessage(
    String conversationId, {
    String text = '',
    List<ChatAttachmentInput> attachments = const [],
    bool thinkingEnabled = false,
    VoidCallback? onUserMessageSaved,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty && attachments.isEmpty) {
      return;
    }
    if (_shuttingDown) {
      throw StateError('应用正在关闭，不能发送新的消息。');
    }

    final conversation = await _repository.findConversation(conversationId);
    if (conversation == null) {
      throw StateError('会话不存在或已删除');
    }

    final history = await _repository.listMessages(conversationId);
    final userMessageId = _repository.newMessageId();
    final savedAttachments = await _repository.saveAttachments(
      conversationId: conversationId,
      messageId: userMessageId,
      inputs: attachments,
    );
    final now = DateTime.now();
    final userMessage = ChatMessage(
      id: userMessageId,
      conversationId: conversationId,
      role: ChatRole.user,
      content: normalized,
      status: ChatMessageStatus.complete,
      createdAt: now,
      updatedAt: now,
      attachments: savedAttachments,
    );
    await _saveMessage(userMessage);
    _replaceMessage(userMessage);
    onUserMessageSaved?.call();

    final isFirstUserMessage = !history.any(
      (message) => message.role == ChatRole.user,
    );
    final updatedConversation = conversation.copyWith(
      title: isFirstUserMessage && conversation.autoTitle
          ? _conversationTitle(normalized, attachments)
          : conversation.title,
      autoTitle: isFirstUserMessage && conversation.autoTitle
          ? false
          : conversation.autoTitle,
      preview: _messagePreview(normalized, attachments.isNotEmpty),
      updatedAt: now,
    );
    await _repository.saveConversation(updatedConversation);
    _replaceConversation(updatedConversation);

    final isSteering = _runningConversationId == conversationId;
    final turn = _ChatTurnRequest(
      taskId: _newTaskId(),
      runId: isSteering ? _activeTurn?.effectiveRunId : null,
      sequence: _taskSequence++,
      conversation: updatedConversation,
      userMessageId: userMessage.id,
      thinkingEnabled: thinkingEnabled,
      kind: isSteering
          ? AgentTurnQueueKind.steering
          : AgentTurnQueueKind.conversation,
    );
    if (isSteering) {
      _steeringQueue.addLast(turn);
      if (_backgroundTaskId != null) {
        unawaited(
          _updateBackgroundTask(
            _backgroundTaskId!,
            _activeTurn?.conversation ?? conversation,
            text: '已收到补充指令，等待当前安全边界',
            progress: _backgroundProgress,
          ),
        );
      }
    } else {
      _conversationQueue.add(turn);
    }
    await _persistTaskCheckpoint();
    _refreshTaskSchedulerPaused();
    _scheduleTurnWorker();
    notifyListeners();
    await turn.completion.future;
  }

  void _scheduleTurnWorker() {
    if (_turnWorker != null || _shuttingDown || _handlingIntakeRetry) return;
    late final Future<void> worker;
    worker = _runTurnWorker();
    _turnWorker = worker;
    unawaited(
      worker.whenComplete(() {
        if (identical(_turnWorker, worker)) {
          _turnWorker = null;
        }
        if (!_shuttingDown && _hasRunnableTurn) {
          _scheduleTurnWorker();
        }
      }),
    );
  }

  String _newTaskId() =>
      'agent_${DateTime.now().microsecondsSinceEpoch}_$_taskSequence';

  Future<void> _runTurnWorker() async {
    while (!_shuttingDown) {
      final turn = _takeNextTurn();
      if (turn == null) {
        _runningConversationId = null;
        notifyListeners();
        return;
      }
      if (_activeRunId != turn.effectiveRunId) {
        if (_activeRunId != null) _runUsage[_activeRunId!] = _agentUsage;
        _activeRunId = turn.effectiveRunId;
        _agentUsage =
            _runUsage[_activeRunId] ??
            (_hasAssignedUsage ? const AgentUsage() : _agentUsage);
        _hasAssignedUsage = true;
      }
      _runningConversationId = turn.conversation.id;
      _activeTurn = turn;
      _taskStopReason = null;
      _taskInterruptionReason = null;
      _cancelChatRequested = false;
      turn.status = AgentTurnCheckpointStatus.running;
      turn.assistantMessageId ??= _repository.newMessageId();
      await _promoteQueuedTurnsFor(turn.conversation.id);
      await _persistTaskCheckpoint();
      notifyListeners();
      try {
        if (turn.cancelledBeforeDispatch) {
          await _persistQueuedTurnCancellation(
            turn,
            reason: '已取消：模型请求尚未发送。',
            completeTurn: false,
          );
          await _persistTaskCheckpoint();
          if (!turn.completion.isCompleted) turn.completion.complete();
          continue;
        }
        await _generateReply(
          turn.conversation.id,
          turn.conversation,
          userMessageId: turn.userMessageId,
          assistantMessageId: turn.assistantMessageId!,
          thinkingEnabled: turn.thinkingEnabled,
          excludedMessageIds: turn.excludedMessageIds,
        );
        final assistant = await _repository.findMessage(
          turn.assistantMessageId!,
        );
        switch (assistant?.status) {
          case ChatMessageStatus.complete:
            if (assistant != null && _assistantNeedsUserInput(assistant)) {
              turn.status = AgentTurnCheckpointStatus.waitingInput;
              _requeueTurn(turn);
              _pauseQueuedTurnsForRun(
                turn.effectiveRunId,
                status: AgentTurnCheckpointStatus.waitingInput,
              );
            } else {
              turn.settled = true;
              _reviewTaskIds.remove(turn.taskId);
            }
          case ChatMessageStatus.failed:
            turn.status = AgentTurnCheckpointStatus.needsReview;
            _reviewTaskIds.add(turn.taskId);
            _requeueTurn(turn);
            _pauseQueuedTurnsForRun(turn.effectiveRunId);
          case ChatMessageStatus.interrupted:
            if (_taskStopReason == _TaskStopReason.pause) {
              turn.status = AgentTurnCheckpointStatus.paused;
              _requeueTurn(turn);
              _pauseQueuedTurnsForRun(turn.effectiveRunId);
            } else if (_taskStopReason == _TaskStopReason.cancel) {
              turn.settled = true;
              _reviewTaskIds.remove(turn.taskId);
            } else {
              turn.status = AgentTurnCheckpointStatus.needsReview;
              _reviewTaskIds.add(turn.taskId);
              _requeueTurn(turn);
              _pauseQueuedTurnsForRun(turn.effectiveRunId);
            }
          case ChatMessageStatus.streaming || null:
            turn.status = AgentTurnCheckpointStatus.needsReview;
            _reviewTaskIds.add(turn.taskId);
            _requeueTurn(turn);
            _pauseQueuedTurnsForRun(turn.effectiveRunId);
        }
        _refreshTaskSchedulerPaused();
        await _persistTaskCheckpoint();
        if (!turn.completion.isCompleted) {
          turn.completion.complete();
        }
      } on Object catch (error, stackTrace) {
        turn.status = AgentTurnCheckpointStatus.needsReview;
        _reviewTaskIds.add(turn.taskId);
        _requeueTurn(turn);
        _pauseQueuedTurnsForRun(turn.effectiveRunId);
        _refreshTaskSchedulerPaused();
        var completionError = error;
        var completionStackTrace = stackTrace;
        try {
          await _persistTaskCheckpoint();
        } on Object catch (checkpointError, checkpointStackTrace) {
          // Preserve the in-memory needsReview state, report the failed
          // settlement, and still release callers waiting for this turn.
          completionError = checkpointError;
          completionStackTrace = checkpointStackTrace;
        } finally {
          if (!turn.completion.isCompleted) {
            turn.completion.completeError(
              completionError,
              completionStackTrace,
            );
          }
        }
      } finally {
        _activeTurn = null;
        _runningConversationId = null;
        notifyListeners();
      }
    }
  }

  _ChatTurnRequest? _takeNextTurn() {
    final steering = _steeringQueue.where(_isRunnableQueuedTurn).firstOrNull;
    if (steering != null) {
      _steeringQueue.remove(steering);
      return steering;
    }
    final conversation = _conversationQueue
        .where(_isRunnableQueuedTurn)
        .firstOrNull;
    if (conversation == null) return null;
    _conversationQueue.remove(conversation);
    return conversation;
  }

  bool get _hasRunnableTurn =>
      _steeringQueue.any(_isRunnableQueuedTurn) ||
      _conversationQueue.any(_isRunnableQueuedTurn);

  bool _isRunnableQueuedTurn(_ChatTurnRequest turn) =>
      turn.status == AgentTurnCheckpointStatus.queued &&
      ![..._steeringQueue, ..._conversationQueue].any(
        (other) =>
            other.effectiveRunId == turn.effectiveRunId &&
            (other.status == AgentTurnCheckpointStatus.paused ||
                other.status == AgentTurnCheckpointStatus.waitingInput ||
                other.status == AgentTurnCheckpointStatus.needsReview),
      );

  void _pauseQueuedTurnsForRun(
    String runId, {
    AgentTurnCheckpointStatus status = AgentTurnCheckpointStatus.paused,
  }) {
    for (final turn in [..._steeringQueue, ..._conversationQueue]) {
      if (turn.effectiveRunId == runId &&
          turn.status == AgentTurnCheckpointStatus.queued) {
        turn.status = status;
      }
    }
  }

  void _requeueTurn(_ChatTurnRequest turn) {
    if (turn.kind == AgentTurnQueueKind.steering) {
      _steeringQueue.addFirst(turn);
    } else {
      _conversationQueue.insert(0, turn);
    }
  }

  Future<void> _promoteQueuedTurnsFor(String conversationId) async {
    final promoted = <_ChatTurnRequest>[];
    _conversationQueue.removeWhere((turn) {
      if (turn.conversation.id != conversationId ||
          turn.status != AgentTurnCheckpointStatus.queued) {
        return false;
      }
      promoted.add(turn);
      return true;
    });
    for (final turn in promoted) {
      turn.runId = _activeTurn?.effectiveRunId;
      turn.kind = AgentTurnQueueKind.steering;
      turn.status = AgentTurnCheckpointStatus.queued;
      _steeringQueue.addLast(turn);
    }
    if (promoted.isNotEmpty) {
      await _persistTaskCheckpoint();
    }
  }

  Future<void> _generateReply(
    String conversationId,
    Conversation updatedConversation, {
    required String userMessageId,
    required String assistantMessageId,
    bool thinkingEnabled = false,
    Set<String> excludedMessageIds = const {},
  }) async {
    final now = DateTime.now();
    final previousAssistant = await _repository.findMessage(assistantMessageId);
    var assistant =
        previousAssistant?.copyWith(
          status: ChatMessageStatus.streaming,
          error: null,
          updatedAt: now,
        ) ??
        ChatMessage(
          id: assistantMessageId,
          conversationId: conversationId,
          role: ChatRole.assistant,
          content: '',
          status: ChatMessageStatus.streaming,
          createdAt: now,
          updatedAt: now,
        );
    await _saveMessage(assistant);
    _replaceMessage(assistant);
    final previousGeneration = await _repository.findGeneration(
      assistantMessageId,
    );
    var generation =
        previousGeneration?.copyWith(
          status: GenerationStatus.requesting,
          error: null,
          updatedAt: now,
        ) ??
        GenerationRun(
          assistantMessageId: assistantMessageId,
          conversationId: conversationId,
          userMessageId: userMessageId,
          status: GenerationStatus.requesting,
          responseText: '',
          toolCalls: const [],
          createdAt: now,
          updatedAt: now,
        );
    await _repository.saveGeneration(generation);

    _isChatGenerating = true;
    _chatGenerationFinished = Completer<void>();
    final cancellation = Completer<void>();
    _generationCancellation = cancellation;
    _activeConversationId = conversationId;
    notifyListeners();

    final toolCalls = <int, ToolCallAccumulator>{};
    final reasoningContent = StringBuffer();
    final toolTranscript = <Map<String, dynamic>>[];
    final usageMeter = AgentUsageMeter(
      initial: _agentUsage,
      activeElapsedDuration: _activeUsageElapsedDuration,
    );
    _activeUsageMeter = usageMeter;
    var persistenceDirty = false;
    ChatStreamTermination? termination;
    final done = Completer<void>();
    _chatStreamDone = done;

    Future<void> persistSnapshot() async {
      persistenceDirty = false;
      _syncAgentUsage(usageMeter);
      final snapshot = _withLiveToolActions(assistant);
      await _saveMessage(snapshot);
      final storedGeneration = await _repository.findGeneration(
        assistantMessageId,
      );
      generation = generation.copyWith(
        responseText: snapshot.content,
        toolCalls: storedGeneration?.toolCalls ?? generation.toolCalls,
        updatedAt: DateTime.now(),
      );
      await _saveGeneration(generation);
      if (persistenceDirty && _streamPersistenceTimer == null) {
        _streamPersistenceTimer = Timer(
          _streamPersistenceInterval,
          () => unawaited(persistSnapshot()),
        );
      }
      await _persistTaskCheckpoint();
    }

    void schedulePersistence() {
      persistenceDirty = true;
      _streamPersistenceTimer ??= Timer(_streamPersistenceInterval, () {
        _streamPersistenceTimer = null;
        unawaited(persistSnapshot());
      });
    }

    Future<void> flushPersistence() async {
      _streamPersistenceTimer?.cancel();
      _streamPersistenceTimer = null;
      if (persistenceDirty) {
        await persistSnapshot();
      }
    }

    try {
      // A restricted Android service start can request a pause from inside
      // startTask. Establish the generation and cancellation state first so the
      // command checkpoints and interrupts this same turn instead of being
      // dropped as a pre-generation pause. Keep startup inside the shared
      // terminal path so persistence errors cannot leave generation locked.
      await _startBackgroundTask(assistant, updatedConversation);
      final prepared = _cancelChatRequested
          ? null
          : await _awaitCancellable(
              _chatService.streamReply(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                excludedMessageIds: excludedMessageIds,
                thinkingEnabled: thinkingEnabled,
                usage: usageMeter,
                isCancelled: () => cancellation.isCompleted,
                cancellationSignal: cancellation.future,
                resumeToolTranscript: assistant.toolTranscript,
                persistToolTranscript: (transcript) async {
                  final checkpointedAssistant = assistant.copyWith(
                    toolTranscript: transcript,
                    updatedAt: DateTime.now(),
                  );
                  await _saveMessage(
                    _withLiveToolActions(checkpointedAssistant),
                  );
                  await _persistTaskCheckpoint();
                  assistant = checkpointedAssistant;
                  _replaceMessage(assistant);
                },
              ),
              cancellation,
            );
      final stream = prepared;
      if (stream != null && !_cancelChatRequested) {
        _chatSubscription = stream.listen(
          (delta) {
            if (_cancelChatRequested || termination != null) {
              return;
            }
            if (delta.termination != null) {
              termination = delta.termination;
            }
            if (delta.content.isNotEmpty) {
              assistant = assistant.copyWith(
                content: '${assistant.content}${delta.content}',
                updatedAt: DateTime.now(),
              );
              _replaceMessage(assistant);
            }
            if (delta.reasoningContent.isNotEmpty) {
              reasoningContent.write(delta.reasoningContent);
            }
            if (delta.toolTranscript.isNotEmpty) {
              toolTranscript.addAll(delta.toolTranscript);
            }
            if (delta.toolCallIndex != null) {
              final index = delta.toolCallIndex!;
              final current = toolCalls.putIfAbsent(
                index,
                ToolCallAccumulator.new,
              );
              current
                ..index = index
                ..id = delta.toolCallId ?? current.id
                ..name = delta.toolCallName ?? current.name
                ..arguments.write(delta.toolArguments);
              unawaited(
                _updateBackgroundTask(
                  assistantMessageId,
                  updatedConversation,
                  text: '正在执行工具：${current.name ?? '未知工具'}',
                  progress: _backgroundProgress,
                ),
              );
            }
            schedulePersistence();
            _syncAgentUsage(usageMeter);
            _notifySoon();
            if (termination != null && !done.isCompleted) {
              done.complete();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!done.isCompleted) {
              done.completeError(error, stackTrace);
            }
          },
          onDone: () {
            if (!done.isCompleted) {
              done.complete();
            }
          },
          cancelOnError: false,
        );
        var checkpointInFlight = false;
        _activeUsageCheckpointTimer?.cancel();
        _activeUsageCheckpointTimer = Timer.periodic(
          _streamPersistenceInterval,
          (_) {
            if (checkpointInFlight ||
                !_isChatGenerating ||
                _cancelChatRequested) {
              return;
            }
            checkpointInFlight = true;
            _syncAgentUsage(usageMeter);
            unawaited(
              _persistTaskCheckpoint()
                  .catchError((Object error) {
                    _backgroundWarning ??= '活动用量检查点保存失败：$error';
                  })
                  .whenComplete(() => checkpointInFlight = false),
            );
          },
        );
        await done.future;
      }

      await flushPersistence();
      if (_cancelChatRequested) {
        assistant = assistant.copyWith(
          status: ChatMessageStatus.interrupted,
          error: _taskInterruptionReason ?? '已停止生成；已保存当前进度，没有继续派发新的工具或写入。',
          updatedAt: DateTime.now(),
        );
      } else if (termination != ChatStreamTermination.completed) {
        assistant = assistant.copyWith(
          status: ChatMessageStatus.failed,
          error: _terminationMessage(termination),
          updatedAt: DateTime.now(),
        );
      } else {
        assistant = assistant.copyWith(
          reasoningContent: reasoningContent.toString(),
          toolTranscript: List.unmodifiable(toolTranscript),
          updatedAt: DateTime.now(),
        );
        await _saveMessage(assistant);
        _replaceMessage(assistant);
        final persistedGeneration = await _repository.findGeneration(
          assistantMessageId,
        );
        generation = generation.copyWith(
          status: GenerationStatus.responseReady,
          responseText: assistant.content,
          toolCalls: _mergeToolLedger(
            persistedGeneration?.toolCalls ?? const [],
            toolCalls.values,
          ),
          updatedAt: DateTime.now(),
          error: _backgroundWarning,
        );
        await _repository.saveGeneration(generation);
        final executed = await _executePendingToolCalls(
          generation,
          _toolCallsFrom(generation.toolCalls),
          completedAt: generation.updatedAt,
        );
        generation = executed.generation;
        final actionSummary = _emptyReplySummary(
          executed.autoActions,
          executed.tableActions,
        );
        assistant = assistant.copyWith(
          status: ChatMessageStatus.complete,
          content: assistant.content.trim().isEmpty
              ? actionSummary
              : assistant.content,
          actions: executed.autoActions,
          tableActions: executed.tableActions,
          updatedAt: DateTime.now(),
          error: null,
        );
        if (assistant.content.trim().isEmpty) {
          assistant = assistant.copyWith(
            status: ChatMessageStatus.failed,
            error: '模型完整结束，但没有返回可展示文字或可执行工具结果；请重试。',
          );
        }
      }
    } catch (error) {
      try {
        await flushPersistence();
      } catch (_) {
        // The explicit terminal state below remains visible even if a partial
        // streaming snapshot could not be written.
      }
      assistant = _cancelChatRequested
          ? assistant.copyWith(
              status: ChatMessageStatus.interrupted,
              error: _taskInterruptionReason ?? '已停止生成；已保存当前进度，没有继续派发新的工具或写入。',
              updatedAt: DateTime.now(),
            )
          : assistant.copyWith(
              status: ChatMessageStatus.failed,
              error: _friendlyChatError(error),
              updatedAt: DateTime.now(),
            );
    } finally {
      usageMeter.pauseActivity();
      _syncAgentUsage(usageMeter);
      if (identical(_activeUsageMeter, usageMeter)) _activeUsageMeter = null;
      _activeUsageCheckpointTimer?.cancel();
      _activeUsageCheckpointTimer = null;
      _streamPersistenceTimer?.cancel();
      _streamPersistenceTimer = null;
      try {
        await _finalizeBackgroundTask(assistant);
        assistant = _withBackgroundWarning(assistant);
        assistant = _withLiveToolActions(assistant);
        await _saveMessage(assistant);
        _replaceMessage(assistant);
        final latestConversation =
            await _repository.findConversation(conversationId) ??
            updatedConversation;
        final withPreview = latestConversation.copyWith(
          preview: _messagePreview(assistant.content, false),
          updatedAt: DateTime.now(),
        );
        await _repository.saveConversation(withPreview);
        _replaceConversation(withPreview);
        if (generation.status == GenerationStatus.responseReady &&
            assistant.status == ChatMessageStatus.complete) {
          await _saveGeneration(
            generation.copyWith(
              status: GenerationStatus.completed,
              responseText: assistant.content,
              updatedAt: DateTime.now(),
              error: _backgroundWarning,
            ),
          );
        } else if (generation.status == GenerationStatus.requesting) {
          await _saveGeneration(
            generation.copyWith(
              status: _cancelChatRequested
                  ? GenerationStatus.interrupted
                  : GenerationStatus.failed,
              responseText: assistant.content,
              updatedAt: DateTime.now(),
              error: assistant.error,
            ),
          );
        }
        _backgroundTaskId = null;
        _backgroundTaskStarted = false;
        _backgroundWarning = null;
      } catch (_) {
        // A persistence error must not leave the workspace locked in streaming.
      } finally {
        final subscription = _chatSubscription;
        _chatSubscription = null;
        _chatStreamDone = null;
        _generationCancellation = null;
        _liveAutoActions.remove(assistantMessageId);
        _liveTableActions.remove(assistantMessageId);
        if (subscription != null) {
          unawaited(subscription.cancel());
        }
        _isChatGenerating = false;
        _cancelChatRequested = false;
        final finished = _chatGenerationFinished;
        _chatGenerationFinished = null;
        _flushUiNotifications();
        notifyListeners();
        if (finished != null && !finished.isCompleted) {
          finished.complete();
        }
      }
    }
  }

  Future<void> _saveMessage(ChatMessage message) {
    final previous = _messageSaveQueues[message.id] ?? Future<void>.value();
    late final Future<void> queued;
    queued = previous
        .catchError((_) {})
        .then((_) => _repository.saveMessage(message))
        .whenComplete(() {
          if (identical(_messageSaveQueues[message.id], queued)) {
            _messageSaveQueues.remove(message.id);
          }
        });
    _messageSaveQueues[message.id] = queued;
    return queued;
  }

  Future<void> _saveGeneration(GenerationRun generation) {
    final id = generation.assistantMessageId;
    final previous = _generationSaveQueues[id] ?? Future<void>.value();
    late final Future<void> queued;
    queued = previous
        .catchError((_) {})
        .then((_) async {
          final current = await _repository.findGeneration(id);
          await _repository.saveGeneration(
            _mergeGenerationWrite(current, generation),
          );
        })
        .whenComplete(() {
          if (identical(_generationSaveQueues[id], queued)) {
            _generationSaveQueues.remove(id);
          }
        });
    _generationSaveQueues[id] = queued;
    return queued;
  }

  Future<void> _persistTaskCheckpoint({AgentTaskCheckpoint? checkpoint}) {
    final snapshot = checkpoint ?? _taskCheckpointSnapshot();
    final next = _taskPersistTail
        .catchError((_) {})
        .then((_) => _taskStore.save(snapshot));
    _taskPersistTail = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }

  AgentTaskCheckpoint _taskCheckpointSnapshot() {
    final turns = <AgentTurnCheckpoint>[
      if (_activeTurn != null &&
          !_activeTurn!.cancelledBeforeDispatch &&
          !_activeTurn!.settled &&
          !_steeringQueue.any((turn) => turn.taskId == _activeTurn!.taskId) &&
          !_conversationQueue.any((turn) => turn.taskId == _activeTurn!.taskId))
        _turnCheckpoint(_activeTurn!, _activeTurn!.status),
      for (final turn in _steeringQueue) _turnCheckpoint(turn, turn.status),
      for (final turn in _conversationQueue) _turnCheckpoint(turn, turn.status),
    ];
    return AgentTaskCheckpoint(
      usage: _agentUsage,
      activeRunId: _activeRunId,
      runUsage: {
        ..._runUsage,
        for (final turn in turns)
          turn.effectiveRunId:
              _runUsage[turn.effectiveRunId] ?? const AgentUsage(),
        ?_activeRunId: _agentUsage,
      },
      turns: List.unmodifiable(turns),
    );
  }

  AgentTurnCheckpoint _turnCheckpoint(
    _ChatTurnRequest turn,
    AgentTurnCheckpointStatus status,
  ) => AgentTurnCheckpoint(
    taskId: turn.taskId,
    runId: turn.effectiveRunId,
    conversationId: turn.conversation.id,
    userMessageId: turn.userMessageId,
    kind: turn.kind,
    status: status,
    sequence: turn.sequence,
    assistantMessageId: turn.assistantMessageId,
    thinkingEnabled: turn.thinkingEnabled,
    excludedMessageIds: turn.excludedMessageIds,
  );

  GenerationRun _mergeGenerationWrite(
    GenerationRun? current,
    GenerationRun incoming,
  ) {
    if (current == null) return incoming;
    final currentTerminal = _isTerminalGeneration(current.status);
    final incomingTerminal = _isTerminalGeneration(incoming.status);
    if (currentTerminal && !incomingTerminal) {
      return current;
    }
    final calls = <String, Map<String, String>>{};
    for (final call in current.toolCalls) {
      calls[_toolLedgerKey(call)] = Map<String, String>.from(call);
    }
    for (final call in incoming.toolCalls) {
      final key = _toolLedgerKey(call);
      final previous = calls[key];
      final merged = <String, String>{...?previous, ...call};
      if (previous != null) {
        for (final field in const [
          'completed_action_kind',
          'completed_action_json',
          'completed_receipt_json',
        ]) {
          final value = previous[field];
          if (value != null && !call.containsKey(field)) {
            merged[field] = value;
          }
        }
      }
      calls[key] = merged;
    }
    final responseText =
        incomingTerminal ||
            incoming.responseText.length >= current.responseText.length
        ? incoming.responseText
        : current.responseText;
    return incoming.copyWith(
      responseText: responseText,
      toolCalls: List.unmodifiable(calls.values),
      error: incomingTerminal ? incoming.error : current.error,
    );
  }

  bool _isTerminalGeneration(GenerationStatus status) =>
      status == GenerationStatus.completed ||
      status == GenerationStatus.interrupted ||
      status == GenerationStatus.failed;

  String _toolLedgerKey(Map<String, String> call) {
    final id = call['id'];
    return id != null && id.isNotEmpty ? 'id:$id' : 'index:${call['index']}';
  }

  Future<T?> _awaitCancellable<T>(
    Future<T> operation,
    Completer<void> cancellation,
  ) {
    final completed = operation.then<T?>((value) => value);
    final cancelled = cancellation.future.then<T?>((_) => null);
    return Future.any<T?>([completed, cancelled]);
  }

  void _notifySoon() {
    _streamUiFlushTimer ??= Timer(_streamUiBatchInterval, () {
      _streamUiFlushTimer = null;
      notifyListeners();
    });
  }

  void _flushUiNotifications() {
    _streamUiFlushTimer?.cancel();
    _streamUiFlushTimer = null;
  }

  ChatMessage _withLiveToolActions(ChatMessage message) {
    final autoActions = _mergeAutoActions([
      ...message.actions,
      ...?_liveAutoActions[message.id],
    ]);
    final tableActions = _mergeTableActions([
      ...message.tableActions,
      ...?_liveTableActions[message.id],
    ]);
    if (autoActions.length == message.actions.length &&
        tableActions.length == message.tableActions.length) {
      return message;
    }
    return message.copyWith(actions: autoActions, tableActions: tableActions);
  }

  List<AutoRecordAction> _mergeAutoActions(Iterable<AutoRecordAction> actions) {
    final byId = <String, AutoRecordAction>{};
    for (final action in actions) {
      byId[action.id] = action;
    }
    return List.unmodifiable(byId.values);
  }

  List<TableChatAction> _mergeTableActions(Iterable<TableChatAction> actions) {
    final byId = <String, TableChatAction>{};
    for (final action in actions) {
      byId[action.id] = action;
    }
    return List.unmodifiable(byId.values);
  }

  Future<_ToolExecutionBatch> _executePendingToolCalls(
    GenerationRun generation,
    List<ToolCallAccumulator> calls, {
    required DateTime completedAt,
    bool updateVisibleMessages = true,
  }) async {
    var currentGeneration = generation;
    final assistant = await _repository.findMessage(
      generation.assistantMessageId,
    );
    final autoActions = <AutoRecordAction>[...?assistant?.actions];
    final tableActions = <TableChatAction>[...?assistant?.tableActions];
    for (final call in calls) {
      if (_cancelChatRequested) {
        await _rememberToolResult(
          generation.assistantMessageId,
          call,
          _ToolActionResult.failed(
            code: 'cancelled_before_dispatch',
            message: '用户停止后，此操作尚未开始，未执行。',
          ),
          actionTime: completedAt,
          updateVisibleMessages: updateVisibleMessages,
        );
        currentGeneration =
            await _repository.findGeneration(generation.assistantMessageId) ??
            currentGeneration;
        continue;
      }
      final result = await _executeToolAction(
        generation.assistantMessageId,
        call,
        completedAt: completedAt,
        generation: currentGeneration,
        updateVisibleMessages: updateVisibleMessages,
      );
      currentGeneration = result.generation ?? currentGeneration;
      final autoAction = result.autoAction;
      if (autoAction != null) {
        autoActions
          ..removeWhere((item) => item.id == autoAction.id)
          ..add(autoAction);
      }
      final tableAction = result.tableAction;
      if (tableAction != null) {
        tableActions
          ..removeWhere((item) => item.id == tableAction.id)
          ..add(tableAction);
      }
    }
    return _ToolExecutionBatch(
      generation: currentGeneration,
      autoActions: _mergeAutoActions(autoActions),
      tableActions: _mergeTableActions(tableActions),
    );
  }

  Future<_ToolActionResult> _executeToolAction(
    String assistantMessageId,
    ToolCallAccumulator call, {
    DateTime? completedAt,
    GenerationRun? generation,
    bool updateVisibleMessages = true,
  }) async {
    final storedGeneration =
        generation ?? await _repository.findGeneration(assistantMessageId);
    final storedCall = storedGeneration == null
        ? null
        : _findStoredCall(storedGeneration, call);
    final storedResult = storedCall == null
        ? null
        : _storedToolResult(storedCall);
    if (storedResult != null) {
      await _acknowledgeInboxAssignmentResult(storedResult);
      return storedResult.copyWith(generation: storedGeneration);
    }

    final assistant = await _repository.findMessage(assistantMessageId);
    if (assistant == null) {
      return _ToolActionResult.failed(
        code: 'assistant_missing',
        message: '回复消息不存在，工具没有执行。',
        generation: storedGeneration,
      );
    }
    final actionTime = completedAt ?? DateTime.now();
    _ToolActionResult result;
    if (call.name == 'propose_global_knowledge_change') {
      final conversation = await _repository.findConversation(
        assistant.conversationId,
      );
      result = conversation == null
          ? _ToolActionResult.failed(
              code: 'conversation_missing',
              message: '会话不存在，全局知识没有写入。',
            )
          : await _executeGlobalKnowledgeTool(
              assistant,
              conversation,
              call,
              actionTime,
            );
    } else if (_tableActionProcessor != null) {
      final tableProcessor = _tableActionProcessor;
      final actions = await tableProcessor.processToolCalls(
        assistantMessageId,
        [call],
        completedAt: actionTime,
      );
      result = actions.isEmpty
          ? _ToolActionResult.failed(
              code: 'unrecognized_tool',
              message: '工具没有产生可保存的表操作回执。',
            )
          : _ToolActionResult.fromTable(actions.single);
    } else {
      final actions = await _autoRecordProcessor.processToolCalls(
        assistantMessageId,
        [call],
        completedAt: actionTime,
      );
      result = actions.isEmpty
          ? _ToolActionResult.failed(
              code: 'unrecognized_tool',
              message: '工具没有产生可保存的成果操作回执。',
            )
          : _ToolActionResult.fromAuto(actions.single);
    }
    await _rememberToolResult(
      assistantMessageId,
      call,
      result,
      actionTime: actionTime,
      updateVisibleMessages: updateVisibleMessages,
    );
    await _acknowledgeInboxAssignmentResult(result);
    return result.copyWith(
      generation: await _repository.findGeneration(assistantMessageId),
    );
  }

  Future<void> _acknowledgeInboxAssignmentResult(
    _ToolActionResult result,
  ) async {
    final action = result.tableAction;
    if (action?.operation == 'table.assign_inbox_target' &&
        action?.status == TableChatActionStatus.applied) {
      await _tableActionProcessor?.acknowledgeInboxAssignmentOperation(action!);
    }
  }

  Future<_ToolActionResult> _executeGlobalKnowledgeTool(
    ChatMessage assistant,
    Conversation conversation,
    ToolCallAccumulator call,
    DateTime actionTime,
  ) async {
    Map<String, dynamic> arguments;
    try {
      final decoded = jsonDecode(call.arguments.toString());
      if (decoded is! Map) {
        return _ToolActionResult.failed(
          code: 'invalid_arguments',
          message: '全局知识工具参数必须是对象。',
        );
      }
      arguments = Map<String, dynamic>.from(decoded);
    } on FormatException {
      return _ToolActionResult.failed(
        code: 'invalid_arguments',
        message: '全局知识工具参数不是有效 JSON。',
      );
    }
    final operation = GlobalKnowledgeOperation.values
        .where((value) => value.name == arguments['operation'])
        .firstOrNull;
    if (operation == null) {
      return _ToolActionResult.failed(
        code: 'invalid_operation',
        message: '全局知识操作类型无效。',
      );
    }
    final permission = switch (operation) {
      GlobalKnowledgeOperation.create =>
        AiPermissionAction.globalKnowledgeCreate,
      GlobalKnowledgeOperation.update =>
        AiPermissionAction.globalKnowledgeUpdate,
      GlobalKnowledgeOperation.delete =>
        AiPermissionAction.globalKnowledgeDelete,
    };
    final targetId = arguments['target_id'] is String
        ? arguments['target_id'] as String
        : null;
    final decision = conversation.effectiveAiPolicy.decisionFor(
      permission,
      knowledgeId: targetId,
    );
    if (decision == AiPolicyDecision.deny) {
      return _ToolActionResult(
        receipt: ChatWriteToolReceipt.rejected(
          code: 'policy_denied',
          message: '当前会话权限不允许此全局知识操作。',
        ),
      );
    }
    final expectedRevision = arguments['expected_revision'] is num
        ? (arguments['expected_revision'] as num).toInt()
        : null;
    final expectedHash = targetId == null
        ? null
        : await _results.hashManagedDocument(targetId);
    if (targetId != null && expectedHash == null) {
      return _ToolActionResult.failed(
        code: 'target_missing',
        message: '全局知识目标不存在或不可读取。',
      );
    }
    final messages = await _repository.listMessages(conversation.id);
    ChatMessage? sourceMessage;
    for (final message in messages) {
      if (message.role == ChatRole.user &&
          !message.createdAt.isAfter(assistant.createdAt)) {
        sourceMessage = message;
      }
    }
    try {
      final candidate = await _results.proposeGlobalKnowledgeChange(
        operation: operation,
        proposal: Map<String, Object?>.from(
          arguments['proposal'] as Map? ?? const {},
        ),
        targetId: targetId,
        expectedRevision: expectedRevision,
        expectedHash: expectedHash,
        sourceConversationId: conversation.id,
        sourceMessageId: sourceMessage?.id,
        authorizationSource: decision == AiPolicyDecision.allow
            ? GlobalKnowledgeAuthorizationSource.policy
            : GlobalKnowledgeAuthorizationSource.none,
      );
      final latestConversation = await _repository.findConversation(
        conversation.id,
      );
      final latestDecision = latestConversation?.effectiveAiPolicy.decisionFor(
        permission,
        knowledgeId: targetId,
      );
      if (latestDecision == null || latestDecision == AiPolicyDecision.deny) {
        return _ToolActionResult(
          receipt: ChatWriteToolReceipt.rejected(
            code: 'policy_denied',
            message: '全局知识候选保存期间，当前会话权限已关闭。',
          ),
        );
      }
      if (latestDecision == AiPolicyDecision.ask &&
          candidate.status == GlobalKnowledgeCandidateStatus.pending) {
        return _ToolActionResult(
          receipt: ChatWriteToolReceipt.waitingConfirmation(
            operationId: candidate.id,
            message: '候选已保存，等待你在全局知识中确认后才生效。',
            data: {
              'candidate_id': candidate.id,
              'digest': candidate.digest,
              'operation': operation.name,
            },
          ),
        );
      }
      if (candidate.status == GlobalKnowledgeCandidateStatus.applied) {
        return _ToolActionResult(
          receipt: ChatWriteToolReceipt.succeeded(
            operationId: candidate.id,
            message: '该全局知识操作已应用并读取到原回执。',
            data: {
              'candidate_id': candidate.id,
              'result_id': candidate.resultId,
              'operation': operation.name,
            },
          ),
        );
      }
      if (latestDecision == AiPolicyDecision.allow &&
          candidate.authorizationSource !=
              GlobalKnowledgeAuthorizationSource.policy) {
        return _ToolActionResult(
          receipt: ChatWriteToolReceipt.waitingConfirmation(
            operationId: candidate.id,
            message: '此候选来自此前的待确认操作；需要人工确认后才能生效。',
            data: {
              'candidate_id': candidate.id,
              'digest': candidate.digest,
              'operation': operation.name,
              'authorization_source': candidate.authorizationSource.wireName,
            },
          ),
        );
      }
      final applied = await _results.confirmGlobalKnowledgeChange(
        candidate.id,
        displayedDigest: candidate.digest,
        authorizationSource: latestDecision == AiPolicyDecision.allow
            ? GlobalKnowledgeAuthorizationSource.policy
            : GlobalKnowledgeAuthorizationSource.human,
        authorizationGuard: latestDecision == AiPolicyDecision.allow
            ? () async {
                final current = await _repository.findConversation(
                  conversation.id,
                );
                return current?.effectiveAiPolicy.decisionFor(
                      permission,
                      knowledgeId: targetId,
                    ) ==
                    AiPolicyDecision.allow;
              }
            : null,
      );
      return _ToolActionResult(
        receipt: ChatWriteToolReceipt.succeeded(
          operationId: candidate.id,
          message: switch (operation) {
            GlobalKnowledgeOperation.create => '全局知识已创建并读回。',
            GlobalKnowledgeOperation.update => '全局知识已更新并读回。',
            GlobalKnowledgeOperation.delete => '全局知识已删除并读回。',
          },
          data: {
            'candidate_id': candidate.id,
            'result_id': applied.document.id,
            'revision': applied.document.revision,
            'operation': operation.name,
            'applied_at': actionTime.toIso8601String(),
          },
        ),
      );
    } on Object catch (error) {
      return _ToolActionResult.failed(
        code: 'global_knowledge_failed',
        message: error is StateError ? error.message : '全局知识操作失败：$error',
      );
    }
  }

  Future<void> _rememberToolResult(
    String assistantMessageId,
    ToolCallAccumulator call,
    _ToolActionResult result, {
    required DateTime actionTime,
    required bool updateVisibleMessages,
  }) async {
    if (updateVisibleMessages) {
      _rememberLiveAction(assistantMessageId, result);
    }
    await _persistActionOnMessage(
      assistantMessageId,
      result,
      at: actionTime,
      updateVisibleMessages: updateVisibleMessages,
    );
    final generation = await _repository.findGeneration(assistantMessageId);
    if (generation == null) return;
    final updated = _withCompletedToolResult(generation, call, result);
    await _saveGeneration(updated);
  }

  void _rememberLiveAction(
    String assistantMessageId,
    _ToolActionResult result,
  ) {
    final autoAction = result.autoAction;
    if (autoAction != null) {
      final values = _liveAutoActions.putIfAbsent(
        assistantMessageId,
        () => <AutoRecordAction>[],
      );
      values
        ..removeWhere((item) => item.id == autoAction.id)
        ..add(autoAction);
    }
    final tableAction = result.tableAction;
    if (tableAction != null) {
      final values = _liveTableActions.putIfAbsent(
        assistantMessageId,
        () => <TableChatAction>[],
      );
      values
        ..removeWhere((item) => item.id == tableAction.id)
        ..add(tableAction);
    }
  }

  Future<void> _persistActionOnMessage(
    String assistantMessageId,
    _ToolActionResult result, {
    DateTime? at,
    bool updateVisibleMessages = true,
  }) async {
    if (result.autoAction == null && result.tableAction == null) return;
    final assistant = await _repository.findMessage(assistantMessageId);
    if (assistant == null) return;
    final autoAction = result.autoAction;
    final tableAction = result.tableAction;
    final updated = assistant.copyWith(
      actions: autoAction == null
          ? assistant.actions
          : _mergeAutoActions([...assistant.actions, autoAction]),
      tableActions: tableAction == null
          ? assistant.tableActions
          : _mergeTableActions([...assistant.tableActions, tableAction]),
      updatedAt: at ?? DateTime.now(),
    );
    await _saveMessage(updated);
    if (updateVisibleMessages) {
      _replaceMessage(updated);
    }
  }

  Map<String, String>? _findStoredCall(
    GenerationRun generation,
    ToolCallAccumulator call,
  ) {
    for (final stored in generation.toolCalls) {
      final id = call.id;
      if (id != null && id.isNotEmpty && stored['id'] == id) {
        return stored;
      }
      if ((stored['index'] ?? '') == (call.index?.toString() ?? '')) {
        return stored;
      }
    }
    return null;
  }

  _ToolActionResult? _storedToolResult(Map<String, String> storedCall) {
    final kind = storedCall['completed_action_kind'];
    final rawAction = storedCall['completed_action_json'];
    final rawReceipt = storedCall['completed_receipt_json'];
    Map<String, dynamic>? receiptJson;
    try {
      if (rawReceipt != null && rawReceipt.isNotEmpty) {
        final decoded = jsonDecode(rawReceipt);
        if (decoded is! Map) return null;
        receiptJson = Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      return null;
    }
    final code = receiptJson?['code']?.toString();
    final message = receiptJson?['message']?.toString() ?? '已读取持久化操作回执。';
    try {
      if (kind == 'table' && rawAction != null) {
        final decoded = jsonDecode(rawAction);
        if (decoded is! Map) return null;
        return _ToolActionResult.fromTable(
          TableChatAction.fromJson(Map<String, dynamic>.from(decoded)),
          code: code,
          message: message,
        );
      }
      if (kind == 'auto' && rawAction != null) {
        final decoded = jsonDecode(rawAction);
        if (decoded is! Map) return null;
        return _ToolActionResult.fromAuto(
          AutoRecordAction.fromJson(Map<String, dynamic>.from(decoded)),
          code: code,
          message: message,
        );
      }
      if (kind == 'receipt' && receiptJson != null) {
        return _ToolActionResult.fromReceipt(_receiptFromJson(receiptJson));
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  ChatWriteToolReceipt _receiptFromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final data = rawData is Map
        ? Map<String, Object?>.from(rawData)
        : const <String, Object?>{};
    final operationId = json['operation_id']?.toString();
    final message = json['message']?.toString() ?? '已读取持久化操作回执。';
    final code = json['code']?.toString() ?? 'stored_failure';
    return switch (json['status']) {
      'succeeded' => ChatWriteToolReceipt.succeeded(
        operationId: operationId ?? 'stored_operation',
        message: message,
        data: data,
      ),
      'waitingConfirmation' => ChatWriteToolReceipt.waitingConfirmation(
        operationId: operationId ?? 'stored_confirmation',
        message: message,
        data: data,
      ),
      'conflict' => ChatWriteToolReceipt.conflict(
        operationId: operationId ?? 'stored_conflict',
        message: message,
        data: data,
      ),
      'rejected' => ChatWriteToolReceipt.rejected(
        code: code,
        message: message,
        data: data,
      ),
      _ => ChatWriteToolReceipt.failed(
        code: code,
        message: message,
        retryable: json['retryable'] == true,
        data: data,
      ),
    };
  }

  GenerationRun _withCompletedToolResult(
    GenerationRun generation,
    ToolCallAccumulator call,
    _ToolActionResult result,
  ) {
    final callData = <String, String>{
      'index': (call.index ?? generation.toolCalls.length).toString(),
      if (call.id != null) 'id': call.id!,
      if (call.name != null) 'name': call.name!,
      'arguments': call.arguments.toString(),
      'completed_action_kind': result.autoAction != null
          ? 'auto'
          : result.tableAction != null
          ? 'table'
          : 'receipt',
      if (result.autoAction != null || result.tableAction != null)
        'completed_action_json': jsonEncode(
          result.autoAction?.toJson() ?? result.tableAction!.toJson(),
        ),
      'completed_receipt_json': jsonEncode({
        'status': result.receipt.outcome.name,
        if (result.receipt.operationId != null)
          'operation_id': result.receipt.operationId,
        if (result.receipt.code != null) 'code': result.receipt.code,
        'message': result.receipt.message,
        'retryable': result.receipt.retryable,
        'data': result.receipt.data,
      }),
    };
    final values = <Map<String, String>>[];
    var replaced = false;
    for (final stored in generation.toolCalls) {
      final sameId =
          call.id != null && call.id!.isNotEmpty && stored['id'] == call.id;
      final sameIndex =
          (stored['index'] ?? '') ==
          (call.index ?? generation.toolCalls.length).toString();
      if (sameId || (!sameId && call.id == null && sameIndex)) {
        if (!replaced) {
          values.add(callData);
          replaced = true;
        }
      } else {
        values.add(stored);
      }
    }
    if (!replaced) values.add(callData);
    return generation.copyWith(
      toolCalls: List.unmodifiable(values),
      updatedAt: DateTime.now(),
    );
  }

  String _terminationMessage(ChatStreamTermination? termination) {
    return switch (termination) {
      ChatStreamTermination.empty => '模型返回了空回复（可能只有心跳或隐藏推理），本轮没有可展示内容；请重试。',
      ChatStreamTermination.disconnected => '连接在模型确认完成前中断，本轮没有继续执行后续工具；请重试。',
      ChatStreamTermination.cancelled => '生成已取消；本轮没有继续派发新的工具。',
      ChatStreamTermination.incomplete ||
      null => '模型响应没有完整结束，本轮未执行未确认的后续工具；请重试。',
      ChatStreamTermination.completed => '模型响应没有产生可展示内容；请重试。',
    };
  }

  String _friendlyChatError(Object error) {
    if (error is TimeoutException) {
      return '模型请求超时；本轮已停止，没有继续派发新的工具。请检查网络后重试。';
    }
    if (error is ModelCancelledException) {
      return '生成已取消；本轮没有继续派发新的工具。';
    }
    if (error is ModelStreamProtocolException) {
      return '模型流格式异常；本轮结果不完整，未继续执行后续工具。';
    }
    if (error is ModelHttpException) {
      return switch (error.statusCode) {
        401 || 403 => '模型鉴权失败；请检查 API Key 后重试。',
        429 => '模型服务限流或账户额度不足；请稍后重试或检查账户额度。',
        >= 500 => '模型服务暂时不可用；本轮未完成，请稍后重试。',
        _ => '模型请求失败（HTTP ${error.statusCode}）；请检查模型配置后重试。',
      };
    }
    if (error is StateError) return error.message;
    return '生成失败：$error';
  }

  ChatMessage _withBackgroundWarning(ChatMessage assistant) {
    final warning = _backgroundWarning;
    if (warning == null || warning.trim().isEmpty) return assistant;
    final existingError = assistant.error?.trim();
    return assistant.copyWith(
      content: assistant.content.trim().isEmpty
          ? assistant.content
          : '> $warning\n\n${assistant.content}',
      error: existingError == null || existingError.isEmpty
          ? warning
          : '$existingError\n$warning',
    );
  }

  String _emptyReplySummary(
    List<AutoRecordAction> autoActions,
    List<TableChatAction> tableActions,
  ) {
    final count = autoActions.length + tableActions.length;
    if (count == 0) return '';
    return '本轮已完成 $count 个本地操作，结果以操作回执为准。';
  }

  Future<void> _cancelQueuedTurnsFor(String conversationId) async {
    final canceled = <_ChatTurnRequest>[
      for (final turn in _steeringQueue)
        if (turn.conversation.id == conversationId) turn,
      for (final turn in _conversationQueue)
        if (turn.conversation.id == conversationId) turn,
    ];
    if (canceled.isEmpty) return;
    _steeringQueue.removeWhere(
      (turn) => turn.conversation.id == conversationId,
    );
    _conversationQueue.removeWhere(
      (turn) => turn.conversation.id == conversationId,
    );
    await _persistTaskCheckpoint();
    notifyListeners();
    for (final turn in canceled) {
      await _persistQueuedTurnCancellation(turn, reason: '已取消：这条补充指令没有发送到模型。');
    }
  }

  Future<void> _persistQueuedTurnCancellation(
    _ChatTurnRequest turn, {
    required String reason,
    bool completeTurn = true,
  }) async {
    if (turn.completion.isCompleted) return;
    final now = DateTime.now();
    final assistant = ChatMessage(
      id: turn.assistantMessageId ?? _repository.newMessageId(),
      conversationId: turn.conversation.id,
      role: ChatRole.assistant,
      content: '',
      status: ChatMessageStatus.interrupted,
      createdAt: now,
      updatedAt: now,
      error: reason,
    );
    await _saveMessage(assistant);
    _replaceMessage(assistant);
    await _saveGeneration(
      GenerationRun(
        assistantMessageId: assistant.id,
        conversationId: turn.conversation.id,
        userMessageId: turn.userMessageId,
        status: GenerationStatus.interrupted,
        responseText: '',
        toolCalls: const [],
        createdAt: now,
        updatedAt: now,
        error: reason,
      ),
    );
    if (completeTurn) turn.completion.complete();
    notifyListeners();
  }

  Future<void> _handleBackgroundCommand(AgentBackgroundCommand command) async {
    final active = _activeTurn;
    if (active == null || active.assistantMessageId != command.taskId) return;
    switch (command.type) {
      case AgentBackgroundCommandType.pause:
        await pauseGeneration(reason: command.reason ?? '用户从通知暂停了任务。');
      case AgentBackgroundCommandType.cancel:
        await cancelGeneration(reason: command.reason ?? '用户从通知取消了任务。');
    }
  }

  Future<void> _startBackgroundTask(
    ChatMessage assistant,
    Conversation conversation,
  ) async {
    _backgroundTaskId = assistant.id;
    _backgroundWarning = null;
    _backgroundTaskStarted = false;
    if (_backgroundAgent is DisabledAgentBackgroundControl) return;
    try {
      final permission = await _backgroundAgent.requestNotificationPermission();
      if (permission.state ==
          AgentBackgroundState.notificationPermissionDenied) {
        _backgroundWarning = _backgroundWarningFor(permission);
      } else {
        final snapshot = await _backgroundAgent.startTask(
          taskId: assistant.id,
          title: conversation.title,
          text: '模型请求准备中',
          progress: _backgroundProgress,
        );
        _backgroundTaskStarted = snapshot.state == AgentBackgroundState.running;
        _backgroundWarning = _backgroundWarningFor(snapshot);
        if (!_cancelChatRequested &&
            snapshot.state == AgentBackgroundState.serviceRestricted &&
            snapshot.taskId == assistant.id) {
          final reason = snapshot.message ?? '系统限制前台服务启动，任务已暂停。';
          _taskStopReason = _TaskStopReason.pause;
          _taskInterruptionReason = '$reason 已保存当前进度，没有继续派发新的工具或写入。';
          _cancelChatRequested = true;
        }
        if (_backgroundWarning == null) {
          await _backgroundAgent.updateTask(
            taskId: assistant.id,
            title: conversation.title,
            text: '模型正在生成回复',
            progress: _backgroundProgress,
          );
        }
      }
    } on Object catch (error) {
      _backgroundWarning = '后台任务启动失败：$error。当前明确标记为仅前台运行。';
    }
    if (_backgroundWarning != null) {
      final generation = await _repository.findGeneration(assistant.id);
      await _saveMessage(
        assistant.copyWith(
          error: _backgroundWarning,
          updatedAt: DateTime.now(),
        ),
      );
      if (generation != null) {
        await _saveGeneration(
          generation.copyWith(
            error: _backgroundWarning,
            updatedAt: DateTime.now(),
          ),
        );
      }
    }
  }

  String? _backgroundWarningFor(AgentBackgroundSnapshot snapshot) {
    return switch (snapshot.state) {
      AgentBackgroundState.running => null,
      AgentBackgroundState.unsupported
          when defaultTargetPlatform != TargetPlatform.android =>
        null,
      AgentBackgroundState.notificationPermissionDenied => '通知权限被拒绝，任务仅在前台运行。',
      AgentBackgroundState.serviceRestricted => '系统限制前台服务，任务仅在前台运行。',
      AgentBackgroundState.activityUnavailable => '当前无法启动前台服务，任务仅在前台运行。',
      AgentBackgroundState.busy => '后台写入运行时忙碌，任务仅在前台运行。',
      AgentBackgroundState.failed => snapshot.message ?? '后台任务启动失败，任务仅在前台运行。',
      AgentBackgroundState.unsupported =>
        snapshot.message ?? '当前平台不支持后台 Agent，任务仅在前台运行。',
      _ => snapshot.message ?? '后台服务未进入运行状态，任务仅在前台运行。',
    };
  }

  Future<void> _updateBackgroundTask(
    String taskId,
    Conversation conversation, {
    required String text,
    double? progress,
  }) async {
    if (_backgroundAgent is DisabledAgentBackgroundControl) return;
    if (!_backgroundTaskStarted) return;
    if (_backgroundTaskId != taskId) return;
    try {
      final snapshot = await _backgroundAgent.updateTask(
        taskId: taskId,
        title: conversation.title,
        text: text,
        progress: progress,
      );
      _backgroundWarning ??= _backgroundWarningFor(snapshot);
    } on Object catch (error) {
      _backgroundWarning ??= '后台进度更新失败：$error。任务仅在前台运行。';
    }
  }

  Future<void> _finalizeBackgroundTask(ChatMessage assistant) async {
    if (_backgroundAgent is DisabledAgentBackgroundControl) return;
    if (!_backgroundTaskStarted) return;
    final taskId = _backgroundTaskId ?? assistant.id;
    try {
      if (assistant.status == ChatMessageStatus.complete) {
        await _backgroundAgent.completeTask(
          taskId: taskId,
          message: '消息回复已完成。',
        );
      } else if (assistant.status == ChatMessageStatus.interrupted &&
          _taskStopReason != _TaskStopReason.cancel) {
        await _backgroundAgent.pauseTask(
          taskId: taskId,
          reason: _taskInterruptionReason ?? assistant.error ?? '任务已暂停。',
        );
      } else if (assistant.status == ChatMessageStatus.interrupted ||
          _taskStopReason == _TaskStopReason.cancel) {
        await _backgroundAgent.cancelTask(
          taskId: taskId,
          reason: _taskInterruptionReason ?? assistant.error ?? '任务已取消。',
        );
      } else {
        await _backgroundAgent.pauseTask(
          taskId: taskId,
          reason: assistant.error ?? '任务失败，需要核对后继续。',
        );
      }
    } on Object catch (error) {
      _backgroundWarning ??= '后台任务结算失败：$error。';
    }
  }

  double? get _backgroundProgress => null;

  void _syncAgentUsage(AgentUsageMeter meter) {
    _agentUsage = meter.snapshot();
  }

  Future<void> pauseGeneration({String reason = '用户暂停了任务。'}) async {
    final turn = _activeTurn;
    if (!_isChatGenerating || turn == null) return;
    final finished = _chatGenerationFinished;
    _taskStopReason = _TaskStopReason.pause;
    _taskSchedulerPaused = true;
    await _persistTaskCheckpoint();
    final interruption = Completer<void>();
    // Listen for settlement before interrupting: the worker can fail its final
    // checkpoint before the generation-finished signal resumes this method.
    // The generation completer fires before the worker writes that checkpoint.
    final completed = Future.wait<void>([
      interruption.future,
      turn.completion.future,
    ]);
    try {
      await _interruptActiveGeneration(reason: reason, finished: finished);
      interruption.complete();
    } on Object catch (error, stackTrace) {
      interruption.completeError(error, stackTrace);
    }
    await completed;
  }

  Future<void> cancelGeneration({
    String? conversationId,
    bool includeSteering = true,
    String reason = '用户取消了任务。',
  }) async {
    final targetConversationId = conversationId ?? _runningConversationId;
    if (targetConversationId == null) return;
    final isActive = _runningConversationId == targetConversationId;
    final activeFinished = isActive ? _chatGenerationFinished : null;
    if (includeSteering) {
      await _cancelQueuedTurnsFor(targetConversationId);
    }
    if (!isActive) return;
    if (!_isChatGenerating && _activeTurn != null) {
      _activeTurn!.cancelledBeforeDispatch = true;
    }
    _taskStopReason = _TaskStopReason.cancel;
    await _interruptActiveGeneration(reason: reason, finished: activeFinished);
  }

  Future<void> _interruptActiveGeneration({
    required String reason,
    required Completer<void>? finished,
  }) async {
    _cancelChatRequested = true;
    _taskInterruptionReason = reason.contains('没有继续派发')
        ? reason
        : '$reason 已保存当前进度，没有继续派发新的工具或写入。';
    final cancellation = _generationCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    final subscription = _chatSubscription;
    if (_chatStreamDone?.isCompleted == false) {
      _chatStreamDone!.complete();
    }
    if (subscription != null) {
      await subscription.cancel();
    }
    _flushUiNotifications();
    notifyListeners();
    await finished?.future;
  }

  Future<String> testModelConnection() => _chatService.testConnection();

  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

  Future<void> _shutdown() async {
    _shuttingDown = true;
    final errors = <Object>[];
    try {
      await pauseGeneration(reason: '应用正在关闭，任务检查点已保留。');
    } catch (error) {
      errors.add(error);
    }
    try {
      await _persistTaskCheckpoint();
    } catch (error) {
      errors.add(error);
    }
    final pendingSaves = _messageSaveQueues.values.toList(growable: false);
    if (pendingSaves.isNotEmpty) {
      for (final save in pendingSaves) {
        try {
          await save;
        } catch (error) {
          errors.add(error);
        }
      }
    }
    final pendingGenerations = _generationSaveQueues.values.toList(
      growable: false,
    );
    if (pendingGenerations.isNotEmpty) {
      for (final save in pendingGenerations) {
        try {
          await save;
        } catch (error) {
          errors.add(error);
        }
      }
    }
    if (!_chatServiceClosed) {
      _chatServiceClosed = true;
      try {
        _chatService.close();
      } catch (error) {
        errors.add(error);
      }
    }
    if (errors.isNotEmpty) {
      _shutdownError = errors.map((error) => error.toString()).join('\n');
      debugPrint(
        'ConversationWorkspace shutdown completed with errors:\n'
        '$_shutdownError',
      );
    }
  }

  Future<void> retryAssistantMessage(String messageId) async {
    final message = await _repository.findMessage(messageId);
    if (message == null ||
        message.role != ChatRole.assistant ||
        (message.status != ChatMessageStatus.failed &&
            message.status != ChatMessageStatus.interrupted)) {
      return;
    }
    final messages = await _repository.listMessages(message.conversationId);
    ChatMessage? previousUser;
    for (final candidate in messages) {
      if (candidate.createdAt.isAfter(message.createdAt)) {
        break;
      }
      if (candidate.role == ChatRole.user) {
        previousUser = candidate;
      }
    }
    if (previousUser == null) {
      return;
    }
    final conversation = await _repository.findConversation(
      message.conversationId,
    );
    if (conversation == null) {
      return;
    }
    if (_shuttingDown) return;
    final isSteering = _runningConversationId == message.conversationId;
    final turn = _ChatTurnRequest(
      taskId: _newTaskId(),
      sequence: _taskSequence++,
      conversation: conversation,
      userMessageId: previousUser.id,
      thinkingEnabled: false,
      kind: isSteering
          ? AgentTurnQueueKind.steering
          : AgentTurnQueueKind.conversation,
      excludedMessageIds: {message.id},
    );
    if (isSteering) {
      _steeringQueue.addLast(turn);
    } else {
      _conversationQueue.add(turn);
    }
    await _persistTaskCheckpoint();
    _scheduleTurnWorker();
    notifyListeners();
    await turn.completion.future;
  }

  Future<Uint8List?> readAttachment(ChatAttachment attachment) {
    return _repository.readAttachment(attachment);
  }

  Future<void> undoAutoRecord(String actionId) async {
    final action = await _repository.findAutoRecordAction(actionId);
    if (action == null ||
        action.status != AutoRecordStatus.created ||
        action.resultId == null) {
      return;
    }
    var reversibleAction = await _results.reversibleActionForKey(actionId);
    if (reversibleAction == null) {
      await _updateAutoRecordAction(
        actionId,
        action.copyWith(status: AutoRecordStatus.undoFailed, reason: '撤销记录不存在'),
      );
      return;
    }
    if (reversibleAction.status == ReversibleActionStatus.undone) {
      await _updateAutoRecordAction(
        actionId,
        action.copyWith(status: AutoRecordStatus.undone, reason: null),
      );
      return;
    }
    if (reversibleAction.status == ReversibleActionStatus.expired ||
        !reversibleAction.undoUntil.isAfter(DateTime.now())) {
      await _updateAutoRecordAction(
        actionId,
        action.copyWith(status: AutoRecordStatus.expired, reason: '撤销时限已过'),
      );
      return;
    }
    if (reversibleAction.status != ReversibleActionStatus.applied) {
      await _updateAutoRecordAction(
        actionId,
        action.copyWith(
          status: AutoRecordStatus.undoFailed,
          reason: reversibleAction.error ?? '当前成果状态不允许撤销',
        ),
      );
      return;
    }
    try {
      await _results.undoAction(actionId);
      await _updateAutoRecordAction(
        actionId,
        action.copyWith(status: AutoRecordStatus.undone, reason: null),
      );
    } on StateError catch (error) {
      reversibleAction = await _results.reversibleActionForKey(actionId);
      final status = switch (reversibleAction?.status) {
        ReversibleActionStatus.undone => AutoRecordStatus.undone,
        ReversibleActionStatus.expired => AutoRecordStatus.expired,
        _ => AutoRecordStatus.undoFailed,
      };
      await _updateAutoRecordAction(
        actionId,
        action.copyWith(status: status, reason: error.message.toString()),
      );
    }
  }

  Future<void> confirmTableStructureAction(String actionId) async {
    final found = await _repository.findTableChatAction(actionId);
    if (found == null) return;
    final (message, action) = found;
    if (action.status != TableChatActionStatus.pendingConfirmation) return;
    final conversation = await _repository.findConversation(
      message.conversationId,
    );
    final operation = action.proposal['operation'];
    final permission = switch (operation) {
      'create' => AiPermissionAction.tableCreate,
      'rename' => AiPermissionAction.tableUpdate,
      'delete' => AiPermissionAction.tableDelete,
      'upsert_field' || 'delete_field' => AiPermissionAction.fieldAdjust,
      'assign_inbox_target' => AiPermissionAction.inboxTargetAdjust,
      _ => null,
    };
    final decision = permission == null || conversation == null
        ? AiPolicyDecision.deny
        : conversation.effectiveAiPolicy.decisionFor(
            permission,
            tableIds: [
              ?(action.tableId),
              if (operation == 'assign_inbox_target')
                ?(action.proposal['payload']
                        as Map?)?['expected_current_table_id']
                    ?.toString(),
            ],
          );
    if (decision == AiPolicyDecision.deny) {
      await _updateTableChatAction(
        message,
        action.copyWith(
          status: TableChatActionStatus.failed,
          message: '当前会话写入权限已关闭，未修改表结构。',
        ),
      );
      return;
    }
    final processor = _tableActionProcessor;
    if (processor == null) return;
    final updated = await processor.confirmStructure(action);
    await _updateTableChatAction(message, updated);
    await _replacePersistedToolReceipt(message.id, updated);
    if (updated.operation == 'table.assign_inbox_target' &&
        updated.status == TableChatActionStatus.applied) {
      await processor.acknowledgeInboxAssignmentOperation(updated);
    }
    await _resumeWaitingTurnForAssistant(message.id);
  }

  Future<void> retryIncompleteIntakeAction(String actionId) async {
    final processor = _tableActionProcessor;
    if (processor == null) return;
    var found = await _repository.findTableChatAction(actionId);
    if (found == null) return;
    var (message, action) = found;
    if (!action.retryableIntake && !action.intakeRetryPending) return;
    final nextAttempt = action.intakeRetryPending
        ? action.intakeRetryAttempt
        : action.intakeRetryAttempt + 1;
    final operationId =
        action.intakeRetryPending && action.intakeRetryOperationId != null
        ? action.intakeRetryOperationId!
        : 'intake-retry:${action.id}:$nextAttempt';
    final pending = action.copyWith(
      status: TableChatActionStatus.pendingRetry,
      intakeRetryAttempt: nextAttempt,
      intakeRetryOperationId: operationId,
      intakeRetryPending: true,
      message: '已保存重新扫描意图，正在复核权限和任务状态。',
    );
    await _updateTableChatAction(message, pending);
    final turn = [
      ..._steeringQueue,
      ..._conversationQueue,
    ].where((turn) => turn.assistantMessageId == message.id).firstOrNull;
    if (turn == null) {
      await _updateTableChatAction(
        message,
        pending.copyWith(message: '原接收任务已不在等待队列；已保留原始意图和扫描编号，请从任务卡继续。'),
      );
      return;
    }
    if (_reviewTaskIds.contains(turn.taskId) ||
        (turn.status != AgentTurnCheckpointStatus.waitingInput &&
            turn.status != AgentTurnCheckpointStatus.paused)) {
      await _updateTableChatAction(
        message,
        pending.copyWith(message: '接收任务需要先核对中断状态；原始意图和扫描编号已保留。'),
      );
      return;
    }
    if (_activeTurn != null || _handlingIntakeRetry) {
      await _updateTableChatAction(
        message,
        pending.copyWith(message: '其他任务正在执行；原始意图和扫描编号已保留，稍后可继续。'),
      );
      return;
    }
    final worker = _turnWorker;
    if (worker != null) await worker;
    found = await _repository.findTableChatAction(actionId);
    if (found == null) return;
    (message, action) = found;
    if (!action.retryableIntake && !action.intakeRetryPending) return;

    final previousRunId = _activeRunId;
    final previousUsage = _agentUsage;
    if (previousRunId != null) _runUsage[previousRunId] = previousUsage;
    final retryRunId = turn.effectiveRunId;
    final retryRunUsage =
        _runUsage[retryRunId] ??
        (previousRunId == retryRunId ? previousUsage : const AgentUsage());
    _activeRunId = retryRunId;
    _agentUsage = retryRunUsage;
    _activeTurn = turn;
    _runningConversationId = turn.conversationId;
    _handlingIntakeRetry = true;
    final activeUsage = AgentUsageMeter(
      initial: _agentUsage,
      activeElapsedDuration: _activeUsageElapsedDuration,
    )..beginActivity();
    _activeUsageMeter = activeUsage;
    var checkpointInFlight = false;
    _activeUsageCheckpointTimer?.cancel();
    _activeUsageCheckpointTimer = Timer.periodic(_streamPersistenceInterval, (
      _,
    ) {
      if (checkpointInFlight || _cancelChatRequested) return;
      checkpointInFlight = true;
      _syncAgentUsage(activeUsage);
      unawaited(
        _persistTaskCheckpoint()
            .catchError((Object error) {
              _backgroundWarning ??= '接收重扫用量检查点保存失败：$error';
            })
            .whenComplete(() => checkpointInFlight = false),
      );
    });
    notifyListeners();
    try {
      final conversation = await _repository.findConversation(
        message.conversationId,
      );
      final decision = conversation?.effectiveAiPolicy.decisionFor(
        AiPermissionAction.contentCreate,
        tableIds: [?(action.tableId)],
      );
      if (decision != AiPolicyDecision.allow) {
        final stillPending = pending.copyWith(
          message: '当前会话权限尚未允许重新扫描；扫描编号仍待执行，未创建或补写内容。',
        );
        await _updateTableChatAction(message, stillPending);
        return;
      }
      final result = await processor.retryIncompleteIntake(
        pending,
        operationId: operationId,
      );
      final updated = result.copyWith(
        requestFingerprint: action.requestFingerprint,
        intakeRetryAttempt: nextAttempt,
        intakeRetryOperationId: operationId,
        intakeRetryPending: result.intakeRetryPending,
      );
      await _updateTableChatAction(message, updated);
      await _replacePersistedToolReceipt(message.id, updated);
      if (!updated.retryableIntake) {
        await _resumeWaitingTurnForAssistant(message.id);
      }
    } on Object catch (error) {
      final retryable = pending.copyWith(
        message: '重新扫描未完成；扫描编号仍待执行且未记为终态：$error',
      );
      await _updateTableChatAction(message, retryable);
    } finally {
      activeUsage.pauseActivity();
      _syncAgentUsage(activeUsage);
      _activeUsageCheckpointTimer?.cancel();
      _activeUsageCheckpointTimer = null;
      if (identical(_activeUsageMeter, activeUsage)) _activeUsageMeter = null;
      _activeTurn = null;
      _runningConversationId = null;
      _handlingIntakeRetry = false;
      _runUsage[retryRunId] = _agentUsage;
      _activeRunId = previousRunId;
      _agentUsage = previousRunId == retryRunId
          ? _runUsage[retryRunId]!
          : previousRunId == null
          ? previousUsage
          : _runUsage[previousRunId] ?? previousUsage;
      await _persistTaskCheckpoint();
      _scheduleTurnWorker();
      notifyListeners();
    }
  }

  Future<void> _replacePersistedToolReceipt(
    String assistantMessageId,
    TableChatAction action,
  ) async {
    final generation = await _repository.findGeneration(assistantMessageId);
    final message = await _repository.findMessage(assistantMessageId);
    if (generation == null || message == null) return;
    for (final stored in generation.toolCalls) {
      final rawAction = stored['completed_action_json'];
      if (rawAction == null) continue;
      Map<String, dynamic> decoded;
      try {
        decoded = Map<String, dynamic>.from(jsonDecode(rawAction) as Map);
      } on Object {
        continue;
      }
      if (decoded['id'] != action.id) continue;
      final call = ToolCallAccumulator()
        ..index = int.tryParse(stored['index'] ?? '')
        ..id = stored['id']
        ..name = stored['name']
        ..arguments.write(stored['arguments'] ?? '');
      await _saveGeneration(
        _withCompletedToolResult(
          generation,
          call,
          _ToolActionResult.fromTable(action),
        ),
      );
      final callId = stored['id'];
      if (callId == null) return;
      final transcript = [
        for (final item in message.toolTranscript)
          item['role'] == 'tool' && item['tool_call_id'] == callId
              ? {
                  ...item,
                  'content': _ToolActionResult.fromTable(action)
                      .receipt
                      .toolContent,
                }
              : item,
      ];
      final updatedMessage = message.copyWith(
        toolTranscript: transcript,
        updatedAt: DateTime.now(),
      );
      await _saveMessage(updatedMessage);
      _replaceMessage(updatedMessage);
      return;
    }
  }

  Future<void> rejectTableStructureAction(String actionId) async {
    final found = await _repository.findTableChatAction(actionId);
    if (found == null) return;
    final (message, action) = found;
    if (action.status != TableChatActionStatus.pendingConfirmation) return;
    final updated =
        _tableActionProcessor?.rejectStructure(action) ??
        action.copyWith(
          status: TableChatActionStatus.rejected,
          message: '已拒绝，未修改表结构。',
        );
    await _updateTableChatAction(message, updated);
    await _replacePersistedToolReceipt(message.id, updated);
    await _resumeWaitingTurnForAssistant(message.id);
  }

  Future<void> _resumeWaitingTurnForAssistant(String assistantMessageId) async {
    final turn = [..._steeringQueue, ..._conversationQueue]
        .where((turn) => turn.assistantMessageId == assistantMessageId)
        .firstOrNull;
    if (turn == null || turn.status != AgentTurnCheckpointStatus.waitingInput) {
      return;
    }
    final assistant = await _repository.findMessage(assistantMessageId);
    if (assistant != null && _assistantNeedsUserInput(assistant)) return;
    turn.status = AgentTurnCheckpointStatus.queued;
    await _persistTaskCheckpoint();
    _refreshTaskSchedulerPaused();
    _scheduleTurnWorker();
    notifyListeners();
  }

  Future<void> undoTableAction(String actionId) async {
    final found = await _repository.findTableChatAction(actionId);
    if (found == null) return;
    final (message, action) = found;
    final processor = _tableActionProcessor;
    if (processor == null || !action.canUndo) return;
    try {
      await processor.undoDelete(action);
      await _updateTableChatAction(
        message,
        action.copyWith(status: TableChatActionStatus.undone, message: '已恢复。'),
      );
    } on Object catch (error) {
      await _updateTableChatAction(
        message,
        action.copyWith(
          status: TableChatActionStatus.failed,
          message: error is StateError ? error.message : error.toString(),
        ),
      );
    }
  }

  Future<void> _updateTableChatAction(
    ChatMessage message,
    TableChatAction action,
  ) async {
    final updated = message.copyWith(
      tableActions: message.tableActions
          .map((item) => item.id == action.id ? action : item)
          .toList(growable: false),
      updatedAt: DateTime.now(),
    );
    await _saveMessage(updated);
    _replaceMessage(updated);
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _streamUiFlushTimer?.cancel();
    _streamPersistenceTimer?.cancel();
    unawaited(_backgroundCommands?.cancel());
    final cancellation = _generationCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    unawaited(shutdown());
    super.dispose();
  }

  void _replaceMessage(ChatMessage message) {
    final values = List<ChatMessage>.from(
      _messagesByConversation[message.conversationId] ?? const [],
    );
    final index = values.indexWhere((item) => item.id == message.id);
    if (index < 0) {
      values.add(message);
    } else {
      values[index] = message;
    }
    values.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _messagesByConversation[message.conversationId] = values;
  }

  void _replaceConversation(Conversation conversation) {
    _conversations = [
      conversation,
      ..._conversations.where((item) => item.id != conversation.id),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> _updateAutoRecordAction(
    String actionId,
    AutoRecordAction updated,
  ) async {
    final message = await _findMessageByAction(actionId);
    if (message == null) {
      return;
    }
    final updatedMessage = message.copyWith(
      actions: message.actions
          .map((action) => action.id == actionId ? updated : action)
          .toList(growable: false),
      updatedAt: DateTime.now(),
    );
    await _repository.saveMessage(updatedMessage);
    _replaceMessage(updatedMessage);
    notifyListeners();
  }

  Future<ChatMessage?> _findMessageByAction(String actionId) async {
    for (final messages in _messagesByConversation.values) {
      for (final message in messages) {
        if (message.actions.any((action) => action.id == actionId)) {
          return message;
        }
      }
    }
    for (final conversation in await _repository.listConversations()) {
      for (final message in await _repository.listMessages(conversation.id)) {
        if (message.actions.any((action) => action.id == actionId)) {
          return message;
        }
      }
    }
    return null;
  }

  String _conversationTitle(
    String text,
    List<ChatAttachmentInput> attachments,
  ) {
    final firstLine = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isNotEmpty) {
      final runes = firstLine.runes.take(28).toList(growable: false);
      return String.fromCharCodes(runes);
    }
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '图片记录 · $month-$day $hour:$minute';
  }

  String _messagePreview(String content, bool hasImage) {
    final normalized = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isNotEmpty) {
      return normalized.length <= 80
          ? normalized
          : '${normalized.substring(0, 80)}...';
    }
    return hasImage ? '[图片]' : '';
  }
}

class _ChatTurnRequest {
  _ChatTurnRequest({
    required this.taskId,
    required this.sequence,
    required this.conversation,
    required this.userMessageId,
    required this.thinkingEnabled,
    required this.kind,
    this.status = AgentTurnCheckpointStatus.queued,
    this.assistantMessageId,
    this.excludedMessageIds = const {},
    this.runId,
  });

  final String taskId;
  String? runId;
  String get effectiveRunId => runId ?? taskId;
  final int sequence;
  final Conversation conversation;
  final String userMessageId;
  final bool thinkingEnabled;
  AgentTurnQueueKind kind;
  final Set<String> excludedMessageIds;
  AgentTurnCheckpointStatus status;
  bool cancelledBeforeDispatch = false;
  bool settled = false;
  String? assistantMessageId;
  final Completer<void> completion = Completer<void>();

  String get conversationId => conversation.id;
}

class AgentTaskSummary {
  const AgentTaskSummary({
    required this.runId,
    required this.conversationId,
    required this.taskIds,
    required this.needsReview,
    required this.awaitingInput,
    required this.usage,
  });

  final String runId;
  final String conversationId;
  final List<String> taskIds;
  final bool needsReview;
  final bool awaitingInput;
  final AgentUsage usage;
}

enum _TaskStopReason { pause, cancel }

class AgentTaskReviewRequiredException implements Exception {
  const AgentTaskReviewRequiredException(this.taskIds);

  final Set<String> taskIds;

  @override
  String toString() => '以下任务需要先核对副作用再继续：${taskIds.join('、')}';
}

class _ToolExecutionBatch {
  const _ToolExecutionBatch({
    required this.generation,
    required this.autoActions,
    required this.tableActions,
  });

  final GenerationRun generation;
  final List<AutoRecordAction> autoActions;
  final List<TableChatAction> tableActions;
}

class _ToolActionResult {
  const _ToolActionResult({
    required this.receipt,
    this.autoAction,
    this.tableAction,
    this.generation,
  });

  factory _ToolActionResult.fromTable(
    TableChatAction action, {
    String? code,
    String message = '表操作已取得本地回执。',
  }) {
    if (action.retryableIntake) {
      return _ToolActionResult(
        receipt: ChatWriteToolReceipt.conflict(
          operationId: action.intakeRetryOperationId ?? action.id,
          message: action.message ?? '接收覆盖不足，原意图等待重新扫描。',
          data: action.toJson(),
        ),
        tableAction: action,
      );
    }
    final receipt = switch (action.status) {
      TableChatActionStatus.applied ||
      TableChatActionStatus.undone => ChatWriteToolReceipt.succeeded(
        operationId: action.id,
        message: action.message ?? message,
        data: action.toJson(),
      ),
      TableChatActionStatus.pendingConfirmation =>
        ChatWriteToolReceipt.waitingConfirmation(
          operationId: action.id,
          message: action.message ?? '操作等待当前对话确认。',
          data: action.toJson(),
        ),
      TableChatActionStatus.pendingRetry => ChatWriteToolReceipt.conflict(
        operationId: action.intakeRetryOperationId ?? action.id,
        message: action.message ?? '接收意图等待重新扫描。',
        data: action.toJson(),
      ),
      TableChatActionStatus.stale => ChatWriteToolReceipt.conflict(
        operationId: action.id,
        message: action.message ?? '目标版本已变化，需要重新读取。',
        data: action.toJson(),
      ),
      TableChatActionStatus.rejected => ChatWriteToolReceipt.rejected(
        code: code ?? 'rejected',
        message: action.message ?? '操作已被拒绝。',
        data: action.toJson(),
      ),
      TableChatActionStatus.failed ||
      TableChatActionStatus.expired => ChatWriteToolReceipt.failed(
        code: code ?? action.status.name,
        message: action.message ?? '表操作失败。',
        data: action.toJson(),
      ),
    };
    return _ToolActionResult(receipt: receipt, tableAction: action);
  }

  factory _ToolActionResult.fromAuto(
    AutoRecordAction action, {
    String? code,
    String message = '成果操作已取得本地回执。',
  }) {
    final receipt = switch (action.status) {
      AutoRecordStatus.created => ChatWriteToolReceipt.succeeded(
        operationId: action.id,
        message: message,
        data: action.toJson(),
      ),
      AutoRecordStatus.review => ChatWriteToolReceipt.waitingConfirmation(
        operationId: action.id,
        message: action.reason ?? '内容已进入待整理。',
        data: action.toJson(),
      ),
      AutoRecordStatus.skipped => ChatWriteToolReceipt.succeeded(
        operationId: action.id,
        message: action.reason ?? '操作未产生新记录，已复用现有结果。',
        data: action.toJson(),
      ),
      AutoRecordStatus.undone ||
      AutoRecordStatus.expired ||
      AutoRecordStatus.undoFailed => ChatWriteToolReceipt.failed(
        code: code ?? action.status.wireName,
        message: action.reason ?? '操作当前不可用。',
        data: action.toJson(),
      ),
    };
    return _ToolActionResult(receipt: receipt, autoAction: action);
  }

  factory _ToolActionResult.failed({
    required String code,
    required String message,
    GenerationRun? generation,
  }) => _ToolActionResult(
    receipt: ChatWriteToolReceipt.failed(code: code, message: message),
    generation: generation,
  );

  factory _ToolActionResult.fromReceipt(ChatWriteToolReceipt receipt) =>
      _ToolActionResult(receipt: receipt);

  final ChatWriteToolReceipt receipt;
  final AutoRecordAction? autoAction;
  final TableChatAction? tableAction;
  final GenerationRun? generation;

  _ToolActionResult copyWith({GenerationRun? generation}) => _ToolActionResult(
    receipt: receipt,
    autoAction: autoAction,
    tableAction: tableAction,
    generation: generation ?? this.generation,
  );
}
