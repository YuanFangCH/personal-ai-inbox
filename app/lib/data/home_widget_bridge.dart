import 'dart:async';

import 'package:flutter/services.dart';

import '../modules/home_widgets/home_widget_contract.dart';

final class HomeWidgetBridge {
  HomeWidgetBridge() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openTargetAvailable') _targets.add(null);
    });
  }

  static const _channel = MethodChannel(
    'com.yuanfang.aitext.personal_ai_inbox/home_widgets',
  );
  final _targets = StreamController<void>.broadcast();
  Stream<void> get openTargets => _targets.stream;

  Future<String> getStoreDirectory() async =>
      (await _channel.invokeMethod<String>('getStoreDirectory'))!;

  Future<WidgetPublishResult> publishSnapshots(String json) async {
    final result = (await _channel.invokeMapMethod<String, int>(
      'publishSnapshots',
      {'snapshot_json': json},
    ))!;
    return WidgetPublishResult(
      status: result['failed_count']! > 0
          ? WidgetPublishStatus.pending
          : WidgetPublishStatus.published,
      submittedCount: result['submitted_count']!,
      failedCount: result['failed_count']!,
    );
  }

  Future<void> clearSnapshots() =>
      _channel.invokeMethod<void>('clearSnapshots');

  Future<String> requestPin(String cardId) async {
    try {
      return await _channel.invokeMethod<String>('requestPin', {
            'card_id': cardId,
          }) ??
          'failed';
    } on PlatformException {
      return 'failed';
    }
  }

  Future<Map<String, Object?>?> takeOpenTarget() =>
      _channel.invokeMapMethod<String, Object?>('takeOpenTarget');

  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_targets.close());
  }
}
