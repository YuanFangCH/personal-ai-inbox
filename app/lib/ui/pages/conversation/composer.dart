part of '../conversation_page.dart';

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.attachments,
    required this.enabled,
    required this.imageEnabled,
    required this.generating,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onPaste,
    required this.onRemoveImage,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final List<ChatAttachmentInput> attachments;
  final bool enabled;
  final bool imageEnabled;
  final bool generating;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onPaste;
  final ValueChanged<int> onRemoveImage;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!enabled)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '请先在设置中配置云端模型 API Key',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  if (attachments.isNotEmpty)
                    SizedBox(
                      height: 76,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: attachments.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final attachment = attachments[index];
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  attachment.bytes,
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: IconButton.filledTonal(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: '移除图片',
                                  onPressed: () => onRemoveImage(index),
                                  icon: const Icon(Icons.close, size: 16),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        key: const Key('chat_gallery'),
                        tooltip: '选择图片',
                        onPressed: imageEnabled ? onPickGallery : null,
                        icon: const Icon(Icons.photo_library_outlined),
                      ),
                      IconButton(
                        key: const Key('chat_camera'),
                        tooltip: '拍照',
                        onPressed: imageEnabled ? onPickCamera : null,
                        icon: const Icon(Icons.photo_camera_outlined),
                      ),
                      IconButton(
                        key: const Key('chat_paste'),
                        tooltip: '粘贴文本',
                        onPressed: enabled ? onPaste : null,
                        icon: const Icon(Icons.content_paste_outlined),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          key: const Key('chat_input'),
                          controller: controller,
                          enabled: enabled,
                          minLines: 1,
                          maxLines: 6,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(hintText: '输入消息'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        key: const Key('chat_send'),
                        tooltip: generating ? '停止生成' : '发送',
                        onPressed: enabled
                            ? generating
                                  ? onStop
                                  : onSend
                            : null,
                        icon: Icon(
                          generating ? Icons.stop : Icons.arrow_upward,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
