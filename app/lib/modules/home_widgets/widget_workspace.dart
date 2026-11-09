import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../tables/table_library.dart';
import 'home_widget_contract.dart';
import 'home_widget_projection.dart';
import 'widget_store.dart';

class WidgetWorkspace extends ChangeNotifier {
  WidgetWorkspace({
    required TableLibrary tables,
    required WidgetStore store,
    required Future<WidgetPublishResult> Function(String) publish,
    required Future<void> Function() clear,
    required bool Function() blocked,
  }) : _tables = tables,
       _store = store,
       _publish = publish,
       _clear = clear,
       _blocked = blocked;

  static const Duration refreshDelay = Duration(milliseconds: 300);
  static const Duration undoWindow = Duration(minutes: 10);

  final TableLibrary _tables;
  final WidgetStore _store;
  final Future<WidgetPublishResult> Function(String) _publish;
  final Future<void> Function() _clear;
  final bool Function() _blocked;

  Timer? _refreshDebounce;
  Future<void> _mutationTail = Future<void>.value();
  Future<void> _refreshTail = Future<void>.value();
  bool _initialized = false;
  bool _disposed = false;

  Future<void> initialize() async {
    _ensureNotDisposed();
    if (_initialized) return;
    _initialized = true;
    _tables.addListener(_scheduleRefresh);
    await refreshWidgets();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _refreshDebounce?.cancel();
    _refreshDebounce = null;
    if (_initialized) {
      _tables.removeListener(_scheduleRefresh);
    }
    _initialized = false;
    super.dispose();
  }

  Future<List<CardSummary>> listCards({bool includeArchived = false}) async {
    _ensureInitialized();
    final state = await _store.readState();
    return [
      for (final card in state.cards.values)
        if (includeArchived || !card.archived)
          CardSummary(
            cardId: card.cardId,
            revision: card.revision,
            archived: card.archived,
            visibility: card.visibility,
            spec: card.spec,
          ),
    ];
  }

  Future<CardDefinition?> getCard(String cardId) async {
    _ensureInitialized();
    return (await _store.readState()).cards[cardId];
  }

  Future<CardPreview> previewCard(CardSpec spec, {String? cardId}) async {
    _ensureInitialized();
    if (_blocked()) {
      throw const WidgetContractException(
        WidgetCommandError.forbidden,
        '迁移门阻断期间不能预览桌面小组件。',
      );
    }
    final source = await _tables.contentSnapshot();
    final existing = cardId == null
        ? null
        : (await _store.readState()).cards[cardId];
    final card = CardDefinition(
      cardId: cardId ?? 'preview',
      revision: existing?.revision ?? 1,
      archived: false,
      visibility: existing?.visibility ?? WidgetVisibility.fields,
      spec: spec,
    );
    final projection = projectCardDetails(
      card,
      source: source,
      localNow: DateTime.now(),
    );
    return CardPreview(
      snapshot: projection.snapshot,
      matchingCount: projection.matchingCount,
      warnings: projection.warnings,
    );
  }

  Future<CardWriteReceipt> applyCardCommand(
    CardCommand command, {
    required String operationId,
    required Future<bool> Function() authorize,
  }) => _serializedMutation(
    () => _applyCardCommand(
      command,
      operationId: operationId,
      authorize: authorize,
    ),
  );

  Future<WidgetPublishResult> refreshWidgets() {
    _ensureNotDisposed();
    final completer = Completer<WidgetPublishResult>();
    _refreshTail = _refreshTail.then((_) async {
      try {
        completer.complete(await _refreshOnce());
      } on Object catch (error) {
        completer.complete(WidgetPublishResult.failed(error.toString()));
      }
    });
    return completer.future;
  }

  Future<WidgetPublishResult> _refreshOnce() async {
    if (_blocked()) {
      try {
        await _clear();
        return const WidgetPublishResult.cleared();
      } on Object catch (error) {
        return WidgetPublishResult.failed(error.toString());
      }
    }

    final state = await _store.readState();
    final snapshots = <WidgetSnapshot>[];
    if (state.cards.isNotEmpty) {
      final source = await _tables.contentSnapshot();
      if (_blocked()) {
        try {
          await _clear();
          return const WidgetPublishResult.cleared();
        } on Object catch (error) {
          return WidgetPublishResult.failed(error.toString());
        }
      }
      final now = DateTime.now();
      for (final card in state.cards.values) {
        snapshots.add(projectCard(card, source: source, localNow: now));
      }
    }
    final envelope = constrainWidgetSnapshots(snapshots);
    try {
      return await _publish(envelope.toJsonString());
    } on Object catch (error) {
      return WidgetPublishResult.failed(error.toString());
    }
  }

