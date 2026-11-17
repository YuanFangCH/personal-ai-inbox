import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/agent_instructions.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

class AgentInstructionsPage extends StatefulWidget {
  const AgentInstructionsPage({super.key});
  @override
  State<AgentInstructionsPage> createState() => _AgentInstructionsPageState();
}

class _AgentInstructionsPageState extends State<AgentInstructionsPage> {
  final _editor = TextEditingController();
  String _revision = 'missing';
  bool _loaded = false, _saving = false;
  bool _conflicted = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      final store = AppScope.of(context).agentInstructions;
      store.load().then((result) async {
        if (!mounted) return;
        switch (result) {
          case InstructionsReady(:final snapshot):
            _revision = snapshot.revision;
            _editor.text = snapshot.markdown;
          case InstructionsReadFailed(:final message):
            _revision = await store.repairRevision() ?? 'missing';
            _error = message;
        }
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Material(
      child: PageFrame(
        title: '秘书指令（AGENTS.md）',
        subtitle: '每次发送消息时自动加载。文件内容会随请求发送给当前模型，不会同步到其他设备。',
        actions: [
          IconButton(
            onPressed: _saving ? null : _export,
            tooltip: '导出 AGENTS.md',
            icon: const Icon(Icons.download),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _editor,
              minLines: 12,
              maxLines: 30,
              decoration: const InputDecoration(
                hintText: '写入长期偏好、默认规则和事实口径',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_conflicted)
              TextButton.icon(
                onPressed: _saving ? null : _reloadLatest,
                icon: const Icon(Icons.refresh),
                label: const Text('放弃本地修改并重新加载最新版本'),
              ),
            if (_revision != 'missing')
              TextButton.icon(
                onPressed: _saving ? null : _undo,
                icon: const Icon(Icons.undo),
                label: const Text('撤销最近一次改动'),
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    final result = await AppScope.of(context).agentInstructions
        .save(expectedRevision: _revision, markdown: _editor.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result.status == InstructionWriteStatus.applied ||
          result.status == InstructionWriteStatus.unchanged) {
        _revision = result.revision ?? _revision;
        _error = null;
        _conflicted = false;
      } else {
        _error = result.message;
        _conflicted = result.status == InstructionWriteStatus.conflict;
      }
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _reloadLatest() async {
    setState(() => _saving = true);
    final store = AppScope.of(context).agentInstructions;
    final result = await store.load();
    if (!mounted) return;
    switch (result) {
      case InstructionsReady(:final snapshot):
        _editor.text = snapshot.markdown;
        _revision = snapshot.revision;
        _error = null;
      case InstructionsReadFailed(:final message):
        _revision = await store.repairRevision() ?? 'missing';
        _error = message;
    }
    setState(() {
      _saving = false;
      _conflicted = false;
    });
  }

  Future<void> _export() async {
    final bytes = await AppScope.of(context).agentInstructions.exportBytes();
    if (bytes == null) return;
    await FilePicker.saveFile(
      fileName: 'AGENTS.md',
      bytes: Uint8List.fromList(bytes),
      type: FileType.custom,
      allowedExtensions: const ['md'],
      dialogTitle: '导出秘书指令',
    );
  }

  Future<void> _undo() async {
    final store = AppScope.of(context).agentInstructions;
    final undo = await store.latestUndo();
    if (undo == null) return;
    final result = await store.undo(
      operationId: undo.operationId,
      expectedRevision: undo.revision,
    );
    if (!mounted) return;
    if (result.status == InstructionWriteStatus.applied) {
      _revision = result.revision ?? 'missing';
      _editor.text =
          (await store.load() as InstructionsReady).snapshot.markdown;
    } else {
      _error = result.message;
    }
    setState(() {});
  }
}
