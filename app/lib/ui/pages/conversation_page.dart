import 'dart:async';

import 'package:flutter/foundation.dart';
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
import '../presentation/markdown_presentation.dart';
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
  const ConversationPage({
    super.key,
    this.conversationId,
    this.isRoot = false,
    this.isWide = false,
    this.onReturnHome,
    this.onNavigate,
  });

  final String? conversationId;
  final bool isRoot;
  final bool isWide;
  final VoidCallback? onReturnHome;
  final ValueChanged<String>? onNavigate;

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
    _prepareMessageEntries(conversationId, messages);
    if (messages.length != _lastMessageCount) {
      _lastMessageCount = messages.length;
      _scrollToBottom();
    }
    if (app.isChatGenerating) {
      _scrollToBottom();
    }
    final modelReady = settings.hasModelKey;
    final imageEgressAllowed = settings.allowImageEgress;
    final modelCapabilities = ModelCapabilities.resolve(settings);
    final imageCapability = modelCapabilities.vision;
    final desktopWideRoot =
        widget.isRoot && MediaQuery.sizeOf(context).width >= 1024;
    final activeCandidates = results.globalKnowledgeCandidates
        .where(
          (candidate) =>
              candidate.sourceConversationId == conversationId &&
              candidate.status != GlobalKnowledgeCandidateStatus.rejected,
        )
        .toList(growable: false);
    final desktopEmpty =
        desktopWideRoot && messages.isEmpty && activeCandidates.isEmpty;
    final desktopInput =
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
    final conversationContent = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppDesignTokens.conversationContentMaxWidth,
        ),
        child: messages.isEmpty && activeCandidates.isEmpty
            ? desktopWideRoot
                  ? const SizedBox.shrink()
                  : const _SecretaryWelcome()
            : NotificationListener<ScrollNotification>(
                onNotification: _handleConversationScroll,
                child: ListView(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    18,
                    16,
                    desktopWideRoot ? 152 : 24,
                  ),
                  children: [
                    for (final message in messages)
                      KeyedSubtree(
                        key: ValueKey('message_${message.id}'),
                        child: _buildMessageRow(message, app),
                      ),
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
    );
    final composer = _Composer(
      controller: _textController,
      focusNode: _composerFocusNode,
      attachments: _imageInputs,
      files: _fileTexts,
      enabled: modelReady && (!_sending || app.isChatGenerating),
      desktopInput: desktopInput,
      imageEnabled: modelReady && imageEgressAllowed && imageCapability,
      thinkingAvailable: modelReady && modelCapabilities.thinking,
      thinkingEnabled: _thinkingEnabled,
      webSearchAvailable: modelReady && modelCapabilities.webSearch,
      voiceService: AppScope.voice(context),
      onVoiceInput: _toggleVoiceInput,
      onThinkingChanged: (value) => setState(() => _thinkingEnabled = value),
      generating: app.isChatGenerating,
      attachmentTrayOpen: _attachmentTrayOpen,
      onToggleAttachmentTray: _toggleAttachmentTray,
      onInputFocused: _closeAttachmentTray,
      onPickGallery: () {
        _closeAttachmentTray();
        _pickGallery();
      },
      onPickCamera: () {
        _closeAttachmentTray();
        _pickCamera();
      },
      onPaste: () {
        _closeAttachmentTray();
        _pasteText();
      },
      onRemoveImage: (index) => setState(() => _imageInputs.removeAt(index)),
      onPickFile: () {
        _closeAttachmentTray();
        _pickFile();
      },
      onRemoveFile: (index) => setState(() => _fileTexts.removeAt(index)),
      onSend: _send,
      onStop: app.cancelGeneration,
    );
    final body = desktopWideRoot
        ? Stack(
            children: [
              Positioned.fill(child: conversationContent),
              AnimatedAlign(
                alignment: desktopEmpty
                    ? Alignment.center
                    : Alignment.bottomCenter,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                curve: Curves.easeInOutCubic,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppDesignTokens.conversationContentMaxWidth,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSize(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          curve: Curves.easeInOut,
                          alignment: Alignment.bottomCenter,
                          child: desktopEmpty
                              ? const Padding(
                                  key: ValueKey('desktop_welcome_visible'),
                                  padding: EdgeInsets.only(bottom: 24),
                                  child: _SecretaryWelcome(),
                                )
                              : const SizedBox(
                                  key: ValueKey('desktop_welcome_hidden'),
                                ),
                        ),
                        composer,
                      ],
                    ),
                  ),
                ),
              ),
              if (!_followConversationTail &&
                  messages.isNotEmpty &&
                  !_attachmentTrayOpen)
                Positioned(
                  right: 20,
                  bottom: 112,
                  child: IconButton.filledTonal(
                    key: const Key('conversation_jump_to_latest'),
                    tooltip: '回到底部',
                    onPressed: () => _scrollToBottom(force: true),
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                ),
            ],
          )
        : Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: conversationContent),
                    if (!_followConversationTail && messages.isNotEmpty)
                      Positioned(
                        right: 20,
                        bottom: 12,
                        child: IconButton.filledTonal(
                          key: const Key('conversation_jump_to_latest'),
                          tooltip: '回到底部',
                          onPressed: () => _scrollToBottom(force: true),
                          icon: const Icon(Icons.keyboard_arrow_down),
                        ),
                      ),
                  ],
                ),
              ),
              composer,
            ],
          );
    return PopScope<Object?>(
      canPop: !widget.isRoot || _sessionDrawerOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.isRoot) _handleAssistantBack();
      },
      child: Scaffold(
        onDrawerChanged: (open) {
          if (open) _drawerWasOpen = true;
          setState(() => _sessionDrawerOpen = open);
          if (!open && _drawerWasOpen) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _drawerWasOpen = false;
            });
          }
        },
        drawer: Drawer(
          width: (MediaQuery.sizeOf(context).width * 0.86)
              .clamp(260.0, 340.0)
              .toDouble(),
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
          builder: (context, constraints) {
            final reduceMotion = MediaQuery.disableAnimationsOf(context);
            final shiftForDrawer =
                widget.isRoot &&
                constraints.maxWidth < 600 &&
                _sessionDrawerOpen;
            final pageBody =
                constraints.maxWidth >= 1024 && widget.isRoot && widget.isWide
                ? Row(
                    children: [
                      SizedBox(
                        width: 252,
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
                : body;
            final borderRadius = shiftForDrawer
                ? const BorderRadius.all(Radius.circular(20))
                : BorderRadius.zero;
            return AnimatedSlide(
              key: const Key('conversation_drawer_shift'),
              offset: shiftForDrawer ? const Offset(0.86, 0) : Offset.zero,
              duration: reduceMotion
                  ? Duration.zero
                  : AppDesignTokens.overlayTransition,
              curve: Curves.easeOutCubic,
              child: AnimatedScale(
                scale: shiftForDrawer && !reduceMotion ? 0.98 : 1,
                alignment: Alignment.centerLeft,
                duration: reduceMotion
                    ? Duration.zero
                    : AppDesignTokens.overlayTransition,
                curve: Curves.easeOutCubic,
                child: ClipRRect(borderRadius: borderRadius, child: pageBody),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMessageRow(ChatMessage message, ConversationWorkspace app) {
    final bubble = _MessageBubble(message: message, app: app);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) _enteringMessageIds.remove(message.id);
    if (!_enteringMessageIds.contains(message.id)) {
      return bubble;
    }
    return _ConversationMessageEntrance(
      key: ValueKey('message_entrance_${message.id}'),
      onCompleted: () {
        if (mounted && _enteringMessageIds.remove(message.id)) {
          setState(() {});
        }
      },
      child: bubble,
    );
  }
}

class _ConversationMessageEntrance extends StatefulWidget {
  const _ConversationMessageEntrance({
    super.key,
    required this.onCompleted,
    required this.child,
  });

  final VoidCallback onCompleted;
  final Widget child;

  @override
  State<_ConversationMessageEntrance> createState() =>
      _ConversationMessageEntranceState();
}

class _ConversationMessageEntranceState
    extends State<_ConversationMessageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 170),
  )..addStatusListener(_handleStatus);

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, 0.012),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onCompleted();
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: SlideTransition(position: _offset, child: widget.child),
  );
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
              size: 32,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '今天有什么想交给我？',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontSize: 22),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecretaryDesktopNavigation extends StatelessWidget {
  const _SecretaryDesktopNavigation({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    const destinations = [
      ('home', '首页', Icons.space_dashboard_outlined),
      ('calendar', '日历', Icons.calendar_month_outlined),
      ('matters', '事项', Icons.account_tree_outlined),
      ('knowledge', '知识', Icons.menu_book_outlined),
    ];
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth - 8) / 2;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final (destination, label, icon) in destinations)
                    SizedBox(
                      width: itemWidth,
                      height: 44,
                      child: TextButton.icon(
                        key: Key('secretary_nav_$destination'),
                        onPressed: () => onSelect(destination),
                        icon: Icon(icon, size: 18),
                        label: Text(label, maxLines: 1),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          foregroundColor: theme.colorScheme.onSurface,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                      ),
                    ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: PopupMenuButton<String>(
                  key: const Key('secretary_nav_more'),
                  tooltip: '更多页面',
                  onSelected: onSelect,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'global_knowledge',
                      child: Text('全局知识库'),
                    ),
                    PopupMenuItem(value: 'pending', child: Text('待处理')),
                    PopupMenuItem(value: 'settings', child: Text('设置')),
                    PopupMenuItem(value: 'sync', child: Text('同步')),
                  ],
                  child: const SizedBox(
                    height: 44,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.more_horiz),
                          SizedBox(width: 8),
                          Text('更多'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