  Future<CardWriteReceipt> _applyCardCommand(
    CardCommand command, {
    required String operationId,
    required Future<bool> Function() authorize,
  }) async {
    _ensureInitialized();
    final invalid = _commandShapeError(command, operationId);
    if (invalid != null) {
      return _failedReceipt(
        operationId,
        command.cardId,
        WidgetCommandError.invalidArgument,
        invalid,
      );
    }
    if (!await _authorized(authorize)) {
      return _failedReceipt(
        operationId,
        command.cardId,
        WidgetCommandError.forbidden,
        '当前权限不允许写入桌面小组件配置。',
      );
    }

    late final WidgetStoreState state;
    try {
      state = await _store.readState();
    } on Object catch (error) {
      return _failedReceipt(
        operationId,
        command.cardId,
        WidgetCommandError.storageError,
        error.toString(),
      );
    }

    final existing = state.operations[operationId];
    if (existing != null) {
      if (existing.signature == command.normalizedSignature) {
        return existing.receipt;
      }
      return _failedReceipt(
        operationId,
        command.cardId,
        WidgetCommandError.operationConflict,
        '相同操作 ID 已用于不同命令。',
        revision: existing.receipt.revision,
      );
    }

    final cards = Map<String, CardDefinition>.of(state.cards);
    final visibility = Map<String, WidgetVisibility>.of(state.visibility);
    final operations = Map<String, WidgetStoreOperation>.of(state.operations);
    final lastMutations = Map<String, String>.of(state.lastMutationByCard);
    final undoByCard = Map<String, WidgetStoreUndo>.of(state.undoByCard);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    late final CardDefinition nextCard;
    late final WidgetStoreUndo nextUndo;
    switch (command.kind) {
      case CardCommandKind.create:
        {
          final validation = _validateSpec(command.spec!, null);
          if (validation != null) {
            return _failedReceipt(
              operationId,
              null,
              WidgetCommandError.invalidArgument,
              validation,
            );
          }
          final cardId = 'card_${const Uuid().v4()}';
          nextCard = CardDefinition(
            cardId: cardId,
            revision: 1,
            archived: false,
            visibility: WidgetVisibility.titles,
            spec: command.spec!,
          );
          nextUndo = WidgetStoreUndo(
            targetOperationId: operationId,
            appliedAtMs: nowMs,
            beforeCard: null,
          );
          cards[cardId] = nextCard;
          visibility[cardId] = nextCard.visibility;
          break;
        }
      case CardCommandKind.replace:
        {
          final current = cards[command.cardId!];
          final revisionError = _revisionError(operationId, command, current);
          if (revisionError != null) return revisionError;
          final validation = _validateSpec(command.spec!, current!.spec);
          if (validation != null) {
            return _failedReceipt(
              operationId,
              current.cardId,
              WidgetCommandError.invalidArgument,
              validation,
              revision: current.revision,
            );
          }
          nextCard = current.copyWith(
            revision: current.revision + 1,
            spec: command.spec,
          );
          cards[current.cardId] = nextCard;
          nextUndo = WidgetStoreUndo(
            targetOperationId: operationId,
            appliedAtMs: nowMs,
            beforeCard: current,
          );
          break;
        }
      case CardCommandKind.archive:
        {
          final current = cards[command.cardId!];
          final revisionError = _revisionError(operationId, command, current);
          if (revisionError != null) return revisionError;
          if (current!.archived) {
            return _failedReceipt(
              operationId,
              current.cardId,
              WidgetCommandError.invalidArgument,
              '桌面小组件已经归档。',
              revision: current.revision,
            );
          }
          nextCard = current.copyWith(
            revision: current.revision + 1,
            archived: true,
          );
          cards[current.cardId] = nextCard;
          nextUndo = WidgetStoreUndo(
            targetOperationId: operationId,
            appliedAtMs: nowMs,
            beforeCard: current,
          );
          break;
        }
      case CardCommandKind.restore:
        {
          final current = cards[command.cardId!];
          final revisionError = _revisionError(operationId, command, current);
          if (revisionError != null) return revisionError;
          if (!current!.archived) {
            return _failedReceipt(
              operationId,
              current.cardId,
              WidgetCommandError.invalidArgument,
              '桌面小组件未归档。',
              revision: current.revision,
            );
          }
          nextCard = current.copyWith(
            revision: current.revision + 1,
            archived: false,
          );
          cards[current.cardId] = nextCard;
          nextUndo = WidgetStoreUndo(
            targetOperationId: operationId,
            appliedAtMs: nowMs,
            beforeCard: current,
          );
          break;
        }
      case CardCommandKind.setVisibility:
        {
          final current = cards[command.cardId!];
          final revisionError = _revisionError(operationId, command, current);
          if (revisionError != null) return revisionError;
          nextCard = current!.copyWith(
            revision: current.revision + 1,
            visibility: command.visibility,
          );
          cards[current.cardId] = nextCard;
          visibility[current.cardId] = command.visibility!;
          nextUndo = WidgetStoreUndo(
            targetOperationId: operationId,
            appliedAtMs: nowMs,
            beforeCard: current,
          );
          break;
        }
      case CardCommandKind.undo:
        {
          final current = cards[command.cardId!];
          final revisionError = _revisionError(operationId, command, current);
          if (revisionError != null) return revisionError;
          if (lastMutations[current!.cardId] != command.targetOperationId) {
            return _failedReceipt(
              operationId,
              current.cardId,
              WidgetCommandError.invalidArgument,
              '只能撤销该小组件最近一次写入。',
              revision: current.revision,
            );
          }
          final target = operations[command.targetOperationId];
          final undo = undoByCard[current.cardId];
          if (target == null ||
              undo == null ||
              undo.targetOperationId != command.targetOperationId) {
            return _failedReceipt(
              operationId,
              current.cardId,
              WidgetCommandError.notFound,
              '找不到可撤销的写入。',
              revision: current.revision,
            );
          }
          final elapsed = nowMs - undo.appliedAtMs;
          if (elapsed < 0 || elapsed > undoWindow.inMilliseconds) {
            return _failedReceipt(
              operationId,
              current.cardId,
              WidgetCommandError.invalidArgument,
              '该写入已超过 10 分钟撤销窗口。',
              revision: current.revision,
            );
          }
          if (target.command.kind == CardCommandKind.create) {
            nextCard = current.copyWith(
              revision: current.revision + 1,
              archived: true,
            );
          } else {
            final before = undo.beforeCard;
            if (before == null) {
              return _failedReceipt(
                operationId,
                current.cardId,
                WidgetCommandError.notFound,
                '撤销材料不完整。',
                revision: current.revision,
              );
            }
            nextCard = before.copyWith(
              revision: current.revision + 1,
              visibility: current.visibility,
            );
          }
          cards[current.cardId] = nextCard;
          visibility[current.cardId] = nextCard.visibility;
          nextUndo = WidgetStoreUndo(
            targetOperationId: operationId,
            appliedAtMs: nowMs,
            beforeCard: current,
          );
          break;
        }
    }

    if (!await _authorized(authorize)) {
      return _failedReceipt(
        operationId,
        nextCard.cardId,
        WidgetCommandError.forbidden,
        '提交前复核发现当前权限不允许写入桌面小组件配置。',
        revision: nextCard.revision,
      );
    }

    lastMutations[nextCard.cardId] = operationId;
    undoByCard[nextCard.cardId] = nextUndo;
    final receipt = CardWriteReceipt(
      operationId: operationId,
      status: CardWriteStatus.applied,
      cardId: nextCard.cardId,
      revision: nextCard.revision,
      publishStatus: WidgetPublishStatus.pending,
    );
    operations[operationId] = WidgetStoreOperation(
      signature: command.normalizedSignature,
      command: command,
      receipt: receipt,
      appliedAtMs: nowMs,
    );
    var committed = WidgetStoreState(
      cards: cards,
      visibility: visibility,
      operations: operations,
      lastMutationByCard: lastMutations,
      undoByCard: undoByCard,
    );
    try {
      await _store.writeState(committed);
    } on Object catch (error) {
      return _failedReceipt(
        operationId,
        nextCard.cardId,
        WidgetCommandError.storageError,
        error.toString(),
        revision: nextCard.revision,
      );
    }
    if (!_disposed) notifyListeners();

    final publishResult = await refreshWidgets();
    final effectiveStatus =
        publishResult.status == WidgetPublishStatus.published
        ? WidgetPublishStatus.published
        : WidgetPublishStatus.pending;
    final updatedReceipt = receipt.copyWith(publishStatus: effectiveStatus);
    final updatedOperations = Map<String, WidgetStoreOperation>.of(operations)
      ..[operationId] = operations[operationId]!.copyWith(
        receipt: updatedReceipt,
      );
    committed = WidgetStoreState(
      cards: cards,
      visibility: visibility,
      operations: updatedOperations,
      lastMutationByCard: lastMutations,
      undoByCard: undoByCard,
    );
    try {
      await _store.writeState(committed);
    } on Object {
      return receipt;
    }
    if (!_disposed) notifyListeners();
    return updatedReceipt;
  }

