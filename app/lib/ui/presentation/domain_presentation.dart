import 'package:flutter/material.dart';

import '../../core/models.dart';

String resultTypeLabel(ResultType type) => switch (type) {
  ResultType.matter => '事项',
  ResultType.todo => '待办',
  ResultType.event => '事件',
  ResultType.knowledge => '知识',
};

IconData resultTypeIcon(ResultType type) => switch (type) {
  ResultType.matter => Icons.account_tree_outlined,
  ResultType.todo => Icons.check_circle_outline,
  ResultType.event => Icons.event_outlined,
  ResultType.knowledge => Icons.menu_book_outlined,
};

String resultStatusLabel(ResultStatus status) => switch (status) {
  ResultStatus.draft => '草稿',
  ResultStatus.reviewed => '已复核',
  ResultStatus.canonical => '定稿',
};

ThemeMode materialThemeMode(ThemePreference preference) => switch (preference) {
  ThemePreference.system => ThemeMode.system,
  ThemePreference.light => ThemeMode.light,
  ThemePreference.dark => ThemeMode.dark,
};

ThemePreference themePreference(ThemeMode mode) => switch (mode) {
  ThemeMode.system => ThemePreference.system,
  ThemeMode.light => ThemePreference.light,
  ThemeMode.dark => ThemePreference.dark,
};
