import 'package:flutter/widgets.dart';

import '../modules/capture/capture_workflow.dart';
import '../modules/conversation/conversation_workspace.dart';
import '../modules/results/result_library.dart';
import '../modules/settings/device_preferences.dart';
import '../modules/sync/sync_workspace.dart';
import '../services/file_input_service.dart';

class AppModules {
  const AppModules({
    required this.results,
    required this.capture,
    required this.conversations,
    required this.preferences,
    required this.sync,
    required this.fileInputService,
  });

  final ResultLibrary results;
  final CaptureWorkflow capture;
  final ConversationWorkspace conversations;
  final DevicePreferences preferences;
  final SyncWorkspace sync;
  final FileInputService fileInputService;
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

  static CaptureWorkflow capture(BuildContext context) => of(context).capture;

  static ConversationWorkspace conversations(BuildContext context) =>
      of(context).conversations;

  static DevicePreferences preferences(BuildContext context) =>
      of(context).preferences;

  static SyncWorkspace sync(BuildContext context) => of(context).sync;

  static FileInputService fileInput(BuildContext context) =>
      of(context).fileInputService;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      !identical(modules, oldWidget.modules);
}
