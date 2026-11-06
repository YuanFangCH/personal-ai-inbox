import 'dart:async';

import 'package:flutter/material.dart';

import 'bootstrap/app_runtime.dart';
import 'services/agent_background_service.dart';
import 'ui/app_shell.dart';
import 'ui/app_scope.dart';
import 'ui/presentation/domain_presentation.dart';
import 'ui/theme/app_theme.dart';

final Expando<AgentBackgroundLifecycleGate> _runtimeShutdownGates =
    Expando<AgentBackgroundLifecycleGate>('runtime shutdown gate');

class PersonalAiInboxApp extends StatefulWidget {
  const PersonalAiInboxApp({
    super.key,
    required this.runtime,
    this.backgroundAgent,
  });

  final AppRuntime runtime;
  final AgentBackgroundPort? backgroundAgent;

  @override
  State<PersonalAiInboxApp> createState() => _PersonalAiInboxAppState();
}

class _PersonalAiInboxAppState extends State<PersonalAiInboxApp>
    with WidgetsBindingObserver {
  late final AppModules _modules;
  late final AgentBackgroundPort _backgroundAgent;
  late final AgentBackgroundLifecycleGate _shutdownGate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _backgroundAgent =
        widget.backgroundAgent ?? AgentBackgroundService.instance;
    _shutdownGate = _runtimeShutdownGates[widget.runtime] ??=
        AgentBackgroundLifecycleGate(
          backgroundAgent: _backgroundAgent,
          shutdownRuntime: widget.runtime.shutdown,
        );
    unawaited(_backgroundAgent.initialize());
    final runtime = widget.runtime;
    _modules = AppModules(
      results: runtime.results,
      tables: runtime.tables,
      migrationGate: runtime.migrationGate,
      capture: runtime.capture,
      conversations: runtime.conversations,
      preferences: runtime.preferences,
      sync: runtime.sync,
      fileInputService: runtime.fileInputService,
      voiceService: runtime.voiceService,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.detached:
        _scheduleShutdownAfterBackgroundTask();
      case AppLifecycleState.resumed:
        _shutdownGate.cancelShutdown();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scheduleShutdownAfterBackgroundTask();
    super.dispose();
  }

  void _scheduleShutdownAfterBackgroundTask() {
    unawaited(_shutdownGate.scheduleShutdown());
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
