import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../core/chat_models.dart';
import '../../services/app_controller.dart';
import '../../services/image_input_service.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'document_detail_page.dart';

Future<void> openConversationPage(BuildContext context, String conversationId) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ConversationPage(conversationId: conversationId),
    ),
  );
}

Future<void> openNewConversationPage(BuildContext context) {
  return Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const ConversationPage()));
}

class ConversationPage extends StatefulWidget {
  const ConversationPage({super.key, this.conversationId});

  final String? conversationId;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _imageInputs = <ChatAttachmentInput>[];
  final _imagePicker = ImageInputService();
  bool _sending = false;
  int _lastMessageCount = -1;
  String? _conversationId;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _conversationId != null) {
        AppScope.of(context).openConversation(_conversationId!);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final conversationId = _conversationId;
    final conversation = conversationId == null
        ? null
        : app.findConversation(conversationId);
    if (conversationId != null && conversation == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('会话不存在或已删除')),
      );
    }
    final messages = conversationId == null
        ? const <ChatMessage>[]
        : app.messagesFor(conversationId);
    if (messages.length != _lastMessageCount) {
      _lastMessageCount = messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    if (app.isChatGenerating) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    final modelReady = app.settings?.hasModelKey ?? false;
    final imageEgressAllowed = app.settings?.allowImageEgress ?? true;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          conversation?.title ?? '新对话',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key: const Key('conversation_new'),
            tooltip: '新对话',
            onPressed: _newConversation,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          if (conversation != null)
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (value) {
                if (value == 'rename') {
                  _renameConversation(conversation);
                } else if (value == 'delete') {
                  _deleteConversation(conversation);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('重命名')),
                PopupMenuItem(value: 'delete', child: Text('删除会话')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: messages.isEmpty
                    ? const EmptyState(
                        icon: Icons.forum_outlined,
                        title: '开始记录',
                        message: '发送文字、粘贴内容或选择图片。',
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                        itemCount: messages.length,
                        itemBuilder: (context, index) =>
                            _MessageBubble(message: messages[index], app: app),
                      ),
              ),
            ),
          ),
          _Composer(
            controller: _textController,
            attachments: _imageInputs,
            enabled: modelReady,
            imageEnabled: modelReady && imageEgressAllowed,
            generating: app.isChatGenerating,
            onPickGallery: _pickGallery,
            onPickCamera: _pickCamera,
            onPaste: _pasteText,
            onRemoveImage: (index) =>
                setState(() => _imageInputs.removeAt(index)),
            onSend: _send,
            onStop: app.cancelChatGeneration,
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final app = AppScope.of(context);
    final text = _textController.text;
    if ((text.trim().isEmpty && _imageInputs.isEmpty) ||
        app.isChatGenerating ||
        _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      final attachments = List<ChatAttachmentInput>.from(_imageInputs);
      var conversationId = _conversationId;
      if (conversationId == null) {
        final conversation = await app.createConversation();
        conversationId = conversation.id;
        if (mounted) {
          setState(() => _conversationId = conversationId);
        }
      }
      if (mounted) {
        _textController.clear();
        setState(() => _imageInputs.clear());
      }
      await app.sendChatMessage(
        conversationId,
        text: text,
        attachments: attachments,
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _pickGallery() async {
    final remaining =
        ImageInputService.maxImagesPerMessage - _imageInputs.length;
    if (remaining <= 0) {
      return;
    }
    final values = await _imagePicker.pickFromGallery(limit: remaining);
    if (!mounted || values.isEmpty) {
      return;
    }
    setState(() => _imageInputs.addAll(values));
  }

  Future<void> _pickCamera() async {
    if (_imageInputs.length >= ImageInputService.maxImagesPerMessage) {
      return;
    }
    final values = await _imagePicker.pickFromCamera();
    if (!mounted || values.isEmpty) {
      return;
    }
    setState(() => _imageInputs.addAll(values));
  }

  Future<void> _pasteText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    final selection = _textController.selection;
    final current = _textController.text;
    final start = selection.isValid ? selection.start : current.length;
    final end = selection.isValid ? selection.end : current.length;
    final updated = current.replaceRange(start, end, text);
    _textController
      ..text = updated
      ..selection = TextSelection.collapsed(offset: start + text.length);
  }

  Future<void> _newConversation() async {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const ConversationPage()),
    );
  }

  Future<void> _renameConversation(Conversation conversation) async {
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
    if (title != null && title.isNotEmpty && mounted) {
      await AppScope.of(context).renameConversation(conversation.id, title);
    }
  }

  Future<void> _deleteConversation(Conversation conversation) async {
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
    if (confirmed != true || !mounted) {
      return;
    }
    await AppScope.of(context).deleteConversation(conversation.id);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }
}

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

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.app, required this.attachment});

  final AppController app;
  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: app.readAttachment(attachment),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return const SizedBox.square(
            dimension: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            width: 180,
            height: 160,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }
}

class _AutoRecordCard extends StatelessWidget {
  const _AutoRecordCard({required this.action, required this.app});

  final AutoRecordAction action;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = switch (action.status) {
      AutoRecordStatus.created => StatusTone.positive,
      AutoRecordStatus.undone => StatusTone.neutral,
      AutoRecordStatus.review => StatusTone.warning,
      AutoRecordStatus.skipped => StatusTone.danger,
    };
    final label = switch (action.status) {
      AutoRecordStatus.created => '已自动创建',
      AutoRecordStatus.undone => '已撤销',
      AutoRecordStatus.review => '待人工确认',
      AutoRecordStatus.skipped => '未创建',
    };
    return SurfacePanel(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Icon(action.type.icon, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    StatusPill(label: label, tone: tone),
                    if (action.reason != null)
                      Text(action.reason!, style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
          if (action.status == AutoRecordStatus.created &&
              action.resultId != null)
            IconButton(
              tooltip: '打开成果',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      DocumentDetailPage(documentId: action.resultId!),
                ),
              ),
              icon: const Icon(Icons.open_in_new),
            ),
          if (action.canUndo)
            TextButton(
              onPressed: () => app.undoAutoRecord(action.id),
              child: const Text('撤销'),
            ),
        ],
      ),
    );
  }
}
