import 'package:flutter_test/flutter_test.dart';

import 'android_ui_case_runner.dart';
import 'device_acceptance_case_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cases = loadDeviceAcceptanceCases();

  test('Device acceptance matrix contains 100 independent cases', () {
    expect(cases, hasLength(100));
    expect(cases.map((item) => item.id).toSet(), hasLength(100));
    expect(cases.where((item) => item.device == 'phone'), hasLength(50));
    expect(cases.where((item) => item.device == 'tablet'), hasLength(50));
    expect(cases.where((item) => item.theme == 'dark'), isNotEmpty);
    expect(cases.where((item) => item.fontScale >= 1.5), hasLength(14));
    expect(
      cases.map((item) => item.action).toSet(),
      containsAll([
        'navigate',
        'font_scale',
        'vertical_swipe',
        'horizontal_swipe',
        'toggle_filter',
        'open_detail',
        'capture',
        'theme_switch',
        'scroll_to_bottom',
        'button_tap',
      ]),
    );
  });

  for (final item in cases) {
    testWidgets('${item.id} ${item.description}', (tester) async {
      await runAndroidUiCase(tester, item);
    });
  }
}
