part of '../conversation_page.dart';

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.app});

  final ChatMessage message;
  final ConversationWorkspace app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final voice = AppScope.voice(context);
    final isUser = message.isUser;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isUser
                ? constraints.maxWidth * 0.82
                : constraints.maxWidth,
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: isUser
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
                : const EdgeInsets.only(top: 8, bottom: 14),
            decoration: BoxDecoration(
              color: isUser
                  ? (theme.brightness == Brightness.dark
                        ? AppDesignTokens.darkInput
                        : AppDesignTokens.lightInput)
                  : null,
              borderRadius: isUser
                  ? BorderRadius.circular(AppDesignTokens.userMessageRadius)
                  : BorderRadius.zero,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (message.attachments.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final attachment in message.attachments)
                        _AttachmentPreview(app: app, attachment: attachment),
                    ],
                  ),
                if (message.attachments.isNotEmpty &&
                    message.content.trim().isNotEmpty)
                  const SizedBox(height: 10),
                if (message.content.trim().isNotEmpty)
                  isUser
                      ? SelectableText(
                          message.content,
                          style: theme.textTheme.bodyLarge,
                        )
                      : MarkdownBody(
                          data: message.content,
                          selectable: true,
                          styleSheet: MarkdownPresentation.styleSheet(theme),
                          builders: MarkdownPresentation.builders,
                        ),
                if (message.status == ChatMessageStatus.streaming)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (message.status == ChatMessageStatus.failed ||
                    message.status == ChatMessageStatus.interrupted) ...[
                  const SizedBox(height: 10),
                  Text(
                    message.error ?? '生成失败',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => app.retryAssistantMessage(message.id),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ),
                ],
                if (message.status == ChatMessageStatus.interrupted)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('已停止生成', style: theme.textTheme.bodySmall),
                  ),
                for (final action in message.actions) ...[
                  const SizedBox(height: 10),
                  _AutoRecordCard(action: action, app: app),
                ],
                if (!isUser &&
                    message.status == ChatMessageStatus.complete &&
                    message.content.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      key: Key('reply_copy_${message.id}'),
                      tooltip: '复制回复',
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: message.content),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('回复已复制')),
                          );
                        }
                      },
                      icon: const Icon(Icons.content_copy_outlined, size: 18),
                    ),
                  ),
                ],
                if (!isUser &&
                    message.status == ChatMessageStatus.complete &&
                    message.content.trim().isNotEmpty &&
                    voice.canSpeak) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      key: Key('reply_speech_${message.id}'),
                      tooltip: voice.isSpeaking ? '停止朗读' : '朗读回复',
                      onPressed: () async {
                        try {
                          if (voice.isSpeaking) {
                            await voice.stopSpeaking();
                          } else {
                            await voice.speak(message.content);
                          }
                        } on Object catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('系统朗读不可用：$error')),
                            );
                          }
                        }
                      },
                      icon: Icon(
                        voice.isSpeaking
                            ? Icons.stop_circle_outlined
                            : Icons.volume_up_outlined,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
