import '../modules/capture/capture_workflow.dart';
import '../modules/conversation/conversation_workspace.dart';
import '../modules/results/result_library.dart';
import '../modules/settings/device_preferences.dart';
import '../modules/sync/sync_workspace.dart';

/// Composition root for the local core.
///
/// The runtime only wires modules and controls their lifecycle. Business
/// commands remain on the owning module interface.
final class AppRuntime {
  const AppRuntime({
    required this.preferences,
    required this.results,
    required this.capture,
    required this.conversations,
    required this.sync,
  });

  final DevicePreferences preferences;
  final ResultLibrary results;
  final CaptureWorkflow capture;
  final ConversationWorkspace conversations;
  final SyncWorkspace sync;

  Future<void> initialize() async {
    await preferences.initialize();
    await results.initialize();
    await capture.initialize();
    await conversations.initialize();
    await sync.initialize();
  }

  Future<void> refresh() async {
    await preferences.initialize();
    await results.refresh();
    await capture.refresh();
    await conversations.refresh();
    await sync.refresh();
  }

  void dispose() {
    conversations.dispose();
    sync.dispose();
    capture.dispose();
    results.dispose();
    preferences.dispose();
  }
}
