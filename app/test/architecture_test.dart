import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('module dependencies keep the intended direction', () {
    final violations = <String>[];

    for (final file in _dartFiles('lib/domain')) {
      _rejectImports(file, violations, const [
        'package:flutter/',
        '../data/',
        '../modules/',
        '../services/',
        '../ui/',
      ]);
    }

    for (final file in _dartFiles('lib/modules')) {
      _rejectImports(file, violations, const [
        '../ui/',
        'package:personal_ai_inbox/ui/',
        '../bootstrap/',
      ]);
    }

    for (final file in _dartFiles('lib/ui')) {
      _rejectImports(file, violations, const [
        '../data/',
        'package:personal_ai_inbox/data/',
        'modules/results/result_library.dart',
        'modules/sync/sync_workspace.dart',
      ]);
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}

List<File> _dartFiles(String directory) {
  final root = Directory(directory);
  if (!root.existsSync()) {
    return const [];
  }
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);
}

void _rejectImports(
  File file,
  List<String> violations,
  List<String> forbiddenFragments,
) {
  final source = file.readAsStringSync();
  for (final line in source.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
      continue;
    }
    for (final fragment in forbiddenFragments) {
      if (trimmed.contains(fragment)) {
        violations.add('${file.path}: $trimmed');
      }
    }
  }
}
