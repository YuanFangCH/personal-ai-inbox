import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/table_models.dart';
import '../../modules/tables/table_library.dart';
import '../app_scope.dart';
import 'common.dart';

class LegacyDraftQueue extends StatelessWidget {
  const LegacyDraftQueue({super.key, required this.documents});

  final List<ResultDocument> documents;

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) return const SizedBox.shrink();
    final tables = AppScope.tables(context);
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            title: '旧格式草稿',
            trailing: Text('${documents.length} 项'),
          ),
          const SizedBox(height: 8),
          for (final document in documents)
            _LegacyDraftTile(document: document, tables: tables),
          const SizedBox(height: 4),
          Text(
            '复制会在对应默认表中创建新条目，原草稿会继续保留。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _LegacyDraftTile extends StatelessWidget {
  const _LegacyDraftTile({required this.document, required this.tables});

  final ResultDocument document;
  final TableLibrary tables;

  @override
  Widget build(BuildContext context) {
    final entryId = _entryId(document.id);
    final global = document.isGlobalKnowledge;
    final copied = tables.entries.any(
      (entry) =>
          entry.id == entryId ||
          entry.extensionFields['legacy_source_id'] == document.id,
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.description_outlined),
      title: Text(document.title),
      subtitle: Text(
        document.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _LegacyDraftDetail(document: document),
        ),
      ),
      trailing: TextButton(
        key: Key('legacy_draft_copy_${document.id}'),
        onPressed: copied || global ? null : () => _copy(context),
        child: Text(
          global
              ? '全局知识单独确认'
              : copied
              ? '已复制'
              : '复制到表',
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    if (document.isGlobalKnowledge) {
      throw StateError('全局知识保持独立审批，不能复制到普通表绕过确认。');
    }
    final role = _tableRole(document);
    final table = tables.tables.singleWhere((item) => item.role == role);
    try {
      await tables.createEntry(
        TableEntryDocument(
          id: _entryId(document.id),
          type: _entryType(document),
          tableId: table.id,
          title: document.title,
          revision: 1,
          createdAt: document.createdAt,
          updatedAt: DateTime.now(),
          body: document.body,
          tags: document.tags,
          links: document.links,
          due: document.type == ResultType.todo ? document.due : null,
          done: document.type == ResultType.todo && document.done,
          start: _entryType(document) == TableContentType.schedule
              ? document.start
              : null,
          end: _entryType(document) == TableContentType.schedule
              ? document.end
              : null,
          allDay:
              _entryType(document) == TableContentType.schedule &&
              document.allDay,
          recurrence: _entryType(document) == TableContentType.schedule
              ? document.recurrence
              : null,
          occurredAt: _entryType(document) == TableContentType.event
              ? document.start
              : null,
          extensionFields: {'legacy_source_id': document.id},
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('草稿未复制：${error is StateError ? error.message : error}'),
        ),
      );
    }
  }
}

class _LegacyDraftDetail extends StatelessWidget {
  const _LegacyDraftDetail({required this.document});

  final ResultDocument document;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('旧格式草稿（只读）')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(document.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        SelectableText(document.body),
        const SizedBox(height: 16),
        Text(
          '来源 ID：${document.id}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

String _entryId(String id) =>
    'nt_draft_${sha256.convert(id.codeUnits).toString().substring(0, 24)}';

TableContentType _entryType(ResultDocument document) {
  if (document.type == ResultType.todo) return TableContentType.todo;
  if (document.type == ResultType.event) {
    final start = document.start;
    if (start != null && start.isAfter(DateTime.now())) {
      return TableContentType.schedule;
    }
    return TableContentType.event;
  }
  return TableContentType.note;
}

TableRole _tableRole(ResultDocument document) => switch (_entryType(document)) {
  TableContentType.todo => TableRole.inboxTodo,
  TableContentType.schedule => TableRole.inboxSchedule,
  TableContentType.event || TableContentType.note => TableRole.inboxEvent,
};
