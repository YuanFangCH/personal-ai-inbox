import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/legacy_global_knowledge_retirement.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

class LegacyGlobalKnowledgeRetirementPage extends StatefulWidget {
  const LegacyGlobalKnowledgeRetirementPage({super.key});

  @override
  State<LegacyGlobalKnowledgeRetirementPage> createState() =>
      _LegacyGlobalKnowledgeRetirementPageState();
}

class _LegacyGlobalKnowledgeRetirementPageState
    extends State<LegacyGlobalKnowledgeRetirementPage> {
  Future<LegacyKnowledgePreview>? _preview;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _preview ??= AppScope.of(context).legacyKnowledgeRetirement.preview();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: '归档旧全局知识',
    subtitle: '确认后会把旧知识、待处理候选和关联冲突打包到本机归档。内容不会转入 AGENTS.md。',
    child: FutureBuilder(
      future: _preview,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final preview = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('旧条目：${preview.documents}'),
            Text('待处理记录：${preview.candidates}'),
            Text('关联冲突副本：${preview.conflicts}'),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed:
                  _busy ||
                      preview.documents +
                              preview.candidates +
                              preview.conflicts ==
                          0
                  ? null
                  : _archive,
              child: Text(_busy ? '正在归档…' : '确认并归档'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _export,
              child: const Text('导出已生成的归档 ZIP'),
            ),
          ],
        );
      },
    ),
  );

  Future<void> _archive() async {
    final retirement = AppScope.of(context).legacyKnowledgeRetirement;
    final preview = await _preview!;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认归档旧全局知识？'),
        content: const Text('将创建本机 ZIP 归档，并从活动数据中移除旧知识。此内容不会自动写入秘书指令。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认归档'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await retirement.archive(expectedRevision: preview.revision);
      if (mounted) {
        setState(() {
          _preview = retirement.preview();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final retirement = AppScope.of(context).legacyKnowledgeRetirement;
    final bytes = await retirement.exportArchive();
    if (bytes == null) return;
    if (!mounted) return;
    await FilePicker.saveFile(
      fileName: 'legacy-global-knowledge.zip',
      bytes: Uint8List.fromList(bytes),
      dialogTitle: '导出旧全局知识归档',
    );
  }
}
