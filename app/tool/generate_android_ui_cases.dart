import 'dart:convert';
import 'dart:io';

void main() {
  final cases = <Map<String, Object?>>[];
  var sequence = 0;

  void add({
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
      'id': 'android_ui_${sequence.toString().padLeft(3, '0')}',
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

  for (final page in pages) {
    add(
      device: 'phone',
      width: 390,
      height: 844,
      pixelRatio: 1,
      theme: 'light',
      fontScale: 1,
      page: page.$1,
      action: 'navigate',
      expectedText: page.$2,
      description: '手机浅色进入${page.$2}页',
    );
  }
  for (final page in pages) {
    add(
      device: 'tablet',
      width: 1280,
      height: 800,
      pixelRatio: 1,
      theme: 'light',
      fontScale: 1,
      page: page.$1,
      action: 'navigate',
      expectedText: page.$2,
      description: '平板浅色进入${page.$2}页',
    );
  }
  for (final page in pages.take(6)) {
    add(
      device: 'phone',
      width: 390,
      height: 844,
      pixelRatio: 1,
      theme: 'dark',
      fontScale: 1,
      page: page.$1,
      action: 'navigate',
      expectedText: page.$2,
      description: '手机深色进入${page.$2}页',
    );
  }
  for (final page in pages.take(4)) {
    add(
      device: 'tablet',
      width: 1280,
      height: 800,
      pixelRatio: 1,
      theme: 'dark',
      fontScale: 1,
      page: page.$1,
      action: 'navigate',
      expectedText: page.$2,
      description: '平板深色进入${page.$2}页',
    );
  }

  for (final page in pages) {
    for (final scale in const [1.3, 1.5]) {
      add(
        device: 'phone',
        width: 390,
        height: 844,
        pixelRatio: 1,
        theme: 'light',
        fontScale: scale,
        page: page.$1,
        action: 'font_scale',
        expectedText: page.$2,
        description: '手机字体 ${scale}x 检查${page.$2}页',
      );
    }
  }

  for (final page in pages) {
    add(
      device: 'phone',
      width: 390,
      height: 844,
      pixelRatio: 1,
      theme: 'light',
      fontScale: 1.3,
      page: page.$1,
      action: 'vertical_swipe',
      expectedText: page.$2,
      description: '手机字体 1.3x 在${page.$2}页上下滑动',
    );
    add(
      device: 'tablet',
      width: 1280,
      height: 800,
      pixelRatio: 1,
      theme: 'light',
      fontScale: 1,
      page: page.$1,
      action: 'vertical_swipe',
      expectedText: page.$2,
      description: '平板在${page.$2}页上下滑动',
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
      device: 'phone',
      width: 390,
      height: 844,
      pixelRatio: 1,
      theme: 'light',
      fontScale: 1,
      page: page,
      action: 'horizontal_swipe',
      description: '手机在$page页横向滑动控件',
    );
  }

  for (final filter in const ['今天', '即将到期', '已完成', '全部', '今天']) {
    add(
      device: 'phone',
      width: 390,
      height: 844,
      pixelRatio: 1,
      theme: filter == '已完成' ? 'dark' : 'light',
      fontScale: filter == '今天' ? 1.3 : 1,
      page: 'todos',
      action: 'toggle_filter',
      expectedText: filter,
      description: '手机待办切换筛选：$filter',
    );
  }

  for (final page in const [
    'matters',
    'knowledge',
    'knowledge',
    'matters',
    'knowledge',
  ]) {
    final phone = cases.length < 85;
    add(
      device: phone ? 'phone' : 'tablet',
      width: phone ? 390 : 1280,
      height: phone ? 844 : 800,
      pixelRatio: 1,
      theme: page == 'matters' ? 'light' : 'dark',
      fontScale: phone ? 1.15 : 1,
      page: page,
      action: 'open_detail',
      description: '${phone ? '手机' : '平板'}打开$page详情',
    );
  }

  for (final variant in const [
    ('phone', 'light', 1.0),
    ('phone', 'dark', 1.3),
    ('tablet', 'light', 1.0),
    ('tablet', 'dark', 1.0),
    ('phone', 'light', 1.5),
  ]) {
    add(
      device: variant.$1,
      width: variant.$1 == 'phone' ? 390 : 1280,
      height: variant.$1 == 'phone' ? 844 : 800,
      pixelRatio: 1,
      theme: variant.$2,
      fontScale: variant.$3,
      page: 'home',
      action: 'capture',
      description: '${variant.$1} ${variant.$2} ${variant.$3}x 捕获并提交',
    );
  }

  for (final page in const [
    'settings',
    'settings',
    'settings',
    'sync',
    'home',
  ]) {
    add(
      device: page == 'home' ? 'tablet' : 'phone',
      width: page == 'home' ? 1280 : 390,
      height: page == 'home' ? 800 : 844,
      pixelRatio: 1,
      theme: 'light',
      fontScale: 1,
      page: page,
      action: 'theme_switch',
      description: '$page 页切换主题控件',
    );
  }

  for (final page in const [
    'home',
    'calendar',
    'todos',
    'knowledge',
    'settings',
  ]) {
    add(
      device: 'phone',
      width: 390,
      height: 844,
      pixelRatio: 1,
      theme: 'light',
      fontScale: 1.5,
      page: page,
      action: 'scroll_to_bottom',
      expectedText: page,
      description: '手机字体 1.5x 在$page页滚动到底部',
    );
  }

  for (final page in const [
    'home',
    'inbox',
    'calendar',
    'todos',
    'matters',
    'knowledge',
  ]) {
    add(
      device: page == 'knowledge' ? 'tablet' : 'phone',
      width: page == 'knowledge' ? 1280 : 390,
      height: page == 'knowledge' ? 800 : 844,
      pixelRatio: 1,
      theme: 'light',
      fontScale: 1,
      page: page,
      action: 'button_tap',
      description: '$page 页主要按钮点击检查',
    );
  }

  if (cases.length != 100) {
    throw StateError('Expected 100 cases, got ${cases.length}');
  }

  final output = const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'generatedAt': '2026-10-04T18:30:00+08:00',
    'cases': cases,
  });
  final jsonFile = File('test/fixtures/android_ui_100_cases.json');
  jsonFile.parent.createSync(recursive: true);
  jsonFile.writeAsStringSync('$output\n');

  final dartFile = File('test/android_ui_100_cases.g.dart');
  dartFile.writeAsStringSync(
    '// Generated by tool/generate_android_ui_cases.dart.\n'
    'const androidUiCaseMaps = <Map<String, Object?>>'
    '${const JsonEncoder.withIndent('  ').convert(cases)};\n',
  );
  stdout.writeln(
    'Wrote ${cases.length} cases to ${jsonFile.path} and ${dartFile.path}',
  );
}
