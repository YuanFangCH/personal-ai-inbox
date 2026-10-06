import 'package:flutter/material.dart';

import 'app.dart';
import 'data/share_bridge.dart';
import 'services/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await AppController.bootstrap();
  await initializeShareBridge((payload) async {
    await controller.handleSharedPayload(payload);
  });
  runApp(PersonalAiInboxApp(controller: controller));
}
