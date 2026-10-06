import 'dart:convert';
import 'dart:io';

void main() {
  final cases = <Map<String, Object?>>[];
  var sequence = 0;

  void add({
    required String target,
    required String device,
    required double width,
    required double height,
    required double pixelRatio,
    required String theme,
    required double fontScale,
    required String page,
    required String action,
    required String description,
    String? expectedText,
  }) {
    sequence++;
    cases.add({
      'id': 'device_acceptance_${sequence.toString().padLeft(3, '0')}',
      'target': target,
      'device': device,
      'width': width,
      'height': height,
      'pixelRatio': pixelRatio,
      'theme': theme,
      'fontScale': fontScale,
      'page': page,
      'action': action,
      'expectedText': expectedText,
      'description': description,
    });
  }

  const pages = [
    ('home', '首页'),
    ('inbox', '收件箱'),
    ('calendar', '日历'),
    ('todos', '待办'),
    ('matters', '事项'),
    ('knowledge', '知识'),
    ('review', '确认'),
    ('sync', '同步'),
    ('settings', '设置'),
  ];

  void addTargetCases({
    required String target,
    required String device,
    required String hardware,
    required double width,
    required double height,
    required double pixelRatio,
  }) {
    for (final page in pages) {
      add(
        target: target,
        device: device,
        width: width,
        height: height,
        pixelRatio: pixelRatio,
        theme: 'light',
        fontScale: 1,
        page: page.$1,
        action: 'navigate',
        expectedText: page.$2,
        description: '$hardware 进入${page.$2}页',
      );
    }

    for (final scale in const [1.15, 1.3, 1.5]) {
      for (final page in const ['home', 'inbox', 'calendar', 'todos']) {
        add(
          target: target,
          device: device,
          width: width,
          height: height,
          pixelRatio: pixelRatio,
          theme: 'light',
          fontScale: scale,
          page: page,
          action: 'font_scale',
          description: '$hardware 字体 ${scale}x 检查 $page 页',
        );
      }
    }

    for (final page in const [
      'home',
      'inbox',
      'calendar',
      'todos',
      'review',
      'settings',
    ]) {
      add(
        target: target,
        device: device,
        width: width,
        height: height,
        pixelRatio: pixelRatio,
        theme: 'light',
        fontScale: 1,
        page: page,
        action: 'vertical_swipe',
        description: '$hardware 在 $page 页上下滑动',
      );
    }

    for (final page in const [
      'calendar',
      'todos',
      'matters',
      'knowledge',
      'settings',
    ]) {
      add(
        target: target,
        device: device,
        width: width,
        height: height,
        pixelRatio: pixelRatio,
        theme: 'light',
        fontScale: 1,
        page: page,
        action: 'horizontal_swipe',
        description: '$hardware 在 $page 页横向滚动控件',
      );
    }

    for (final filter in const ['全部', '今天', '即将到期', '已完成']) {
      add(
        target: target,
        device: device,
        width: width,
        height: height,
        pixelRatio: pixelRatio,
        theme: filter == '已完成' ? 'dark' : 'light',
        fontScale: 1,
        page: 'todos',
        action: 'toggle_filter',
        expectedText: filter,
        description: '$hardware 切换待办筛选：$filter',
      );
    }

    for (final page in const ['matters', 'knowledge', 'knowledge']) {
      add(
        target: target,
        device: device,
        width: width,
        height: height,
        pixelRatio: pixelRatio,
        theme: page == 'knowledge' ? 'dark' : 'light',
        fontScale: 1,
        page: page,
        action: 'open_detail',
        description: '$hardware 打开 $page 详情',
      );
    }

    for (final variant in const [
      ('light', 1.0),
      ('dark', 1.3),
      ('light', 1.5),
    ]) {
      add(
        target: target,
        device: device,
        width: width,
        height: height,
        pixelRatio: pixelRatio,
        theme: variant.$1,
        fontScale: variant.$2,
        page: 'home',
        action: 'capture',
        description: '$hardware ${variant.$1} ${variant.$2}x 捕获并提交',
      );
    }

    for (final page in const ['settings', 'sync', 'home']) {
      add(
        target: target,
        device: device,
        width: width,
        height: height,
        pixelRatio: pixelRatio,
        theme: page == 'sync' ? 'dark' : 'light',
        fontScale: 1,
        page: page,
        action: 'theme_switch',
        description: '$hardware 在 $page 页切换主题',
      );
    }

    for (final page in const ['knowledge', 'settings']) {
      add(
        target: target,
        device: device,
        width: width,
        height: height,
        pixelRatio: pixelRatio,
        theme: 'light',
        fontScale: 1.5,
        page: page,
        action: 'scroll_to_bottom',
        expectedText: page,
        description: '$hardware 字体 1.5x 在 $page 页滚动到底部',
      );
    }

    for (final page in const ['home', 'calendar', 'todos']) {
      add(
        target: target,
        device: device,
        width: width,
        height: height,
        pixelRatio: pixelRatio,
        theme: 'light',
        fontScale: 1,
        page: page,
        action: 'button_tap',
        description: '$hardware 点击 $page 页主要按钮',
      );
    }
  }

  addTargetCases(
    target: 'honor-phone',
    device: 'phone',
    hardware: '荣耀手机',
    width: 390,
    height: 844,
    pixelRatio: 1,
  );
  addTargetCases(
    target: 'galaxy-tab',
    device: 'tablet',
    hardware: '三星 Galaxy Tab',
    width: 1280,
    height: 800,
    pixelRatio: 1,
  );

  if (cases.length != 100) {
    throw StateError('Expected 100 cases, got ${cases.length}');
  }
  for (final target in const ['honor-phone', 'galaxy-tab']) {
    final count = cases.where((item) => item['target'] == target).length;
    if (count != 50) {
      throw StateError('Expected 50 $target cases, got $count');
    }
  }

  final output = const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'generatedAt': '2026-10-04T21:00:00+08:00',
    'cases': cases,
  });
  final jsonFile = File('test/fixtures/device_acceptance_100_cases.json');
  jsonFile.parent.createSync(recursive: true);
  jsonFile.writeAsStringSync('$output\n');

  final dartFile = File('test/device_acceptance_100_cases.g.dart');
  dartFile.writeAsStringSync(
    '// Generated by tool/generate_device_acceptance_cases.dart.\n'
    'const deviceAcceptanceCaseMaps = <Map<String, Object?>>'
    '${const JsonEncoder.withIndent('  ').convert(cases)};\n',
  );
  stdout.writeln(
    'Wrote ${cases.length} cases to ${jsonFile.path} and ${dartFile.path}',
  );
}
