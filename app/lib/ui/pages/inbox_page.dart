import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/chat_models.dart';
import '../../services/app_controller.dart';
import '../app_scope.dart';
import '../widgets/capture_sheet.dart';
import '../widgets/common.dart';
import '../widgets/review_queue.dart';
import 'conversation_page.dart';
import 'document_detail_page.dart';

class InboxPage extends StatelessWidget {
  const InboxPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final reviews = app.reviewCaptures;
    final drafts = app.draftDocuments;
    final conflicts = app.conflictFiles;
    final pending = reviews.length + conflicts.length;
    return PageFrame(
      title: '收件箱',
      subtitle: pending == 0
          ? '${app.conversations.length} 个会话 · ${drafts.length} 条草稿'
          : '$pending 条待确认 · ${drafts.length} 条草稿 · '
                '${app.conversations.length} 个会话',
      actions: [
        FilledButton.icon(
          key: const Key('inbox_new_conversation'),
          onPressed: () => _newConversation(context),
          icon: const Icon(Icons.add_comment_outlined),
          label: const Text('新对话'),
        ),
        OutlinedButton.icon(
          onPressed: () => showCaptureSheet(context),
          icon: const Icon(Icons.inbox_outlined),
          label: const Text('收下内容'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ReviewQueue(),
          if (drafts.isNotEmpty) ...[
            const SectionHeading(title: '草稿'),
            const SizedBox(height: 8),
            SurfacePanel(
              child: Column(
                children: [
                  for (var index = 0; index < drafts.length; index++) ...[
                    DocumentListTile(
                      document: drafts[index],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              DocumentDetailPage(documentId: drafts[index].id),
                        ),
                      ),
                    ),
                    if (index != drafts.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          const SectionHeading(title: '对话'),
          const SizedBox(height: 8),
          SurfacePanel(
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < app.conversations.length;
                  index++
                ) ...[
                  _ConversationTile(
                    conversation: app.conversations[index],
                    app: app,
                  ),
                  if (index != app.conversations.length - 1)
                    const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _newConversation(BuildContext context) async {
    await openNewConversationPage(context);
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.app});

  final Conversation conversation;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: Key('conversation_${conversation.id}'),
      onTap: () => openConversationPage(context, conversation.id),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.forum_outlined,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    conversation.preview.isEmpty
                        ? '尚未发送消息'
                        : conversation.preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _formatTime(conversation.updatedAt),
              style: theme.textTheme.bodySmall,
            ),
            PopupMenuButton<String>(
              tooltip: '会话操作',
              onSelected: (value) {
                if (value == 'rename') {
                  _rename(context);
                } else if (value == 'delete') {
                  _delete(context);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('重命名')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: conversation.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title != null && title.isNotEmpty) {
      await app.renameConversation(conversation.id, title);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话'),
        content: const Text('会话和本地图片会被删除，已自动创建的成果不会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await app.deleteConversation(conversation.id);
    }
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return DateFormat('HH:mm').format(date);
    }
    return DateFormat('MM-dd').format(date);
  }
}
