import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/data/home_widget_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'widget bridge sends the snapshot and consumes a tap only once',
    () async {
      const channel = MethodChannel(
        'com.yuanfang.aitext.personal_ai_inbox/home_widgets',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Map<String, Object?>? target = {
        'kind': 'entry',
        'table_id': 'tb_work',
        'entry_id': 'todo_fixture',
      };
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'publishSnapshots':
            return {'submitted_count': 2, 'failed_count': 1};
          case 'takeOpenTarget':
            final current = target;
            target = null;
            return current;
        }
        throw MissingPluginException(call.method);
      });
      final bridge = HomeWidgetBridge();
      addTearDown(() {
        bridge.dispose();
        messenger.setMockMethodCallHandler(channel, null);
      });

      const json = '{"schema_version":1,"cards":[]}';
      final published = await bridge.publishSnapshots(json);
      expect(published.submittedCount, 2);
      expect(published.failedCount, 1);
      expect(calls.first.arguments, {'snapshot_json': json});
      expect((await bridge.takeOpenTarget())?['entry_id'], 'todo_fixture');
      expect(await bridge.takeOpenTarget(), isNull);
    },
  );
}
