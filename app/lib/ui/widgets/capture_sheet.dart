import 'package:flutter/material.dart';

import '../../modules/capture/capture_workflow.dart';
import '../app_scope.dart';
import '../presentation/domain_presentation.dart';
import 'common.dart';

Future<void> showCaptureSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: reducedMotionAnimationStyle(context),
    builder: (context) => const _CaptureSheet(),
  );
}

class _CaptureSheet extends StatefulWidget {
  const _CaptureSheet();

  @override
  State<_CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends State<_CaptureSheet> {
  final _controller = TextEditingController();
  bool _preferModel = true;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modelAvailable = AppScope.preferences(context).settings.hasModelKey;
    return AnimatedPadding(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '收下内容',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '文本、链接和随手记会先保存在本端。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('capture_text_field'),
                controller: _controller,
                autofocus: true,
                minLines: 5,
                maxLines: 10,
                scrollPadding: const EdgeInsets.only(bottom: 180),
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '例如：明天下午三点提醒我交材料',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _preferModel && modelAvailable,
                onChanged: modelAvailable
                    ? (value) => setState(() => _preferModel = value)
                    : null,
                title: const Text('使用云端模型整理'),
                subtitle: Text(modelAvailable ? '失败时自动退回本地规则' : '当前未配置模型密钥'),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('capture_submit'),
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.inbox),
                    label: const Text('收下'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await AppScope.capture(context)
          .captureText(text, preferModel: _preferModel);
      if (!mounted) {
        return;
      }
      final message = switch (result.status) {
        CaptureOutcomeStatus.created =>
          '已生成${resultTypeLabel(result.document!.type)}：${result.document!.title}',
        CaptureOutcomeStatus.review => '已进入确认队列',
        CaptureOutcomeStatus.failure => result.message ?? '捕获失败',
      };
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.warning == null ? message : '$message（${result.warning}）',
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
