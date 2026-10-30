import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:personal_ai_inbox/data/disk_space_probe.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android returns available bytes for app support storage', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final available = await availableBytesForPath(support.path);
    expect(available, isNotNull);
    expect(available, greaterThan(0));
  });
}
