import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';

import '../../core/chat_models.dart';
import '../../core/models.dart';
import '../../modules/conversation/conversation_workspace.dart';
import '../../services/file_input_service.dart';
import '../../services/image_input_service.dart';
import '../../services/model_capabilities.dart';
import '../../services/voice_service.dart';
import '../app_scope.dart';
import '../presentation/domain_presentation.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/common.dart';
import 'document_detail_page.dart';
import 'global_knowledge_page.dart';
import 'pending_page.dart';
import '../widgets/global_knowledge_candidate_card.dart';

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
  const ConversationPage({super.key, this.conversationId, this.isRoot = false});

  final String? conversationId;
  final bool isRoot;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage>
    with _ConversationPageActions {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _conversationWorkspaceForCleanup = AppScope.conversations(context);
    if (!_temporaryPermissionsInitialized) {
      _temporaryPermissions = AppScope.preferences(context)
          .settings
          .defaultAiPermissions;
      _temporaryPermissionsInitialized = true;
    }
  }

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
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppScope.conversations(context),
        AppScope.preferences(context),
        AppScope.results(context),
        AppScope.capture(context),
        AppScope.sync(context),
        AppScope.voice(context),
      ]),
      builder: (context, _) => _buildConversation(context),
    );
  }

  Widget _buildConversation(BuildContext context) {
    final app = AppScope.conversations(context);
    final settings = AppScope.preferences(context).settings;
    final results = AppScope.results(context);
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
    final modelReady = settings.hasModelKey;
    final imageEgressAllowed = settings.allowImageEgress;
    final modelCapabilities = ModelCapabilities.resolve(settings);
    final imageCapability = modelCapabilities.vision;
    final activeCandidates = results.globalKnowledgeCandidates
        .where(
          (candidate) =>
              candidate.sourceConversationId == conversationId &&
              candidate.status != GlobalKnowledgeCandidateStatus.rejected,
        )
        .toList(growable: false);
    final body = Column(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: messages.isEmpty && activeCandidates.isEmpty
                  ? const _SecretaryWelcome()
                  : ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                      children: [
                        for (final message in messages)
                          _MessageBubble(message: message, app: app),
                        for (final candidate in activeCandidates) ...[
                          const SizedBox(height: 10),
                          GlobalKnowledgeCandidateCard(
                            candidate: candidate,
                            results: results,
                            showActions:
                                candidate.status ==
                                GlobalKnowledgeCandidateStatus.pending,
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
        _Composer(
          controller: _textController,
          attachments: _imageInputs,
          enabled: modelReady && (!_sending || app.isChatGenerating),
          imageEnabled: modelReady && imageEgressAllowed && imageCapability,
          files: _fileTexts,
          thinkingAvailable: modelReady && modelCapabilities.thinking,
          thinkingEnabled: _thinkingEnabled,
          webSearchAvailable: modelReady && modelCapabilities.webSearch,
          voiceService: AppScope.voice(context),
          onVoiceInput: _toggleVoiceInput,
          onThinkingChanged: (value) =>
              setState(() => _thinkingEnabled = value),
          generating: app.isChatGenerating,
          onPickGallery: _pickGallery,
          onPickCamera: _pickCamera,
          onPaste: _pasteText,
          onRemoveImage: (index) =>
              setState(() => _imageInputs.removeAt(index)),
          onPickFile: _pickFile,
          onRemoveFile: (index) => setState(() => _fileTexts.removeAt(index)),
          onSend: _send,
          onStop: app.cancelGeneration,
        ),
      ],
    );
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: Builder(
            builder: (drawerContext) => _buildSessionManager(
              drawerContext,
              app,
              conversation,
              inDrawer: true,
            ),
          ),
        ),
      ),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            key: const Key('conversation_manage'),
            tooltip: '对话管理',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu),
          ),
        ),
        title: Text(
          widget.isRoot ? '懒狗秘书' : conversation?.title ?? '懒狗秘书',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key: const Key('conversation_permissions'),
            tooltip: '当前对话权限',
            onPressed: () => _showPermissions(conversation),
            icon: const Icon(Icons.tune_outlined),
          ),
          IconButton(
            key: Key(
              widget.isRoot ? 'inbox_new_conversation' : 'conversation_new',
            ),
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
      body: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth >= 1200 && widget.isRoot
            ? Row(
                children: [
                  SizedBox(
                    width: 300,
                    child: _buildSessionManager(
                      context,
                      app,
                      conversation,
                      inDrawer: false,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ],
              )
            : body,
      ),
    );
  }
}

class _SecretaryWelcome extends StatelessWidget {
  const _SecretaryWelcome();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 42,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              '你好，我是懒狗秘书',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '可以帮你整理信息、安排日程、跟进待办和管理知识。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
