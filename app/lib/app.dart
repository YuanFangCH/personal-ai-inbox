import 'package:flutter/material.dart';

import 'services/app_controller.dart';
import 'ui/app_shell.dart';
import 'ui/app_scope.dart';
import 'ui/theme/app_theme.dart';

class PersonalAiInboxApp extends StatelessWidget {
  const PersonalAiInboxApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final themeMode = controller.settings?.themeMode ?? ThemeMode.system;
          return MaterialApp(
            title: '个人 AI 收件箱',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeMode,
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
