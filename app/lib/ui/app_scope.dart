import 'package:flutter/widgets.dart';

import '../data/home_widget_bridge.dart';
import '../modules/home_widgets/widget_workspace.dart';
import '../modules/capture/capture_workflow.dart';
import '../modules/conversation/conversation_workspace.dart';
import '../modules/results/result_library.dart';
import '../modules/settings/device_preferences.dart';
import '../modules/sync/sync_workspace.dart';
import '../modules/tables/table_library.dart';
import '../modules/tables/table_migration_gate.dart';
import '../services/file_input_service.dart';
import '../services/voice_service.dart';

class AppModules {
  const AppModules({
    this.homeWidgets,
    this.homeWidgetBridge,
    required this.results,
    required this.tables,
    required this.migrationGate,
    required this.capture,
    required this.conversations,
    required this.preferences,
    required this.sync,
    required this.fileInputService,
    required this.voiceService,
  });

  final ResultLibrary results;
  final WidgetWorkspace? homeWidgets;
  final HomeWidgetBridge? homeWidgetBridge;
  final TableLibrary tables;
  final TableMigrationGate migrationGate;
  final CaptureWorkflow capture;
  final ConversationWorkspace conversations;
  final DevicePreferences preferences;
  final SyncWorkspace sync;
  final FileInputService fileInputService;
  final VoiceService voiceService;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.modules, required super.child});

  final AppModules modules;

  static AppModules of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing from the widget tree');
    return scope!.modules;
  }

  static ResultLibrary results(BuildContext context) => of(context).results;

  static TableLibrary tables(BuildContext context) => of(context).tables;

  static TableMigrationGate migrationGate(BuildContext context) =>
      of(context).migrationGate;

  static CaptureWorkflow capture(BuildContext context) => of(context).capture;

  static ConversationWorkspace conversations(BuildContext context) =>
      of(context).conversations;

  static DevicePreferences preferences(BuildContext context) =>
      of(context).preferences;

  static SyncWorkspace sync(BuildContext context) => of(context).sync;

  static FileInputService fileInput(BuildContext context) =>
      of(context).fileInputService;

  static VoiceService voice(BuildContext context) => of(context).voiceService;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      !identical(modules, oldWidget.modules);
}
