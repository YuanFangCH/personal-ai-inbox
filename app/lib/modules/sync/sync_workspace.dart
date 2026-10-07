import 'package:flutter/foundation.dart';

import '../../core/models.dart';
import '../../data/result_repository.dart';
import '../../data/sync_engine.dart';

/// Application module that owns the visible state of a sync round.
///
/// Callers never need to touch [SyncEngine] directly. The module keeps the
/// engine and conflict storage behind a small stateful interface and converts
/// failures into [errorMessage] so UI code does not handle raw exceptions.
class SyncWorkspace extends ChangeNotifier {
  SyncWorkspace({
    required SyncEngine engine,
    required ResultRepository repository,
  }) : _engine = engine,
       _repository = repository;

  final SyncEngine _engine;
  final ResultRepository _repository;

  SyncReport? _lastReport;
  List<String> _conflictFiles = const [];
  bool _isBusy = false;
  String? _errorMessage;

  SyncReport? get lastReport => _lastReport;

  List<String> get conflictFiles => List.unmodifiable(_conflictFiles);

  bool get isBusy => _isBusy;

  String get providerName => _engine.provider.displayName;

  /// Current user-visible failure. Structured per-object failures remain a
  /// future [SyncReport] evolution point; this slice exposes the aggregate
  /// error without changing the existing report model.
  String? get errorMessage => _errorMessage;

  Future<void> initialize() => refresh();

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
    _errorMessage = null;
    notifyListeners();

    try {
      final report = await _engine.sync();
      _lastReport = report;
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

      if (useRemote) {
        await _repository.resolveConflictUsingRemote(normalizedPath);
      } else {
        await _repository.keepLocalConflict(normalizedPath);
      }
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
