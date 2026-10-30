import 'package:flutter/foundation.dart';

import '../../data/table_migration_service.dart';

/// Keeps the legacy application read-only while a required migration is under
/// review. The production runtime performs this check before starting modules
/// that can write user data.
class TableMigrationGate extends ChangeNotifier {
  TableMigrationGate({required TableMigrationService service})
    : _service = service,
      isEnabled = true;

  TableMigrationGate.disabled() : _service = null, isEnabled = false;

  final TableMigrationService? _service;
  final bool isEnabled;

  TableMigrationPreview? _preview;
  TableMigrationReceipt? _receipt;
  String? _error;
  bool _isChecking = false;
  bool _isApplying = false;
  bool _barrierActive = false;

  TableMigrationPreview? get preview => _preview;
  TableMigrationReceipt? get receipt => _receipt;
  String? get error => _error;
  bool get isChecking => _isChecking;
  bool get isApplying => _isApplying;
  bool get migrationComplete => _receipt != null;
  bool get requiresReadOnly =>
      isEnabled && (_error != null || _preview?.hasLegacyContent == true);

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
      _preview = await service.preview();
      _receipt = await service.completedReceipt(_preview!);
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
      _receipt = await service.apply(current);
      return _receipt!;
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
