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
import 'package:personal_ai_inbox/ui/pages/document_detail_page.dart';
import 'package:personal_ai_inbox/ui/widgets/common.dart';

import 'android_ui_100_cases.g.dart';
import 'test_support.dart';

List<AndroidUiCase> loadAndroidUiCases() {
  return androidUiCaseMaps.map(AndroidUiCase.fromMap).toList(growable: false);
}

Future<void> runAndroidUiCase(
  WidgetTester tester,
  AndroidUiCase item, {
  bool simulateViewport = true,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final previousOnError = FlutterError.onError;
  final capturedDetails = <FlutterErrorDetails>[];
  FlutterError.onError = (details) {
    capturedDetails.add(details);
    previousOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousOnError);
  if (simulateViewport) {
    tester.view.physicalSize = Size(item.width, item.height);
    tester.view.devicePixelRatio = item.pixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  tester.platformDispatcher.textScaleFactorTestValue = item.fontScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final controller = await _buildController(item);
  addTearDown(controller.dispose);
  await tester.pumpWidget(PersonalAiInboxApp(controller: controller));
  await tester.pumpAndSettle();
  if (!simulateViewport) {
    _assertPhysicalViewport(tester, item);
  }
  await _goToPage(tester, item);

  await _runAction(tester, controller, item);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await _failIfException(tester, item.id, details: capturedDetails);
}

void _assertPhysicalViewport(WidgetTester tester, AndroidUiCase item) {
  final logicalWidth =
      tester.view.physicalSize.width / tester.view.devicePixelRatio;
  if (item.device == 'phone') {
    expect(
      logicalWidth,
      lessThan(600),
      reason: '${item.id}: expected a compact phone viewport',
    );
  } else {
    expect(
      logicalWidth,
      greaterThanOrEqualTo(600),
      reason: '${item.id}: expected an expanded tablet viewport',
    );
  }
}

Future<AppController> _buildController(AndroidUiCase item) async {
  final vault = MemoryVaultStore();
  final index = MemoryIndexDatabase();
  final settings = FakeSettingsService(
    deviceId: item.device == 'tablet' ? 'android-tablet' : 'android-phone',
    themeMode: item.theme == 'dark' ? ThemeMode.dark : ThemeMode.light,
  );
  final repository = ResultRepository(
    vault: vault,
    index: index,
    deviceId: item.device == 'tablet' ? 'android-tablet' : 'android-phone',
  );
  await repository.initialize();

  final matter = await repository.create(
    type: ResultType.matter,
    title: '英语比赛',
    body: '准备比赛材料，确认报名截止时间。',
  );
  await repository.create(
    type: ResultType.knowledge,
    title: '长文知识 ${item.id}',
    body: List.filled(
      item.fontScale >= 1.5 ? 120 : 40,
      'Android UI 字体与滚动压力测试内容。',
    ).join(),
  );
  await repository.create(
    type: ResultType.todo,
    title: '提交参赛材料',
    body: '',
    due: DateTime.now().add(const Duration(hours: 3)),
    matterId: matter.id,
  );
  await repository.create(
    type: ResultType.event,
    title: '比赛说明会',
    body: '',
    start: DateTime.now().add(const Duration(hours: 1)),
    end: DateTime.now().add(const Duration(hours: 2)),
    matterId: matter.id,
  );
  await index.insertCapture(
    CaptureRecord(
      id: 'cap_${item.id}',
      deviceId: item.device,
      capturedAt: DateTime.now(),
      sourceType: CaptureSourceType.text,
      text: '下周找时间确认比赛资料',
      status: CaptureStatus.needsReview,
      candidateType: ResultType.knowledge,
      candidateTitle: '确认比赛资料',
      confidence: 0.55,
      reviewReason: '日期需要确认',
    ),
  );

  final controller = AppController(
    repository: repository,
    indexDatabase: index,
    captureService: CaptureService(
      settings: settings,
      parser: const DeterministicParser(),
    ),
    settingsService: settings,
    syncEngine: SyncEngine(
      repository: repository,
      provider: MemorySyncProvider(),
      deviceId: item.device == 'tablet' ? 'android-tablet' : 'android-phone',
    ),
  );
  await controller.initialize();
  return controller;
}

Future<void> _goToPage(WidgetTester tester, AndroidUiCase item) async {
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  if (item.page == AndroidUiPage.todos) {
    await tester.tap(find.byKey(const Key('nav_calendar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_section_todos')));
  } else if (width < 980 && item.page.index >= 4) {
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('sheet_nav_${item.page.name}')));
  } else {
    await tester.tap(find.byKey(Key('nav_${item.page.name}')));
  }
  await tester.pumpAndSettle();
  expect(
    find.byKey(
      item.page == AndroidUiPage.todos
          ? const Key('calendar_section_todos')
          : Key('page_${item.page.name}'),
    ),
    findsOneWidget,
    reason: item.id,
  );
}

