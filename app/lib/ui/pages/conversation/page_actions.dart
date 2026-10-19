part of '../conversation_page.dart';

mixin _ConversationPageActions on State<ConversationPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _imageInputs = <ChatAttachmentInput>[];
  final _imagePicker = ImageInputService();
  final _fileTexts = <ExtractedFileText>[];
  final _historySearchController = TextEditingController();
  bool _sending = false;
  int _lastMessageCount = -1;
  String? _conversationId;
  String _voiceBaseText = '';
  int _voiceInsertStart = 0;
  int _voiceReplaceEnd = 0;
  AiPermissions _temporaryPermissions = const AiPermissions();
  bool _temporaryPermissionsInitialized = false;
  bool _thinkingEnabled = false;

  void _initializeConversationPage() {
    _conversationId = widget.conversationId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _conversationId != null) {
        AppScope.conversations(context).openConversation(_conversationId!);
      }
    });
  }

  void _disposeConversationPage() {
    _textController.dispose();
    _scrollController.dispose();
    _historySearchController.dispose();
  }

  Future<void> _send() async {
    final app = AppScope.conversations(context);
    final text = _composeMessageText(_textController.text);
    if ((text.trim().isEmpty && _imageInputs.isEmpty) ||
        app.isChatGenerating ||
        _sending) {
      return;
    }
    final voice = AppScope.voice(context);
    if (voice.isListening) await voice.stopListening();
    setState(() => _sending = true);
    try {
      final attachments = List<ChatAttachmentInput>.from(_imageInputs);
      var conversationId = _conversationId;
      if (conversationId == null) {
        final conversation = await app.createConversation(
          permissions: _temporaryPermissions,
        );
        conversationId = conversation.id;
        if (mounted) {
          setState(() => _conversationId = conversationId);
        }
      }
      if (mounted) {
        _textController.clear();
        setState(() {
          _imageInputs.clear();
          _fileTexts.clear();
        });
      }
      await app.sendChatMessage(
        conversationId,
        text: text,
        attachments: attachments,
        thinkingEnabled: _thinkingEnabled,
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

  Future<void> _toggleVoiceInput() async {
    final voice = AppScope.voice(context);
    if (voice.isListening) {
      await voice.stopListening();
      return;
    }
    final text = _textController.text;
    final selection = _textController.selection;
    _voiceBaseText = text;
    _voiceInsertStart = selection.isValid ? selection.start : text.length;
    _voiceReplaceEnd = selection.isValid ? selection.end : text.length;
    final started = await voice.startListening((recognized, isFinal) {
      if (!mounted || recognized.isEmpty) return;
      final before = _voiceBaseText.substring(0, _voiceInsertStart);
      final after = _voiceBaseText.substring(_voiceReplaceEnd);
      final separator = before.isNotEmpty && !RegExp(r'\s$').hasMatch(before)
          ? ' '
          : '';
      final inserted = '$separator$recognized';
      final updated = '$before$inserted$after';
      _textController.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(
          offset: before.length + inserted.length,
        ),
      );
      setState(() {});
    });
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(voice.lastError ?? '离线语音识别不可用，请检查麦克风权限和中文语言包。')),
      );
    }
  }

  Future<void> _pickFile() async {
    const maxMessageChars = 24000;
    final used = _fileTexts.fold<int>(
      0,
      (total, file) => total + file.text.runes.length,
    );
    final remaining = maxMessageChars - used;
    if (remaining <= 0 || _fileTexts.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('每条消息最多添加 3 个文件、共 24,000 个字符。')),
      );
      return;
    }
    try {
      final file = await AppScope.fileInput(context).pickAndExtract(
        maxTextChars: remaining < FileInputService.maxFileTextChars
            ? remaining
            : FileInputService.maxFileTextChars,
      );
      if (!mounted || file == null) return;
      setState(() => _fileTexts.add(file));
      if (file.truncated) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${file.fileName} 内容超过预算，已截取可读部分。')),
        );
      }
    } on FileInputException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  String _composeMessageText(String typedText) {
    final output = StringBuffer(typedText.trim());
    for (final file in _fileTexts) {
      if (output.isNotEmpty) output.write('\n\n');
      output
        ..write('【文件：${file.fileName}${file.truncated ? '（已截取）' : ''}】\n')
        ..write(file.text);
    }
    return output.toString();
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
    if (AppScope.voice(context).isListening) {
      await AppScope.voice(context).stopListening();
    }
    if (!mounted) return;
    if (widget.isRoot) {
      setState(() {
        _conversationId = null;
        _temporaryPermissions = AppScope.preferences(context)
            .settings
            .defaultAiPermissions;
        _textController.clear();
        _imageInputs.clear();
        _fileTexts.clear();
        _historySearchController.clear();
        _thinkingEnabled = false;
        _lastMessageCount = 0;
      });
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const ConversationPage()),
    );
  }

  Widget _buildSessionManager(
    BuildContext context,
    ConversationWorkspace app,
    Conversation? activeConversation, {
    required bool inDrawer,
  }) {
    final theme = Theme.of(context);
    final query = _historySearchController.text.trim().toLowerCase();
    final conversations = app.conversations
        .where((conversation) {
          return query.isEmpty ||
              conversation.title.toLowerCase().contains(query) ||
              conversation.preview.toLowerCase().contains(query);
        })
        .toList(growable: false);
    final pendingCount =
        AppScope.capture(context).reviewCaptures.length +
        AppScope.sync(context).conflictFiles.length +
        AppScope.results(context).globalKnowledgeCandidates
            .where(
              (candidate) =>
                  candidate.status != GlobalKnowledgeCandidateStatus.applied &&
                  candidate.status != GlobalKnowledgeCandidateStatus.rejected,
            )
            .length +
        AppScope.results(context).draftDocuments.length;
    final groupedRows = _groupedConversationRows(conversations);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '懒狗秘书',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                key: const Key('conversation_new_from_drawer'),
                tooltip: '新对话',
                onPressed: () {
                  if (inDrawer) {
                    Navigator.pop(context);
                  }
                  _newConversation();
                },
                icon: const Icon(Icons.add_comment_outlined),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            key: const Key('conversation_search'),
            controller: _historySearchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '搜索对话',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _historySearchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除搜索',
                      onPressed: () {
                        _historySearchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          key: const Key('conversation_pending_page'),
          leading: const Icon(Icons.inbox_outlined),
          title: const Text('待处理'),
          trailing: pendingCount == 0
              ? null
              : StatusPill(label: '$pendingCount', tone: StatusTone.warning),
          onTap: () {
            if (inDrawer) Navigator.pop(context);
            Navigator.of(this.context).push(
              MaterialPageRoute<void>(builder: (_) => const PendingPage()),
            );
          },
        ),
        ListTile(
          key: const Key('conversation_global_knowledge'),
          leading: const Icon(Icons.lightbulb_outline),
          title: const Text('全局知识库'),
          onTap: () {
            if (inDrawer) Navigator.pop(context);
            Navigator.of(this.context).push(
              MaterialPageRoute<void>(
                builder: (_) => const GlobalKnowledgePage(),
              ),
            );
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: groupedRows.isEmpty
              ? Center(
                  child: Text(
                    query.isEmpty ? '还没有历史对话' : '没有匹配的对话',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : ListView.builder(
                  key: const Key('conversation_history_list'),
                  itemCount: groupedRows.length,
                  itemBuilder: (context, index) {
                    final row = groupedRows[index];
                    if (row.conversation == null) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          row.groupLabel!,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    final conversation = row.conversation!;
                    return ListTile(
                      key: Key('conversation_${conversation.id}'),
                      selected: activeConversation?.id == conversation.id,
                      title: Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: conversation.preview.isEmpty
                          ? null
                          : Text(
                              conversation.preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () {
                        if (inDrawer) Navigator.pop(context);
                        _openManagedConversation(conversation.id);
                      },
                      trailing: PopupMenuButton<String>(
                        tooltip: '对话选项',
                        onSelected: (value) {
                          if (value == 'rename') {
                            _renameConversation(conversation);
                          } else if (value == 'delete') {
                            _deleteConversation(conversation);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('重命名')),
                          PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text('对话保存在本机；成果按同步规则共享。', style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }

  List<_ConversationHistoryRow> _groupedConversationRows(
    List<Conversation> conversations,
  ) {
    final rows = <_ConversationHistoryRow>[];
    String? previousGroup;
    for (final conversation in conversations) {
      final group = _conversationGroup(conversation.updatedAt);
      if (group != previousGroup) {
        rows.add(_ConversationHistoryRow.group(group));
        previousGroup = group;
      }
      rows.add(_ConversationHistoryRow.item(conversation));
    }
    return rows;
  }

  String _conversationGroup(DateTime value) {
    final now = DateTime.now();
    final date = DateTime(value.year, value.month, value.day);
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(date).inDays;
    if (difference <= 0) return '今天';
    if (difference == 1) return '昨天';
    if (difference <= 7) return '7 天内';
    if (difference <= 30) return '30 天内';
    return DateFormat('yyyy年M月').format(value);
  }

  Future<void> _openManagedConversation(String id) async {
    _historySearchController.clear();
    final voice = AppScope.voice(context);
    final app = AppScope.conversations(context);
    if (voice.isListening) {
      await voice.stopListening();
    }
    await app.openConversation(id);
    if (!mounted) return;
    setState(() {
      _conversationId = id;
      _lastMessageCount = -1;
      _textController.clear();
      _imageInputs.clear();
      _fileTexts.clear();
      _thinkingEnabled = false;
    });
  }

  AiPermissions _currentPermissions(Conversation? conversation) =>
      conversation?.aiPermissions ?? _temporaryPermissions;

  Future<void> _showPermissions(Conversation? conversation) async {
    var permissions = _currentPermissions(conversation);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '当前对话权限',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const Key('conversation_permissions_close'),
                      tooltip: '完成',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('只影响当前对话；全局设置决定新对话默认值。'),
                const SizedBox(height: 8),
                _permissionTile(
                  title: '读取',
                  subtitle: '按需读取成果、全局知识和其他对话',
                  value: permissions.read,
                  onChanged: (value) => _setPermission(
                    conversation,
                    permissions.copyWith(read: value),
                    setSheetState,
                    (next) => permissions = next,
                  ),
                ),
                _permissionTile(
                  title: '新增',
                  subtitle: '允许创建普通成果、提议新增全局知识',
                  value: permissions.create,
                  onChanged: (value) => _setPermission(
                    conversation,
                    permissions.copyWith(create: value),
                    setSheetState,
                    (next) => permissions = next,
                  ),
                ),
                _permissionTile(
                  title: '修改与删除',
                  subtitle: '修改/删除普通成果；全局知识仍需确认',
                  value: permissions.modifyDelete,
                  onChanged: (value) => _setPermission(
                    conversation,
                    permissions.copyWith(modifyDelete: value),
                    setSheetState,
                    (next) => permissions = next,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setPermission(
    Conversation? conversation,
    AiPermissions next,
    StateSetter setSheetState,
    ValueChanged<AiPermissions> updateLocal,
  ) async {
    updateLocal(next);
    setSheetState(() {});
    if (conversation == null) {
      setState(() => _temporaryPermissions = next);
    } else {
      await AppScope.conversations(context)
          .setConversationPermissions(conversation.id, next);
    }
  }

  Widget _permissionTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => SwitchListTile(
    title: Text(title),
    subtitle: Text(subtitle),
    value: value,
    onChanged: onChanged,
    contentPadding: EdgeInsets.zero,
  );

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
      await AppScope.conversations(context)
          .renameConversation(conversation.id, title);
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
    await AppScope.conversations(context).deleteConversation(conversation.id);
    if (mounted && conversation.id == _conversationId && widget.isRoot) {
      setState(() {
        _conversationId = null;
        _temporaryPermissions = AppScope.preferences(context)
            .settings
            .defaultAiPermissions;
        _lastMessageCount = 0;
        _textController.clear();
        _imageInputs.clear();
        _fileTexts.clear();
        _thinkingEnabled = false;
      });
    } else if (mounted && conversation.id == _conversationId) {
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

class _ConversationHistoryRow {
  const _ConversationHistoryRow._({this.conversation, this.groupLabel});

  factory _ConversationHistoryRow.group(String label) =>
      _ConversationHistoryRow._(groupLabel: label);

  factory _ConversationHistoryRow.item(Conversation conversation) =>
      _ConversationHistoryRow._(conversation: conversation);

  final Conversation? conversation;
  final String? groupLabel;
}
