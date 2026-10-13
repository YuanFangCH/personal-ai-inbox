import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../modules/results/result_library.dart';
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
  static const _pageSize = 50;

  final _search = TextEditingController();
  ResultLibrary? _results;
  List<ResultDocument> _documents = const [];
  String _query = '';
  int _offset = 0;
  int _requestGeneration = 0;
  bool _hasMore = true;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final results = AppScope.results(context);
    if (!identical(results, _results)) {
      _results?.removeListener(_handleResultsChanged);
      _results = results..addListener(_handleResultsChanged);
    }
    if (_requestGeneration == 0) _load(reset: true);
  }

  @override
  void dispose() {
    _results?.removeListener(_handleResultsChanged);
    _search.dispose();
    super.dispose();
  }

  void _handleResultsChanged() => _load(reset: true);

  Future<void> _load({required bool reset}) async {
    if (!reset && (_loading || !_hasMore)) return;
    final generation = reset ? ++_requestGeneration : _requestGeneration;
    final offset = reset ? 0 : _offset;
    setState(() {
      _loading = true;
      if (reset) {
        _documents = const [];
        _offset = 0;
        _hasMore = true;
      }
    });
    try {
      final page = await _results!.searchKnowledge(
        query: _query,
        offset: offset,
        limit: _pageSize,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _documents = reset ? page : [..._documents, ...page];
        _offset = offset + page.length;
        _hasMore = page.length == _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim();
    return PageFrame(
      title: '知识',
      subtitle: '已加载 ${_documents.length} 条',
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
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >=
              notification.metrics.maxScrollExtent - 200) {
            _load(reset: false);
          }
          return false;
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _search,
              onChanged: (value) {
                _query = value;
                _load(reset: true);
              },
              decoration: const InputDecoration(
                hintText: '搜索标题、正文和标签',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 14),
            if (_documents.isEmpty && _loading)
              const Center(child: CircularProgressIndicator())
            else if (_documents.isEmpty)
              EmptyState(
                icon: Icons.menu_book_outlined,
                title: query.isEmpty ? '还没有知识' : '没有匹配结果',
                message: query.isEmpty ? '收下文章、链接或随手记后会出现在这里。' : '换个关键词试试。',
              )
            else
              SurfacePanel(
                child: Column(
                  children: [
                    for (var index = 0; index < _documents.length; index++) ...[
                      DocumentListTile(
                        document: _documents[index],
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DocumentDetailPage(
                              documentId: _documents[index].id,
                            ),
                          ),
                        ),
                      ),
                      if (index != _documents.length - 1)
                        const Divider(height: 1),
                    ],
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
