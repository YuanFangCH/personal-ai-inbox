part of '../conversation_page.dart';

mixin _ConversationPageActions on State<ConversationPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _imageInputs = <ChatAttachmentInput>[];
  final _imagePicker = ImageInputService();
  bool _sending = false;
  int _lastMessageCount = -1;
  String? _conversationId;

  void _initializeConversationPage() {
    _conversationId = widget.conversationId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _conversationId != null) {
        AppScope.of(context).openConversation(_conversationId!);
      }
    });
  }

  void _disposeConversationPage() {
    _textController.dispose();
    _scrollController.dispose();
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
