import 'migration_coordinator.dart';
import 'settings_service.dart';
import 'sqlite_migration_coordinator.dart';

Future<MigrationCoordinator?> createMigrationCoordinator({
  required String supportPath,
  required SettingsService settings,
}) async =>
    SqliteMigrationCoordinator(supportPath: supportPath, settings: settings);
