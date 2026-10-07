part of '../conversation_page.dart';

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.app});

  final ChatMessage message;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primaryContainer
              : theme.brightness == Brightness.dark
              ? const Color(0xFF182125)
              : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isUser
                ? theme.colorScheme.primary.withValues(alpha: 0.25)
                : theme.dividerColor,
          ),
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
                  ? SelectableText(message.content)
                  : MarkdownBody(data: message.content, selectable: true),
            if (message.status == ChatMessageStatus.streaming)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (message.status == ChatMessageStatus.failed) ...[
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
          ],
        ),
      ),
    );
  }
}
