import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/android_ui_case_runner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final cases = loadAndroidUiCases();

  for (final item in cases) {
    testWidgets('${item.id} ${item.description}', (tester) async {
      await runAndroidUiCase(tester, item);
    });
  }
}
