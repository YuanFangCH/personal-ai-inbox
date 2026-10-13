import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models.dart';
import '../../data/index_database.dart';
import '../../data/result_repository.dart';
import '../../data/sync_engine.dart';
import '../results/result_library.dart';

/// Application module that owns the visible state of a sync round.
///
/// Callers never need to touch [SyncEngine] directly. The module keeps the
/// engine and conflict storage behind a small stateful interface and converts
/// failures into [errorMessage] so UI code does not handle raw exceptions.
class SyncWorkspace extends ChangeNotifier {
  SyncWorkspace({
    required SyncEngine engine,
    required ResultRepository repository,
    ResultLibrary? results,
  }) : _engine = engine,
       _repository = repository,
       _results = results;

  final SyncEngine _engine;
  final ResultRepository _repository;
  final ResultLibrary? _results;

  SyncReport? _lastReport;
  List<String> _conflictFiles = const [];
  bool _isBusy = false;
  String? _errorMessage;
  Completer<void>? _activeSync;

  SyncReport? get lastReport => _lastReport;

  List<String> get conflictFiles => List.unmodifiable(_conflictFiles);

  bool get isBusy => _isBusy;

  String get providerName => _engine.provider.displayName;

  /// Current user-visible failure. Structured per-object failures remain a
  /// future [SyncReport] evolution point; this slice exposes the aggregate
  /// error without changing the existing report model.
  String? get errorMessage => _errorMessage;

  Future<void> initialize() => refresh();

  Future<void> shutdown() async {
    await _activeSync?.future;
  }

  Future<void> refresh() async {
    try {
      _conflictFiles = List.unmodifiable(await _repository.listConflictFiles());
    } catch (error) {
      _errorMessage = _formatFailure('刷新同步状态失败', error);
    }
    notifyListeners();
  }

  Future<void> syncNow() async {
    if (_isBusy) {
      return;
    }

    _isBusy = true;
    final activeSync = Completer<void>();
    _activeSync = activeSync;
    _errorMessage = null;
    notifyListeners();

    try {
      final report = await _engine.sync();
      _lastReport = report;
      await _results?.refresh();
      if (report.failed > 0) {
        final reportMessage = report.message?.trim();
        _errorMessage = reportMessage == null || reportMessage.isEmpty
            ? '同步有 ${report.failed} 项失败'
            : reportMessage;
      }
      _conflictFiles = List.unmodifiable(await _repository.listConflictFiles());
    } catch (error) {
      _errorMessage = _formatFailure('同步失败', error);
    } finally {
      _isBusy = false;
      notifyListeners();
      activeSync.complete();
      if (identical(_activeSync, activeSync)) _activeSync = null;
    }
  }

  Future<void> resolveConflict(String path, {required bool useRemote}) async {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      _errorMessage = '未指定冲突副本';
      notifyListeners();
      return;
    }

    try {
      if (!_conflictFiles.contains(normalizedPath)) {
        _errorMessage = '冲突副本不存在或已处理';
        return;
      }

      SyncConflictRecord? conflict;
      for (final candidate in await _repository.listConflicts()) {
        if (candidate.copyPath == normalizedPath) conflict = candidate;
      }
      if (conflict == null) throw StateError('冲突记录不存在或已处理');
      await _engine.resolveConflict(conflict.resultId, useRemote: useRemote);
      await _results?.refresh();
      _conflictFiles = List.unmodifiable(await _repository.listConflictFiles());
      _errorMessage = null;
    } catch (error) {
      _errorMessage = _formatFailure('冲突裁决失败', error);
    } finally {
      notifyListeners();
    }
  }

  String _formatFailure(String fallback, Object error) {
    final details = error is StateError ? error.message : error.toString();
    return details.trim().isEmpty ? fallback : '$fallback：$details';
  }
}
