import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/data/disk_space_probe.dart';

void main() {
  test(
    'Windows disk probe reports capacity for an existing directory',
    () async {
      if (!Platform.isWindows) return;
      final available = await availableBytesForPath(Directory.systemTemp.path);
      expect(available, isNotNull);
      expect(available, greaterThan(0));
    },
  );
}
