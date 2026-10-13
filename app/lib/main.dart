import 'package:flutter/material.dart';

import 'app.dart';
import 'bootstrap/app_runtime.dart';
import 'data/share_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = await AppRuntime.bootstrap();
  await initializeShareBridge((payload) async {
    await runtime.conversations.handleSharedPayload(payload);
  });
  runApp(PersonalAiInboxApp(runtime: runtime));
}
