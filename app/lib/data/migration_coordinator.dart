abstract interface class MigrationCoordinator {
  Future<void> prepare();

  Future<void> complete();

  Future<void> rollback();
}