  String? _validateSpec(CardSpec spec, CardSpec? previous) {
    final tables = {for (final table in _tables.tables) table.id: table};
    final previousSections = {
      for (final section in previous?.sections ?? const <SectionSpec>[])
        section.tableId: section,
    };
    final previousExcluded =
        previous?.excludedTableIds.toSet() ?? const <String>{};

    for (final section in spec.sections) {
      if (!tables.containsKey(section.tableId)) {
        if (!previousSections.containsKey(section.tableId)) {
          return '数据表 ${section.tableId} 不存在。';
        }
        continue;
      }
      final table = tables[section.tableId]!;
      final existingFields =
          previousSections[section.tableId]?.fields
              .map((field) => field.wireName)
              .toSet() ??
          const <String>{};
      final fieldIds = table.fields.map((field) => field.id).toSet();
      for (final field in section.fields) {
        final customFieldId = field.customFieldId;
        if (customFieldId != null &&
            !fieldIds.contains(customFieldId) &&
            !existingFields.contains(field.wireName)) {
          return '字段 custom:$customFieldId 在数据表 ${table.id} 中不存在。';
        }
      }
    }
    for (final tableId in spec.excludedTableIds) {
      if (!tables.containsKey(tableId) && !previousExcluded.contains(tableId)) {
        return '排除的数据表 $tableId 不存在。';
      }
    }
    return null;
  }

