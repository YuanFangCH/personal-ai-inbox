import 'dart:async';

import 'package:flutter/material.dart';

import 'bootstrap/app_runtime.dart';
import 'ui/app_shell.dart';
import 'ui/app_scope.dart';
import 'ui/presentation/domain_presentation.dart';
import 'ui/theme/app_theme.dart';

class PersonalAiInboxApp extends StatefulWidget {
  const PersonalAiInboxApp({super.key, required this.runtime});

  final AppRuntime runtime;

  @override
  State<PersonalAiInboxApp> createState() => _PersonalAiInboxAppState();
}

class _PersonalAiInboxAppState extends State<PersonalAiInboxApp>
    with WidgetsBindingObserver {
  late final AppModules _modules;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final runtime = widget.runtime;
    _modules = AppModules(
      results: runtime.results,
      capture: runtime.capture,
      conversations: runtime.conversations,
      preferences: runtime.preferences,
      sync: runtime.sync,
      fileInputService: runtime.fileInputService,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(widget.runtime.shutdown());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.runtime.shutdown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      modules: _modules,
      child: AnimatedBuilder(
        animation: widget.runtime.preferences,
        builder: (context, _) {
          final themeMode = materialThemeMode(
            widget.runtime.preferences.settings.themeMode,
          );
          return MaterialApp(
            title: '懒狗秘书',
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
