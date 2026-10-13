import 'migration_coordinator.dart';
import 'migration_coordinator_factory_stub.dart'
    if (dart.library.io) 'migration_coordinator_factory_io.dart'
    as platform;
import 'settings_service.dart';

Future<MigrationCoordinator?> createMigrationCoordinator({
  required String supportPath,
  required SettingsService settings,
}) => platform.createMigrationCoordinator(
  supportPath: supportPath,
  settings: settings,
);
