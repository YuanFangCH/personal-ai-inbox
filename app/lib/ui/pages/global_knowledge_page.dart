import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../modules/results/result_library.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

class GlobalKnowledgePage extends StatefulWidget {
  const GlobalKnowledgePage({super.key});

  @override
  State<GlobalKnowledgePage> createState() => _GlobalKnowledgePageState();
}

class _GlobalKnowledgePageState extends State<GlobalKnowledgePage> {
  ResultLibrary? _results;
  List<ResultDocument> _documents = const [];
  var _loading = true;
  var _loadFailed = false;
  var _loadGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final results = AppScope.results(context);
    if (_results == results) return;
    _results?.removeListener(_handleChange);
    _results = results..addListener(_handleChange);
    _load();
  }

  @override
  void dispose() {
    _results?.removeListener(_handleChange);
    super.dispose();
  }

  void _handleChange() => _load();

  Future<void> _load() async {
    final results = _results;
    if (results == null) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final documents = await results.searchKnowledge(globalOnly: true);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _documents = documents;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return PageFrame(
      title: '全局知识库',
      subtitle: '已确认后随成果同步到手机、平板和 Windows',
      actions: [
        FilledButton.icon(
          key: const Key('global_knowledge_add'),
          onPressed: results == null ? null : () => _editKnowledge(),
          icon: const Icon(Icons.add),
          label: const Text('新增事实'),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EmptyState(
                  icon: Icons.error_outline,
                  title: '全局知识暂时无法加载',
                  message: '请检查本地知识库状态后重试。',
                ),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            )
          : _documents.isEmpty
          ? const EmptyState(
              icon: Icons.lightbulb_outline,
              title: '还没有全局知识',
              message: '保存学期日期、周数等事实，让秘书在需要时计算和引用。',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final document in _documents) ...[
                  _KnowledgeTile(
                    document: document,
                    onEdit: () => _editKnowledge(document),
                    onDelete: () => _deleteKnowledge(document),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Future<void> _editKnowledge([ResultDocument? existing]) async {
    final fields = await showDialog<_KnowledgeFormValue>(
      context: context,
      animationStyle: reducedMotionAnimationStyle(context),
      builder: (_) => _KnowledgeFormDialog(document: existing),
    );
    if (fields == null || !mounted) return;
    final results = _results!;
    try {
      final candidate = await results.proposeGlobalKnowledgeChange(
        operation: existing == null
            ? GlobalKnowledgeOperation.create
            : GlobalKnowledgeOperation.update,
        targetId: existing?.id,
        expectedRevision: existing?.revision,
        expectedHash: existing == null
            ? null
            : await results.hashManagedDocument(existing.id),
        proposal: fields.toProposal(),
      );
      await results.confirmGlobalKnowledgeChange(
        candidate.id,
        displayedDigest: candidate.digest,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(existing == null ? '全局知识已新增' : '全局知识已修改')),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('未保存：$error')));
      }
    }
  }

  Future<void> _deleteKnowledge(ResultDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: reducedMotionAnimationStyle(context),
      builder: (context) => AlertDialog(
        title: const Text('确认删除全局知识？'),
        content: Text('“${document.title}”将被标记删除并随成果同步。此操作需要你明确确认。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final results = _results!;
    try {
      final hash = await results.hashManagedDocument(document.id);
      if (hash == null) throw StateError('全局知识文件不可读取');
      final candidate = await results.proposeGlobalKnowledgeChange(
        operation: GlobalKnowledgeOperation.delete,
        targetId: document.id,
        expectedRevision: document.revision,
        expectedHash: hash,
        proposal: const {},
      );
      await results.confirmGlobalKnowledgeChange(
        candidate.id,
        displayedDigest: candidate.digest,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('全局知识已删除')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('未删除：$error')));
      }
    }
  }
}

class _KnowledgeTile extends StatelessWidget {
  const _KnowledgeTile({
    required this.document,
    required this.onEdit,
    required this.onDelete,
  });

  final ResultDocument document;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final facts = document.extensionFields['global_facts'];
    return SurfacePanel(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  document.title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: '修改',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          if (document.body.isNotEmpty) Text(document.body),
          if (facts is Map) ...[
            const SizedBox(height: 6),
            SelectableText(jsonEncode(facts)),
          ],
          const SizedBox(height: 6),
          Text(
            '版本 ${document.revision} · ${document.extensionFields['global_approved_at'] ?? '已确认'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _KnowledgeFormValue {
  const _KnowledgeFormValue({
    required this.title,
    required this.body,
    required this.facts,
  });

  final String title;
  final String body;
  final Map<String, Object?> facts;

  Map<String, Object?> toProposal() => {
    'title': title,
    'body': body,
    'facts': facts,
  };
}

class _KnowledgeFormDialog extends StatefulWidget {
  const _KnowledgeFormDialog({this.document});

  final ResultDocument? document;

  @override
  State<_KnowledgeFormDialog> createState() => _KnowledgeFormDialogState();
}

class _KnowledgeFormDialogState extends State<_KnowledgeFormDialog> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _facts;
  String? _error;

  @override
  void initState() {
    super.initState();
    final document = widget.document;
    _title = TextEditingController(text: document?.title ?? '');
    _body = TextEditingController(text: document?.body ?? '');
    _facts = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(
        document?.extensionFields['global_facts'] ?? <String, Object?>{},
      ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _facts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.document == null ? '新增全局知识' : '修改全局知识'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            TextField(
              controller: _body,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: '说明'),
            ),
            TextField(
              controller: _facts,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '结构化事实（JSON）',
                hintText: '{"semester_start":"2026-09-01","week_count":16}',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('global_knowledge_confirm_save'),
        onPressed: _save,
        child: const Text('确认并保存'),
      ),
    ],
  );

  void _save() {
    try {
      final decoded = jsonDecode(_facts.text);
      if (decoded is! Map) throw const FormatException('事实必须是 JSON 对象');
      final facts = Map<String, Object?>.from(decoded);
      if (_title.text.trim().isEmpty) throw const FormatException('标题不能为空');
      Navigator.pop(
        context,
        _KnowledgeFormValue(
          title: _title.text.trim(),
          body: _body.text.trim(),
          facts: facts,
        ),
      );
    } on Object catch (error) {
      setState(() => _error = error.toString());
    }
  }
}
