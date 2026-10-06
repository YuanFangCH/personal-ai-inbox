import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android main manifest includes release network and share entrypoints',
    () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();

      expect(manifest, contains('android.permission.INTERNET'));
      expect(manifest, contains('android.intent.action.SEND'));
      expect(manifest, contains('android.intent.action.PROCESS_TEXT'));
      expect(manifest, contains('text/plain'));
    },
  );
}
