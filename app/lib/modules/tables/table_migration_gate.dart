import 'package:flutter/foundation.dart';

import '../../data/table_migration_service.dart';

/// Keeps the legacy application read-only while a required migration is under
/// review. The production runtime performs this check before starting modules
/// that can write user data.
class TableMigrationGate extends ChangeNotifier {
  TableMigrationGate({
    required TableMigrationService service,
    this.onMigrationComplete,
  }) : _service = service,
       isEnabled = true;

  TableMigrationGate.disabled()
    : _service = null,
      onMigrationComplete = null,
      isEnabled = false;

  final TableMigrationService? _service;
  final Future<void> Function()? onMigrationComplete;
  final bool isEnabled;

  TableMigrationPreview? _preview;
  TableMigrationReceipt? _receipt;
  String? _error;
  bool _isChecking = false;
  bool _isApplying = false;
  bool _barrierActive = false;

  TableMigrationPreview? get preview => _preview;
  TableMigrationPreviewPresentation? get previewPresentation {
    final current = _preview;
    if (current == null) return null;
    return TableMigrationPreviewPresentation(
      legacyRecordCount: current.legacyRecords.length,
      tablesCount: current.tables.length,
      entryCount: current.entries.length,
      estimatedBackupBytes: current.estimatedBackupBytes,
      estimatedOutputBytes: current.estimatedOutputBytes,
      estimatedRequiredBytes: current.estimatedRequiredBytes,
      availableBytes: current.availableBytes,
      issues: [
        for (final issue in current.issues)
          TableMigrationIssuePresentation(
            path: issue.path,
            message: issue.message,
          ),
      ],
      records: [
        for (final record in current.legacyRecords)
          LegacyMigrationRecordPresentation(
            type: record.type.wireName,
            title: record.title,
            body: record.body,
            status: record.status.wireName,
            deleted: record.deleted,
            sourcePath: record.sourcePath,
          ),
      ],
    );
  }

  TableMigrationReceipt? get receipt => _receipt;
  String? get error => _error;
  bool get isChecking => _isChecking;
  bool get isApplying => _isApplying;
  bool get migrationComplete => _receipt != null;
  bool get requiresReadOnly =>
      isEnabled &&
      (_error != null ||
          (_preview?.hasLegacyContent == true && !migrationComplete));

  Future<void> initialize() async {
    if (!isEnabled) return;
    await refresh();
  }

  Future<void> refresh() async {
    final service = _service;
    if (service == null) return;
    _isChecking = true;
    _error = null;
    notifyListeners();
    try {
      await service.resumeSourceCleanup();
      _preview = await service.preview();
      _receipt = await service.completedReceipt(_preview!);
      if (_receipt != null && _preview!.hasLegacyContent) {
        await service.cleanupLegacySources(_preview!);
        _preview = await service.preview();
      }
    } on Object catch (error) {
      _preview = null;
      _receipt = null;
      _error = error.toString();
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  Future<TableMigrationReceipt> applyMigration() async {
    final service = _service;
    final current = _preview;
    if (service == null || current == null || !current.canApply) {
      throw StateError('迁移预检未通过，不能开始迁移。');
    }
    if (_receipt != null || _isApplying || !requiresReadOnly) {
      throw StateError('当前迁移状态不允许重复执行。');
    }
    _isApplying = true;
    _error = null;
    notifyListeners();
    try {
      final receipt = await service.apply(current);
      await service.cleanupLegacySources(current);
      await onMigrationComplete?.call();
      _preview = await service.preview();
      _receipt = receipt;
      return receipt;
    } on Object catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _isApplying = false;
      notifyListeners();
    }
  }

  Future<TableMigrationReceipt> runStartupMigrationBarrier(
    Future<TableMigrationReceipt> Function() operation,
  ) async {
    if (!requiresReadOnly || _barrierActive) {
      throw StateError('表迁移只允许在启动只读门内执行。');
    }
    _barrierActive = true;
    try {
      return await operation();
    } finally {
      _barrierActive = false;
    }
  }
}

class TableMigrationPreviewPresentation {
  const TableMigrationPreviewPresentation({
    required this.legacyRecordCount,
    required this.tablesCount,
    required this.entryCount,
    required this.estimatedBackupBytes,
    required this.estimatedOutputBytes,
    required this.estimatedRequiredBytes,
    required this.availableBytes,
    required this.issues,
    required this.records,
  });

  final int legacyRecordCount;
  final int tablesCount;
  final int entryCount;
  final int estimatedBackupBytes;
  final int estimatedOutputBytes;
  final int estimatedRequiredBytes;
  final int? availableBytes;
  final List<TableMigrationIssuePresentation> issues;
  final List<LegacyMigrationRecordPresentation> records;
}

class TableMigrationIssuePresentation {
  const TableMigrationIssuePresentation({
    required this.path,
    required this.message,
  });

  final String path;
  final String message;
}

class LegacyMigrationRecordPresentation {
  const LegacyMigrationRecordPresentation({
    required this.type,
    required this.title,
    required this.body,
    required this.status,
    required this.deleted,
    required this.sourcePath,
  });

  final String type;
  final String title;
  final String body;
  final String status;
  final bool deleted;
  final String sourcePath;
}
