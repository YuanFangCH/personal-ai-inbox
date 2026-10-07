import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../core/chat_models.dart';
import '../../services/app_controller.dart';
import '../../services/image_input_service.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'document_detail_page.dart';

part 'conversation/attachment_preview.dart';
part 'conversation/auto_record_card.dart';
part 'conversation/composer.dart';
part 'conversation/message_bubble.dart';
part 'conversation/page_actions.dart';

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

class _ConversationPageState extends State<ConversationPage>
    with _ConversationPageActions {
  @override
  void initState() {
    super.initState();
    _initializeConversationPage();
  }

  @override
  void dispose() {
    _disposeConversationPage();
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
}
