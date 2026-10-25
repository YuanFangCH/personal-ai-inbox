part of '../conversation_page.dart';

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.attachments,
    required this.enabled,
    required this.desktopInput,
    required this.imageEnabled,
    required this.files,
    required this.thinkingAvailable,
    required this.thinkingEnabled,
    required this.webSearchAvailable,
    required this.onThinkingChanged,
    required this.attachmentTrayOpen,
    required this.onToggleAttachmentTray,
    required this.onInputFocused,
    required this.voiceService,
    required this.onVoiceInput,
    required this.generating,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onPaste,
    required this.onRemoveImage,
    required this.onPickFile,
    required this.onRemoveFile,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<ChatAttachmentInput> attachments;
  final bool enabled;
  final bool desktopInput;
  final bool imageEnabled;
  final List<ExtractedFileText> files;
  final bool thinkingAvailable;
  final bool thinkingEnabled;
  final bool webSearchAvailable;
  final ValueChanged<bool> onThinkingChanged;
  final bool attachmentTrayOpen;
  final VoidCallback onToggleAttachmentTray;
  final VoidCallback onInputFocused;
  final VoiceService voiceService;
  final VoidCallback onVoiceInput;
  final bool generating;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onPaste;
  final ValueChanged<int> onRemoveImage;
  final VoidCallback onPickFile;
  final ValueChanged<int> onRemoveFile;
  final VoidCallback onSend;
  final VoidCallback onStop;

  bool get _isComposing {
    final range = controller.value.composing;
    return range.isValid && !range.isCollapsed;
  }

  void _submitFromKeyboard() {
    if (!enabled || generating || _isComposing) return;
    onSend();
  }

  void _insertNewline() {
    if (!enabled || _isComposing) return;
    final value = controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    controller.value = TextEditingValue(
      text: value.text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  Widget _textInput() {
    final input = TextField(
      key: const Key('chat_input'),
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      onTap: onInputFocused,
      minLines: 1,
      maxLines: 6,
      textInputAction: desktopInput
          ? TextInputAction.send
          : TextInputAction.newline,
      // Keep the composition range and focus until the submit guard has run.
      onEditingComplete: desktopInput ? () {} : null,
      onSubmitted: desktopInput ? (_) => _submitFromKeyboard() : null,
      decoration: const InputDecoration(
        hintText: '发消息给懒狗秘书',
        filled: false,
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: 8),
      ),
    );
    if (!desktopInput) return input;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _submitFromKeyboard,
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            _submitFromKeyboard,
        const SingleActivator(LogicalKeyboardKey.enter, shift: true):
            _insertNewline,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, shift: true):
            _insertNewline,
      },
      child: input,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppDesignTokens.conversationContentMaxWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(
                  AppDesignTokens.composerRadius,
                ),
                border: Border.all(color: theme.dividerColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!enabled)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '请先在设置中配置云端模型 API Key',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    if (attachments.isNotEmpty) ...[
                      SizedBox(
                        height: 72,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: attachments.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final attachment = attachments[index];
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    attachment.bytes,
                                    width: 68,
                                    height: 68,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton.filledTonal(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: '移除附件',
                                    onPressed: () => onRemoveImage(index),
                                    icon: const Icon(Icons.close, size: 16),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (files.isNotEmpty) ...[
                      SizedBox(
                        height: 48,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: files.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final file = files[index];
                            return InputChip(
                              key: Key('chat_file_${file.fileName}'),
                              avatar: const Icon(Icons.description_outlined),
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 190,
                                ),
                                child: Text(
                                  '${file.fileName}${file.truncated ? ' · 已截取' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              onDeleted: () => onRemoveFile(index),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    _textInput(),
                    Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _ComposerCapabilityChip(
                                  icon: Icons.blur_on_outlined,
                                  label: '深度思考',
                                  enabled: thinkingAvailable,
                                  selected: thinkingEnabled,
                                  tooltip: '当前模型端点暂不支持此能力',
                                  onSelected: onThinkingChanged,
                                ),
                                const SizedBox(width: 6),
                                _ComposerCapabilityChip(
                                  icon: Icons.public,
                                  label: '智能搜索',
                                  enabled: webSearchAvailable,
                                  selected: false,
                                  tooltip: '当前模型接口未声明内置联网搜索能力',
                                  onSelected: null,
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          key: const Key('chat_attachment_menu'),
                          tooltip: attachmentTrayOpen ? '关闭附件菜单' : '添加附件',
                          onPressed: enabled ? onToggleAttachmentTray : null,
                          icon: Icon(
                            attachmentTrayOpen
                                ? Icons.close
                                : Icons.add_circle_outline,
                          ),
                        ),
                        IconButton(
                          key: const Key('chat_voice_input'),
                          tooltip: voiceService.isListening
                              ? '结束语音输入'
                              : '离线语音转文字',
                          onPressed: enabled && voiceService.canTrySpeechInput
                              ? onVoiceInput
                              : null,
                          icon: Icon(
                            voiceService.isListening
                                ? Icons.mic
                                : Icons.mic_none_outlined,
                          ),
                        ),
                        const SizedBox(width: 2),
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
                    AnimatedSize(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : AppDesignTokens.contentTransition,
                      curve: Curves.easeInOut,
                      alignment: Alignment.topCenter,
                      child: attachmentTrayOpen
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _AttachmentMenuButton(
                                          icon: Icons.photo_camera_outlined,
                                          label: '拍照',
                                          onPressed: imageEnabled
                                              ? onPickCamera
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _AttachmentMenuButton(
                                          icon: Icons.photo_library_outlined,
                                          label: '相册',
                                          onPressed: imageEnabled
                                              ? onPickGallery
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _AttachmentMenuButton(
                                          icon: Icons.attach_file,
                                          label: '文件',
                                          onPressed: enabled
                                              ? onPickFile
                                              : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: enabled ? onPaste : null,
                                      icon: const Icon(
                                        Icons.content_paste_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('粘贴文字'),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final media = MediaQuery.of(context);
    final availableHeight =
        (media.size.height -
                media.viewInsets.bottom -
                media.padding.vertical -
                kToolbarHeight)
            .clamp(0.0, double.infinity)
            .toDouble();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: availableHeight),
      child: SingleChildScrollView(
        key: const Key('conversation_composer_scroll'),
        reverse: true,
        child: content,
      ),
    );
  }
}

class _ComposerCapabilityChip extends StatelessWidget {
  const _ComposerCapabilityChip({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.selected,
    required this.tooltip,
    this.onSelected,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final bool selected;
  final String tooltip;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: FilterChip(
      avatar: Icon(icon, size: 17),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: enabled ? onSelected : null,
      visualDensity: VisualDensity.compact,
    ),
  );
}

class _AttachmentMenuButton extends StatelessWidget {
  const _AttachmentMenuButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(AppDesignTokens.controlRadius),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppDesignTokens.controlRadius),
      child: SizedBox(
        height: 84,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    ),
  );
}
