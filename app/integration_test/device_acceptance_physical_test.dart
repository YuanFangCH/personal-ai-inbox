import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/android_ui_case_runner.dart';
import '../test/device_acceptance_case_runner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const profile = String.fromEnvironment('DEVICE_UNDER_TEST');
  if (!isSupportedDeviceProfile(profile)) {
    throw StateError(
      'DEVICE_UNDER_TEST must be honor-phone or galaxy-tab; got "$profile".',
    );
  }
  final cases = loadDeviceAcceptanceCases(target: profile);

  test('$profile contains 50 physical device acceptance cases', () {
    expect(cases, hasLength(50));
  });

  for (final item in cases) {
    testWidgets('${item.id} ${item.description}', (tester) async {
      await runAndroidUiCase(tester, item, simulateViewport: false);
    });
  }
}