  CardWriteReceipt? _revisionError(
    String operationId,
    CardCommand command,
    CardDefinition? current,
  ) {
    if (current == null) {
      return _failedReceipt(
        operationId,
        command.cardId,
        WidgetCommandError.notFound,
        '桌面小组件不存在。',
      );
    }
    if (command.expectedRevision != current.revision) {
      return _failedReceipt(
        operationId,
        current.cardId,
        WidgetCommandError.revisionConflict,
        '桌面小组件版本已变化。',
        revision: current.revision,
      );
    }
    return null;
  }

  Future<bool> _authorized(Future<bool> Function() authorize) async {
    if (_blocked()) return false;
    try {
      return await authorize();
    } on Object {
      return false;
    }
  }

  String? _commandShapeError(CardCommand command, String operationId) {
    if (operationId.trim().isEmpty) return 'operationId 不能为空。';
    if (command.kind == CardCommandKind.create) {
      return command.spec == null ? 'create 缺少 spec。' : null;
    }
    if (command.cardId == null || command.cardId!.trim().isEmpty) {
      return 'card_id 不能为空。';
    }
    if (command.expectedRevision == null || command.expectedRevision! < 1) {
      return 'expected_revision 必须是正整数。';
    }
    if (command.kind == CardCommandKind.replace && command.spec == null) {
      return 'replace 缺少 spec。';
    }
    if (command.kind == CardCommandKind.setVisibility &&
        command.visibility == null) {
      return 'set_visibility 缺少 visibility。';
    }
    if (command.kind == CardCommandKind.undo &&
        (command.targetOperationId == null ||
            command.targetOperationId!.trim().isEmpty)) {
      return 'undo 缺少 target_operation_id。';
    }
    return null;
  }

  CardWriteReceipt _failedReceipt(
    String operationId,
    String? cardId,
    WidgetCommandError error,
    String message, {
    int revision = 0,
  }) => CardWriteReceipt(
    operationId: operationId,
    status: CardWriteStatus.failed,
    cardId: cardId?.trim().isNotEmpty == true ? cardId! : 'unknown',
    revision: revision,
    publishStatus: WidgetPublishStatus.pending,
    error: error,
    message: message,
  );

  void _scheduleRefresh() {
    if (!_initialized || _disposed) return;
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(refreshDelay, () {
      unawaited(refreshWidgets());
    });
  }

  Future<T> _serializedMutation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _mutationTail = _mutationTail.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _ensureInitialized() {
    _ensureNotDisposed();
    if (!_initialized) {
      throw StateError('WidgetWorkspace.initialize() must complete first.');
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('WidgetWorkspace is disposed.');
  }
}
