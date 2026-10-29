import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/table_models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android runtime seeds three role-stable tables idempotently across restart',
    (_) async {
      final first = await AppRuntime.bootstrap();
      final firstTables = first.tables.tables;
      expect(firstTables, hasLength(3));
      expect(firstTables.map((table) => (table.id, table.role)).toSet(), {
        ('tb_default_todo', TableRole.inboxTodo),
        ('tb_default_schedule', TableRole.inboxSchedule),
        ('tb_default_event', TableRole.inboxEvent),
      });
      await first.shutdown();

      final restarted = await AppRuntime.bootstrap();
      expect(restarted.tables.tables, hasLength(3));
      expect(restarted.tables.tables.map((table) => table.id).toSet(), {
        'tb_default_todo',
        'tb_default_schedule',
        'tb_default_event',
      });
      await restarted.shutdown();
    },
  );
}
