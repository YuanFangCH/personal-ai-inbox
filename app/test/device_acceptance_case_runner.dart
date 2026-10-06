import 'android_ui_case_runner.dart';
import 'device_acceptance_100_cases.g.dart';

List<AndroidUiCase> loadDeviceAcceptanceCases({String? target}) {
  return deviceAcceptanceCaseMaps
      .where((item) => target == null || item['target'] == target)
      .map(AndroidUiCase.fromMap)
      .toList(growable: false);
}

bool isSupportedDeviceProfile(String profile) {
  return profile == 'honor-phone' || profile == 'galaxy-tab';
}
