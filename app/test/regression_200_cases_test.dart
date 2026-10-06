import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/sync_engine.dart';
import 'package:personal_ai_inbox/data/sync_provider.dart';
import 'package:personal_ai_inbox/services/app_controller.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';
import 'package:personal_ai_inbox/ui/widgets/common.dart';

import 'test_support.dart';

void main() {
  late List<RegressionCase> cases;

  setUpAll(() {
    final payload = jsonDecode(
      File('test/fixtures/regression_cases.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    cases = (payload['cases'] as List)
        .map((item) => RegressionCase.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  });

  test('fixture contains 200 distributed cases', () {
    expect(cases, hasLength(200));
    expect(cases.where((item) => item.device == 'phone'), hasLength(67));
    expect(cases.where((item) => item.device == 'tablet'), hasLength(67));
    expect(cases.where((item) => item.device == 'desktop'), hasLength(66));
    for (final size in const ['small', 'medium', 'large', 'xlarge']) {
      expect(
        cases.where((item) => item.size == size),
        hasLength(50),
        reason: 'size bucket $size',
      );
    }
    expect(
      cases.map((item) => item.text.length).reduce((a, b) => a + b),
      greaterThan(250000),
    );
  });

  test('all 200 cases classify on their assigned device profile', () {
    const parser = DeterministicParser();
    final now = DateTime(2026, 10, 4, 10, 30);
    final failures = <String>[];

    for (final item in cases) {
      final actual = parser.parse(item.text, now);
      if (actual.type != item.expectedType) {
        failures.add(
          '${item.id} ${item.device}/${item.size}: '
          'type ${actual.type.wireName} != ${item.expectedType.wireName}',
        );
        continue;
      }
      if (actual.needsReview != item.expectReview) {
        failures.add(
          '${item.id} ${item.device}/${item.size}: '
          'review ${actual.needsReview} != ${item.expectReview}',
        );
        continue;
      }
      if (item.expectedStart != null && actual.start != item.expectedStart) {
        failures.add(
          '${item.id} ${item.device}/${item.size}: '
          'start ${actual.start} != ${item.expectedStart}',
        );
        continue;
      }
      if (item.expectedDue != null && actual.due != item.expectedDue) {
        failures.add(
          '${item.id} ${item.device}/${item.size}: '
          'due ${actual.due} != ${item.expectedDue}',
        );
      }
    }

    expect(failures, isEmpty, reason: failures.take(20).join('\n'));
  });

  group('three device backends', () {
    for (final profile in DeviceProfile.values) {
      test('${profile.name} persists, rebuilds, and syncs its cases', () async {
        final assigned = cases
            .where((item) => item.device == profile.name)
            .toList(growable: false);
        final harness = await _buildHarness(profile, assigned);

        expect(harness.controller.documents, hasLength(assigned.length));
        expect(
          await harness.vault.listMarkdownFiles(),
          hasLength(assigned.length),
        );
        expect(await harness.index.listResults(), hasLength(assigned.length));

        await harness.index.clear();
        await harness.repository.rebuildIndex();
        expect(await harness.index.listResults(), hasLength(assigned.length));

        final first = await harness.engine.sync();
        final second = await harness.engine.sync();
        expect(first.uploaded, assigned.length);
        expect(first.failed, 0);
        expect(second.unchanged, assigned.length);
        expect(second.uploaded, 0);
      });
    }
  });

  for (final profile in DeviceProfile.values) {
    testWidgets('${profile.name} frontend renders its assigned cases', (
      tester,
    ) async {
      tester.view.physicalSize = profile.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final assigned = cases
          .where((item) => item.device == profile.name)
          .toList(growable: false);
      final harness = await _buildHarness(profile, assigned);
      await tester.pumpWidget(
        PersonalAiInboxApp(controller: harness.controller),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      if (profile.compact) {
        await _tapAndScroll(tester, const Key('nav_inbox'));
        await _tapAndScroll(tester, const Key('nav_calendar'));
        await _tapAndScroll(tester, const Key('nav_todos'));
        await tester.tap(find.byKey(const Key('nav_more')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sheet_nav_knowledge')));
        await tester.pumpAndSettle();
        await _tapFirstDocument(tester);
        await tester.tap(find.byKey(const Key('nav_more')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sheet_nav_settings')));
        await tester.pumpAndSettle();
      } else {
        for (final key in const [
          'nav_inbox',
          'nav_calendar',
          'nav_todos',
          'nav_matters',
          'nav_knowledge',
          'nav_review',
          'nav_sync',
          'nav_settings',
        ]) {
          await _tapAndScroll(tester, Key(key));
          if (key == 'nav_knowledge') {
            await _tapFirstDocument(tester);
          }
        }
      }

      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _tapAndScroll(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isNotEmpty) {
    await tester.drag(scrollables.first, const Offset(0, -700));
    await tester.pumpAndSettle();
  }
  expect(tester.takeException(), isNull);
}

Future<void> _tapFirstDocument(WidgetTester tester) async {
  final documents = find.byType(DocumentListTile);
  if (documents.evaluate().isEmpty) {
    return;
  }
  await tester.ensureVisible(documents.first);
  await tester.pumpAndSettle();
  await tester.tap(documents.first);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await tester.pageBack();
  await tester.pumpAndSettle();
}

Future<_Harness> _buildHarness(
  DeviceProfile profile,
  List<RegressionCase> cases,
) async {
  final vault = MemoryVaultStore();
  final index = MemoryIndexDatabase();
  final settings = FakeSettingsService(deviceId: profile.deviceId);
  final repository = ResultRepository(
    vault: vault,
    index: index,
    deviceId: profile.deviceId,
  );
  await repository.initialize();
  for (final item in cases) {
    await repository.create(
      type: item.expectedType,
      title: '${item.id} ${item.titleHint}',
      body: item.text,
      due: item.expectedDue,
      start: item.expectedStart,
      end: item.expectedStart?.add(const Duration(hours: 1)),
    );
  }
  final provider = MemorySyncProvider();
  final engine = SyncEngine(
    repository: repository,
    provider: provider,
    deviceId: profile.deviceId,
  );
  final controller = AppController(
    repository: repository,
    indexDatabase: index,
    captureService: CaptureService(
      settings: settings,
      parser: const DeterministicParser(),
    ),
    settingsService: settings,
    syncEngine: engine,
  );
  await controller.initialize();
  return _Harness(
    controller: controller,
    repository: repository,
    vault: vault,
    index: index,
    engine: engine,
  );
}

class _Harness {
  const _Harness({
    required this.controller,
    required this.repository,
    required this.vault,
    required this.index,
    required this.engine,
  });

  final AppController controller;
  final ResultRepository repository;
  final MemoryVaultStore vault;
  final MemoryIndexDatabase index;
  final SyncEngine engine;
}

enum DeviceProfile {
  phone(size: Size(390, 844), deviceId: 'honor-phone'),
  tablet(size: Size(1024, 768), deviceId: 'galaxy-tab'),
  desktop(size: Size(1440, 900), deviceId: 'win-desktop');

  const DeviceProfile({required this.size, required this.deviceId});

  final Size size;
  final String deviceId;

  bool get compact => size.width < 980;
}

class RegressionCase {
  const RegressionCase({
    required this.id,
    required this.device,
    required this.size,
    required this.text,
    required this.expectedType,
    required this.expectReview,
    required this.titleHint,
    this.expectedStart,
    this.expectedDue,
  });

  factory RegressionCase.fromJson(Map<String, dynamic> json) {
    return RegressionCase(
      id: json['id'] as String,
      device: json['device'] as String,
      size: json['size'] as String,
      text: json['text'] as String,
      expectedType: ResultType.parse(json['expectedType'] as String),
      expectReview: json['expectReview'] as bool,
      titleHint: json['titleHint'] as String,
      expectedStart: _date(json['expectedStart']),
      expectedDue: _date(json['expectedDue']),
    );
  }

  final String id;
  final String device;
  final String size;
  final String text;
  final ResultType expectedType;
  final bool expectReview;
  final String titleHint;
  final DateTime? expectedStart;
  final DateTime? expectedDue;

  static DateTime? _date(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.parse(value as String);
  }
}