Future<void> _runAction(
  WidgetTester tester,
  AppController controller,
  AndroidUiCase item,
) async {
  switch (item.action) {
    case 'navigate':
    case 'font_scale':
      return;
    case 'vertical_swipe':
      await _swipeVertical(tester);
      break;
    case 'horizontal_swipe':
      await _swipeHorizontal(tester);
      break;
    case 'toggle_filter':
      await tester.tap(find.text(item.expectedText!).first);
      await tester.pumpAndSettle();
      break;
    case 'open_detail':
      await _openDetail(tester);
      break;
    case 'capture':
      await _capture(tester);
      break;
    case 'theme_switch':
      await _switchTheme(tester, item);
      break;
    case 'scroll_to_bottom':
      await _scrollToBottom(tester);
      break;
    case 'button_tap':
      await _tapPrimaryButton(tester, item.page);
      break;
    default:
      throw StateError('Unsupported action: ${item.action}');
  }
}

Future<void> _swipeVertical(WidgetTester tester) async {
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) {
    return;
  }
  final target = scrollables.first;
  await tester.drag(target, const Offset(0, -420));
  await tester.pumpAndSettle();
  await tester.drag(target, const Offset(0, 180));
  await tester.pumpAndSettle();
}

Future<void> _swipeHorizontal(WidgetTester tester) async {
  final target = find.byType(SegmentedButton).evaluate().isNotEmpty
      ? find.byType(SegmentedButton).first
      : find.byType(Scrollable).first;
  await tester.drag(target, const Offset(-160, 0));
  await tester.pumpAndSettle();
}

Future<void> _openDetail(WidgetTester tester) async {
  final documents = find.byType(DocumentListTile);
  if (documents.evaluate().isEmpty) {
    return;
  }
  await tester.ensureVisible(documents.first);
  await tester.pumpAndSettle();
  await tester.tap(documents.first);
  await tester.pumpAndSettle();
  expect(find.byType(DocumentDetailPage), findsOneWidget);
  await tester.pageBack();
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester) async {
  final captureButton = find.byKey(const Key('capture_button'));
  if (captureButton.evaluate().isNotEmpty) {
    await tester.tap(captureButton);
  } else {
    await tester.tap(find.text('收下内容').first);
  }
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('capture_text_field')),
    '周五下午两点和客户开会',
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('capture_submit')),
    240,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('capture_submit')));
  await tester.pumpAndSettle();
}

Future<void> _switchTheme(WidgetTester tester, AndroidUiCase item) async {
  if (item.page != AndroidUiPage.settings) {
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    if (width < 980) {
      await tester.tap(find.byKey(const Key('nav_more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet_nav_settings')));
    } else {
      await tester.tap(find.byKey(const Key('nav_settings')));
    }
    await tester.pumpAndSettle();
  }
  final target = item.theme == 'dark' ? '浅色' : '深色';
  await tester.tap(find.text(target));
  await tester.pumpAndSettle();
}

Future<void> _scrollToBottom(WidgetTester tester) async {
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) {
    return;
  }
  for (var i = 0; i < 4; i++) {
    await tester.drag(scrollables.first, const Offset(0, -600));
    await tester.pumpAndSettle();
  }
}

Future<void> _tapPrimaryButton(WidgetTester tester, AndroidUiPage page) async {
  if (page == AndroidUiPage.calendar || page == AndroidUiPage.todos) {
    await tester.tap(find.byKey(const Key('calendar_quick_create')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    return;
  }
  final labels = switch (page) {
    AndroidUiPage.home => '收下内容',
    AndroidUiPage.inbox => '收下内容',
    AndroidUiPage.matters => '新建事项',
    AndroidUiPage.knowledge => '新建知识',
    _ => null,
  };
  if (labels == null) {
    return;
  }
  await tester.tap(find.text(labels).first);
  await tester.pumpAndSettle();
  if (find.byKey(const Key('capture_text_field')).evaluate().isNotEmpty) {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  } else {
    await tester.pageBack();
    await tester.pumpAndSettle();
  }
}

Future<void> _failIfException(
  WidgetTester tester,
  String caseId, {
  List<FlutterErrorDetails> details = const [],
}) async {
  final error = tester.takeException();
  if (error == null) {
    return;
  }
  if (error is FlutterError) {
    final diagnostics = details.map((item) => item.toString()).join('\n');
    fail('$caseId:\n${error.toStringDeep()}\n$diagnostics');
  }
  fail('$caseId: $error');
}

class AndroidUiCase {
  const AndroidUiCase({
    required this.id,
    required this.device,
    required this.width,
    required this.height,
    required this.pixelRatio,
    required this.theme,
    required this.fontScale,
    required this.page,
    required this.action,
    required this.description,
    this.expectedText,
  });

  factory AndroidUiCase.fromMap(Map<String, Object?> json) {
    return AndroidUiCase(
      id: json['id'] as String,
      device: json['device'] as String,
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      pixelRatio: (json['pixelRatio'] as num).toDouble(),
      theme: json['theme'] as String,
      fontScale: (json['fontScale'] as num).toDouble(),
      page: AndroidUiPage.values.byName(json['page'] as String),
      action: json['action'] as String,
      description: json['description'] as String,
      expectedText: json['expectedText'] as String?,
    );
  }

  final String id;
  final String device;
  final double width;
  final double height;
  final double pixelRatio;
  final String theme;
  final double fontScale;
  final AndroidUiPage page;
  final String action;
  final String description;
  final String? expectedText;
}

enum AndroidUiPage {
  home,
  inbox,
  calendar,
  todos,
  matters,
  knowledge,
  sync,
  settings,
}
