import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'document_detail_page.dart';
import 'document_editor_page.dart';

class KnowledgePage extends StatefulWidget {
  const KnowledgePage({super.key});

  @override
  State<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<KnowledgePage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final query = _search.text.trim().toLowerCase();
    final documents = app.knowledge
        .where((document) {
          if (query.isEmpty) {
            return true;
          }
          return document.title.toLowerCase().contains(query) ||
              document.body.toLowerCase().contains(query) ||
              document.tags.any((tag) => tag.toLowerCase().contains(query));
        })
        .toList(growable: false);
    return PageFrame(
      title: '知识',
      subtitle: '${app.knowledge.length} 条知识',
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const DocumentEditorPage.create(type: ResultType.knowledge),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('新建知识'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '搜索标题、正文和标签',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 14),
          if (documents.isEmpty)
            EmptyState(
              icon: Icons.menu_book_outlined,
              title: query.isEmpty ? '还没有知识' : '没有匹配结果',
              message: query.isEmpty ? '收下文章、链接或随手记后会出现在这里。' : '换个关键词试试。',
            )
          else
            SurfacePanel(
              child: Column(
                children: [
                  for (var index = 0; index < documents.length; index++) ...[
                    DocumentListTile(
                      document: documents[index],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DocumentDetailPage(
                            documentId: documents[index].id,
                          ),
                        ),
                      ),
                    ),
                    if (index != documents.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
