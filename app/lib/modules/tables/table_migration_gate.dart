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
  String? _error;
  bool _isChecking = false;
  bool _barrierActive = false;

  TableMigrationPreview? get preview => _preview;
  String? get error => _error;
  bool get isChecking => _isChecking;
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
    } on Object catch (error) {
      _preview = null;
      _error = error.toString();
    } finally {
      _isChecking = false;
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
