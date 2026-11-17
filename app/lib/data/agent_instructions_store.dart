import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../core/agent_instructions.dart';
import 'vault_store.dart';

class AgentInstructionsStore {
  AgentInstructionsStore(this._vault, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const path = 'AGENTS.md';
  static const maxBytes = 8192;
  static const _root = '.local/agent-instructions';
  static const _pending = '$_root/pending.json';
  static const _latest = '$_root/latest.json';
  static const _undoWindow = Duration(minutes: 10);

  final VaultStore _vault;
  final DateTime Function() _clock;

  Future<InstructionReadResult> load() => _vault.exclusive(() async {
    try {
      final snapshot = await _snapshot();
      return InstructionsReady(snapshot);
    } on FormatException {
      return const InstructionsReadFailed(
        'invalid_file',
        'AGENTS.md 不是有效的 UTF-8 文件，或超过 8 KiB。请在设置中处理。',
      );
    } on Exception {
      return const InstructionsReadFailed(
        'read_failed',
        '无法读取 AGENTS.md，请检查设置后重试。',
      );
    }
  });

  Future<List<int>?> exportBytes() async {
    final result = await load();
    if (result case InstructionsReady(:final snapshot)) {
      return utf8.encode(snapshot.markdown);
    }
    return null;
  }

  Future<InstructionWriteResult> save({
    required String expectedRevision,
    required String markdown,
  }) => _mutate(
    id: const Uuid().v4(),
    expected: expectedRevision,
    digest: _digestText(markdown),
    transform: (_) => markdown,
    // The editor can explicitly replace malformed or oversized bytes.
    allowInvalidBefore: true,
  );

  Future<InstructionWriteResult> edit({
    required String operationId,
    required String expectedRevision,
    required List<InstructionEdit> edits,
    required Future<bool> Function() canCommit,
  }) => _mutate(
    id: operationId,
    expected: expectedRevision,
    digest: _digestText(
      jsonEncode([
        expectedRevision,
        for (final e in edits) [e.oldText, e.newText],
      ]),
    ),
    transform: (current) => _applyEdits(current!, edits),
    canCommit: canCommit,
  );

  Future<InstructionWriteResult> undo({
    required String operationId,
    required String expectedRevision,
  }) => _guard(() async {
    final last = await _readJson(_latest);
    final current = await _snapshot();
    if (last?['id'] != operationId ||
        last?['after_revision'] != expectedRevision ||
        current.revision != expectedRevision) {
      return _result(
        InstructionWriteStatus.conflict,
        '文件已有其他改动，未撤销。',
        revision: current.revision,
        code: 'conflict',
      );
    }
    final expires = DateTime.parse(last!['undo_until'] as String);
    if (!_clock().isBefore(expires)) {
      await _vault.delete(_latest);
      return _result(
        InstructionWriteStatus.rejected,
        '撤销期限已过。',
        code: 'undo_expired',
      );
    }
    return _commit(
      id: const Uuid().v4(),
      digest: operationId,
      before: current,
      after: last['before'] as String?,
      canUndo: false,
    );
  });

  Future<InstructionUndo?> latestUndo() => _vault.exclusive(() async {
    await _recover();
    final latest = await _readJson(_latest);
    final rawUntil = latest?['undo_until'] as String?;
    final id = latest?['id'] as String?;
    final revision = latest?['after_revision'] as String?;
    if (rawUntil == null || id == null || revision == null) return null;
    final until = DateTime.parse(rawUntil);
    return _clock().isBefore(until)
        ? (operationId: id, revision: revision, until: until)
        : null;
  });

  Future<InstructionWriteResult> _mutate({
    required String id,
    required String expected,
    required String digest,
    required String Function(String?) transform,
    bool allowInvalidBefore = false,
    Future<bool> Function()? canCommit,
  }) => _guard(() async {
    final prior = await _readJson(_receiptPath(id));
    if (prior != null) {
      return prior['digest'] == digest
          ? _receipt(prior)
          : _result(
              InstructionWriteStatus.rejected,
              '操作 ID 已用于其他参数。',
              code: 'operation_mismatch',
            );
    }
    if (canCommit != null && !await canCommit()) return _notAuthorized();
    final before = await _snapshot(allowInvalid: allowInvalidBefore);
    if (before.revision != expected) {
      return _result(
        InstructionWriteStatus.conflict,
        '指令已变化，请重新读取。',
        revision: before.revision,
        code: 'conflict',
      );
    }
    final after = transform(before.markdown);
    if (utf8.encode(after).length > maxBytes) {
      return _result(
        InstructionWriteStatus.rejected,
        'AGENTS.md 不能超过 8 KiB。',
        code: 'too_large',
      );
    }
    if (before.revision == _digestText(after)) {
      final receipt = <String, Object?>{
        'id': id,
        'digest': digest,
        'after_revision': before.revision,
        'changed': false,
      };
      await _writeJson(_receiptPath(id), receipt);
      return _receipt(receipt);
    }
    return _commit(
      id: id,
      digest: digest,
      before: before,
      after: after,
      canUndo: !before.revision.startsWith('invalid:'),
      canCommit: canCommit,
    );
  });

  Future<InstructionWriteResult> _guard(
    Future<InstructionWriteResult> Function() operation,
  ) async {
    try {
      return await _vault.exclusive(() async {
        await _recover();
        return operation();
      });
    } on _InstructionConflict {
      return _result(
        InstructionWriteStatus.conflict,
        '编辑位置不唯一或发生重叠，请重新读取。',
        code: 'conflict',
      );
    } on FormatException {
      return _result(
        InstructionWriteStatus.failed,
        '无法读取指令文件或事务记录。',
        code: 'invalid_file',
      );
    } on Exception {
      return _result(
        InstructionWriteStatus.failed,
        '未能确认指令写入结果，请重新打开设置核对。',
        code: 'write_unverified',
      );
    }
  }

  Future<InstructionWriteResult> _commit({
    required String id,
    required String digest,
    required InstructionSnapshot before,
    required String? after,
    required bool canUndo,
    Future<bool> Function()? canCommit,
  }) async {
    final beforeText = before.revision == 'missing' ? null : before.markdown;
    final diff = _change(beforeText ?? '', after ?? '');
    final state = <String, Object?>{
      'id': id,
      'digest': digest,
      'changed': true,
      'before_revision': before.revision,
      'after_revision': after == null ? 'missing' : _digestText(after),
      if (canUndo) 'before': beforeText,
      if (canUndo) 'undo_until': _clock().add(_undoWindow).toIso8601String(),
      'removed': diff.$1,
      'added': diff.$2,
    };
    await _writeJson(_pending, state);
    if (canCommit != null && !await canCommit()) {
      await _vault.delete(_pending);
      return _notAuthorized();
    }
    if ((await _snapshot(allowInvalid: true)).revision != before.revision) {
      await _vault.delete(_pending);
      return _result(
        InstructionWriteStatus.conflict,
        '指令已变化，请重新读取。',
        code: 'conflict',
      );
    }
    if (after == null) {
      await _vault.delete(path);
    } else {
      await _vault.writeAtomically(path, after);
    }
    if ((await _snapshot()).revision != state['after_revision']) {
      throw const FormatException(
        'Instruction replacement could not be verified',
      );
    }
    await _recordCommitted(state);
    return _receipt(state);
  }

  Future<void> _recover() async {
    final state = await _readJson(_pending);
    if (state != null) {
      final current = (await _snapshot(allowInvalid: true)).revision;
      if (current == state['after_revision']) {
        await _recordCommitted(state);
      } else if (current == state['before_revision']) {
        await _vault.delete(_pending);
      } else {
        throw const FormatException('Unverified instruction write');
      }
    }
    final last = await _readJson(_latest);
    final expiry = last?['undo_until'] as String?;
    if (expiry != null && !_clock().isBefore(DateTime.parse(expiry))) {
      await _writeJson(_latest, {
        'id': last!['id'],
        'after_revision': last['after_revision'],
        'undo_until': expiry,
      });
    }
  }

  Future<void> _recordCommitted(Map<String, Object?> state) async {
    await _writeJson(
      _receiptPath(state['id'] as String),
      {...state}..remove('before'),
    );
    await _writeJson(_latest, state);
    await _vault.delete(_pending);
  }

  Future<InstructionSnapshot> _snapshot({bool allowInvalid = false}) async {
    final bytes = await _vault.readRawBytes(path);
    if (bytes == null) return (markdown: '', revision: 'missing');
    final hash = sha256.convert(bytes).toString();
    try {
      if (bytes.length > maxBytes) {
        throw const FormatException('Instruction size');
      }
      return (markdown: utf8.decode(bytes), revision: hash);
    } on FormatException {
      if (allowInvalid) return (markdown: '', revision: 'invalid:$hash');
      rethrow;
    }
  }

  // Recovery and explicit repair use the hash without exposing damaged bytes.
  Future<String?> repairRevision() => _vault.exclusive(() async {
    final revision = (await _snapshot(allowInvalid: true)).revision;
    return revision.startsWith('invalid:') ? revision : null;
  });

  String _receiptPath(String id) => '$_root/receipts/${_digestText(id)}.json';
  Future<Map<String, Object?>?> _readJson(String path) async {
    final text = await _vault.read(path);
    return text == null
        ? null
        : Map<String, Object?>.from(jsonDecode(text) as Map);
  }

  Future<void> _writeJson(String path, Map<String, Object?> value) =>
      _vault.writeAtomically(path, jsonEncode(value));

  InstructionWriteResult _receipt(Map<String, Object?> value) {
    final changed = value['changed'] == true;
    final rawTime = value['undo_until'] as String?;
    final expires = rawTime == null ? null : DateTime.parse(rawTime);
    return _result(
      changed
          ? InstructionWriteStatus.applied
          : InstructionWriteStatus.unchanged,
      changed ? '秘书指令已保存，下次发送消息时生效。' : '秘书指令没有变化。',
      id: value['id'] as String,
      revision: value['after_revision'] as String,
      undoUntil: expires != null && _clock().isBefore(expires) ? expires : null,
      removed: value['removed'] as String?,
      added: value['added'] as String?,
    );
  }

  static InstructionWriteResult _notAuthorized() => _result(
    InstructionWriteStatus.rejected,
    '当前消息无权改写秘书指令。',
    code: 'not_authorized',
  );

  static InstructionWriteResult _result(
    InstructionWriteStatus status,
    String message, {
    String? id,
    String? revision,
    DateTime? undoUntil,
    String? code,
    String? removed,
    String? added,
  }) => (
    status: status,
    operationId: id,
    revision: revision,
    undoUntil: undoUntil,
    code: code,
    message: message,
    removed: removed,
    added: added,
  );

  static String _digestText(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  static String _applyEdits(String text, List<InstructionEdit> edits) {
    final ranges = <(int, int, String)>[];
    for (var index = 0; index < edits.length; index++) {
      final edit = edits[index];
      final old = edit.oldText;
      if (old == null) {
        if (index != edits.length - 1) throw _InstructionConflict();
        final separator = text.isEmpty || text.endsWith('\n') ? '' : '\n';
        ranges.add((text.length, text.length, '$separator${edit.newText}'));
        continue;
      }
      if (old.isEmpty) throw _InstructionConflict();
      final start = text.indexOf(old);
      if (start < 0 || text.indexOf(old, start + 1) >= 0) {
        throw _InstructionConflict();
      }
      ranges.add((start, start + old.length, edit.newText));
    }
    ranges.sort((a, b) {
      final byStart = a.$1.compareTo(b.$1);
      return byStart != 0 ? byStart : b.$2.compareTo(a.$2);
    });
    final output = StringBuffer();
    var offset = 0;
    for (final range in ranges) {
      if (range.$1 < offset) throw _InstructionConflict();
      output
        ..write(text.substring(offset, range.$1))
        ..write(range.$3);
      offset = range.$2;
    }
    return (output..write(text.substring(offset))).toString();
  }

  static (String, String) _change(String before, String after) {
    final a = before.split('\n'), b = after.split('\n');
    var start = 0, endA = a.length, endB = b.length;
    while (start < endA && start < endB && a[start] == b[start]) {
      start++;
    }
    while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
      endA--;
      endB--;
    }
    return (
      a.sublist(start, endA).join('\n'),
      b.sublist(start, endB).join('\n'),
    );
  }
}

class _InstructionConflict implements Exception {}
