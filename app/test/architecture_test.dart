import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('dependency guard rejects import, export, and part violations', () {
    final violations = _violatingPaths(
      "import 'package:flutter/widgets.dart';\n"
      "export '../data/result_repository.dart';\n"
      "part '../ui/private_part.dart';\n"
      "import '../bootstrap/./app_runtime.dart';\n",
      const ['package:flutter/', '../data/', '../ui/', '../bootstrap/'],
    );

    expect(violations, hasLength(4));
  });

  test('module cycle guard detects a deliberately cyclic graph', () {
    expect(
      _hasCycle({
        'capture': {'results'},
        'results': {'capture'},
      }),
      isTrue,
    );
    expect(
      _hasCycle({
        'capture': {'results'},
        'results': {'settings'},
        'settings': <String>{},
      }),
      isFalse,
    );
  });

  test('module dependencies keep the intended direction', () {
    final violations = <String>[];

    for (final file in [
      ..._dartFiles('lib/domain'),
      ..._dartFiles('lib/core'),
    ]) {
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
    final moduleGraph = _moduleDependencyGraph(_dartFiles('lib/modules'));
    if (_hasCycle(moduleGraph)) {
      violations.add('lib/modules: dependency cycle: $moduleGraph');
    }

    for (final file in _dartFiles('lib/ui')) {
      _rejectImports(file, violations, const [
        '../data/',
        'package:personal_ai_inbox/data/',
        '../bootstrap/',
        'package:personal_ai_inbox/bootstrap/',
        'services/app_controller.dart',
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

Map<String, Set<String>> _moduleDependencyGraph(List<File> files) {
  final graph = <String, Set<String>>{};
  for (final file in files) {
    final sourceModule = _moduleInPath(file.path);
    if (sourceModule == null) continue;
    graph.putIfAbsent(sourceModule, () => <String>{});
    for (final line in file.readAsLinesSync()) {
      final directive = RegExp(
        r'''^(?:import|export|part)\s+['"]([^'"]+)['"]''',
      ).firstMatch(line.trim());
      if (directive == null) continue;
      final destination = _moduleInImport(file.path, directive.group(1)!);
      if (destination != null && destination != sourceModule) {
        graph[sourceModule]!.add(destination);
      }
    }
  }
  return graph;
}

String? _moduleInImport(String sourcePath, String importPath) {
  final normalized = importPath.replaceAll('\\', '/');
  if (normalized.startsWith('package:personal_ai_inbox/')) {
    return _moduleInPath(
      normalized.substring('package:personal_ai_inbox/'.length),
    );
  }
  if (normalized.startsWith('package:') || p.isAbsolute(normalized)) {
    return null;
  }
  return _moduleInPath(p.normalize(p.join(p.dirname(sourcePath), normalized)));
}

String? _moduleInPath(String path) {
  final parts = path.replaceAll('\\', '/').split('/');
  final modulesIndex = parts.indexOf('modules');
  return modulesIndex >= 0 && modulesIndex + 1 < parts.length
      ? parts[modulesIndex + 1]
      : null;
}

bool _hasCycle(Map<String, Set<String>> graph) {
  final visiting = <String>{};
  final visited = <String>{};

  bool visit(String node) {
    if (visiting.contains(node)) return true;
    if (!visited.add(node)) return false;
    visiting.add(node);
    for (final dependency in graph[node] ?? const <String>{}) {
      if (visit(dependency)) return true;
    }
    visiting.remove(node);
    return false;
  }

  for (final node in graph.keys) {
    if (visit(node)) return true;
  }
  return false;
}

void _rejectImports(
  File file,
  List<String> violations,
  List<String> forbiddenFragments,
) {
  for (final line in _violatingPaths(
    file.readAsStringSync(),
    forbiddenFragments,
  )) {
    violations.add('${file.path}: $line');
  }
}

List<String> _violatingPaths(String source, List<String> forbiddenFragments) {
  final violations = <String>[];
  for (final line in source.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('import ') &&
        !trimmed.startsWith('export ') &&
        !trimmed.startsWith('part ')) {
      continue;
    }
    final directive = RegExp(r'''^(?:import|export|part)\s+['"]([^'"]+)['"]''')
        .firstMatch(trimmed);
    if (directive == null) continue;
    final path = _normalizePath(directive.group(1)!);
    for (final fragment in forbiddenFragments) {
      if (path.contains(_normalizePath(fragment))) {
        violations.add(trimmed);
      }
    }
  }
  return violations;
}

String _normalizePath(String path) {
  final normalizedSlashes = path.replaceAll('\\', '/');
  final colon = normalizedSlashes.indexOf(':');
  final prefix = colon >= 0 ? normalizedSlashes.substring(0, colon + 1) : '';
  final remainder = colon >= 0
      ? normalizedSlashes.substring(colon + 1)
      : normalizedSlashes;
  final absolute = remainder.startsWith('/');
  final segments = <String>[];
  for (final segment in remainder.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..' && segments.isNotEmpty && segments.last != '..') {
      segments.removeLast();
    } else if (segment == '..' && !absolute) {
      segments.add(segment);
    } else if (segment != '..') {
      segments.add(segment);
    }
  }
  return '$prefix${absolute ? '/' : ''}${segments.join('/')}';
}
