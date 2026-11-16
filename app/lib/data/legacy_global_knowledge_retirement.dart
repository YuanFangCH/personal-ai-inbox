import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../modules/results/result_library.dart';
import 'vault_store.dart';

typedef LegacyKnowledgePreview = ({
  int documents,
  int candidates,
  int conflicts,
  String revision,
});

/// Archives old global-knowledge inputs on this device after explicit review.
class LegacyGlobalKnowledgeRetirement {
  LegacyGlobalKnowledgeRetirement(this._vault, this._results);

  static const _archivePath =
      '.local/global-knowledge-retirement/v1/archive.zip.base64';
  final VaultStore _vault;
  final ResultLibrary _results;

  Future<LegacyKnowledgePreview> preview() async {
    final docs = _results.documents.where((d) => d.isGlobalKnowledge).toList();
    final candidates = _results.globalKnowledgeCandidates;
    final internal = resultLibraryInternal(_results);
    final conflicts = await internal.listConflictFiles();
    final selectedConflicts = <List<String>>[];
    for (final path in conflicts) {
      final source = await internal.readRaw(path);
      if (source == null) continue;
      if (_relatesToLegacy(source)) {
        selectedConflicts.add([
          path,
          sha256.convert(utf8.encode(source)).toString(),
        ]);
      }
    }
    final documentSources = <List<Object?>>[];
    for (final document in docs) {
      final source = await internal.readRaw(document.markdownPath);
      documentSources.add([
        document.id,
        document.revision,
        document.deleted,
        source == null ? null : sha256.convert(utf8.encode(source)).toString(),
      ]);
    }
    final content = <String, Object?>{
      'documents': documentSources,
      'candidates': [
        for (final c in candidates) [c.id, c.digest, c.status.name],
      ],
      'conflicts': selectedConflicts,
    };
    return (
      documents: docs.length,
      candidates: candidates.length,
      conflicts: selectedConflicts.length,
      revision: sha256.convert(utf8.encode(jsonEncode(content))).toString(),
    );
  }

  Future<bool> isArchived() async => await _vault.read(_archivePath) != null;

  Future<List<int>?> exportArchive() async {
    final encoded = await _vault.read(_archivePath);
    return encoded == null ? null : base64Decode(encoded);
  }

  Future<void> archive({required String expectedRevision}) async {
    final priorArchive = await exportArchive();
    if (priorArchive != null) {
      await _resumeCleanup(priorArchive);
      return;
    }
    final current = await preview();
    if (current.revision != expectedRevision) {
      throw StateError('全局知识在确认后发生变化，请重新检查归档预览。');
    }
    final archive = Archive();
    final files = <String, String>{};
    final internal = resultLibraryInternal(_results);
    for (final document in _results.documents.where(
      (d) => d.isGlobalKnowledge,
    )) {
      final path = document.markdownPath;
      final text = await internal.readRaw(path);
      if (text == null) throw StateError('归档源文件缺失：$path');
      files[path] = sha256.convert(utf8.encode(text)).toString();
      archive.addFile(
        ArchiveFile(path, utf8.encode(text).length, utf8.encode(text)),
      );
    }
    final candidates = jsonEncode([
      for (final c in _results.globalKnowledgeCandidates)
        {
          'id': c.id,
          'digest': c.digest,
          'status': c.status.name,
          'proposal': c.proposal,
          'target_id': c.targetId,
        },
    ]);
    files['candidates.json'] = sha256
        .convert(utf8.encode(candidates))
        .toString();
    archive.addFile(
      ArchiveFile(
        'candidates.json',
        utf8.encode(candidates).length,
        utf8.encode(candidates),
      ),
    );
    for (final path in await internal.listConflictFiles()) {
      final text = await internal.readRaw(path);
      if (text == null) continue;
      if (!_relatesToLegacy(text)) continue;
      files[path] = sha256.convert(utf8.encode(text)).toString();
      archive.addFile(
        ArchiveFile(path, utf8.encode(text).length, utf8.encode(text)),
      );
    }
    final documentIds = <String, String>{
      for (final d in _results.documents.where((d) => d.isGlobalKnowledge))
        d.markdownPath: d.id,
    };
    final manifest = jsonEncode({
      'schema_version': 1,
      'source_hashes': files,
      'document_ids': documentIds,
    });
    archive.addFile(
      ArchiveFile(
        'manifest.json',
        utf8.encode(manifest).length,
        utf8.encode(manifest),
      ),
    );
    final bytes = ZipEncoder().encode(archive);
    final verified = ZipDecoder().decodeBytes(bytes);
    if (verified.files.length != files.length + 1) {
      throw StateError('ZIP 归档校验失败。');
    }
    for (final entry in verified.files.where(
      (file) => file.name != 'manifest.json',
    )) {
      final expected = files[entry.name];
      if (expected == null ||
          sha256.convert(entry.content as List<int>).toString() != expected) {
        throw StateError('归档条目校验失败：${entry.name}');
      }
    }
    if ((await preview()).revision != expectedRevision) {
      throw StateError('全局知识在生成归档时发生变化，请重新检查归档预览。');
    }
    await _vault.writeAtomically(_archivePath, base64Encode(bytes));
    final stored = await exportArchive();
    if (stored == null || stored.length != bytes.length) {
      throw StateError('本地归档保存校验失败。');
    }
    await _resumeCleanup(bytes);
  }

  Future<void> _resumeCleanup(List<int> bytes) async {
    final zip = ZipDecoder().decodeBytes(bytes);
    final manifestFile = zip.files
        .where((f) => f.name == 'manifest.json')
        .firstOrNull;
    if (manifestFile == null) throw StateError('归档缺少清单。');
    final manifest =
        jsonDecode(utf8.decode(manifestFile.content as List<int>)) as Map;
    if (manifest['schema_version'] != 1 ||
        manifest['source_hashes'] is! Map ||
        manifest['document_ids'] is! Map) {
      throw StateError('归档清单格式无效。');
    }
    final rawHashes = manifest['source_hashes'] as Map;
    final rawIds = manifest['document_ids'] as Map;
    final entries = {for (final file in zip.files) file.name: file};
    if (entries.length != zip.files.length ||
        entries.length != rawHashes.length + 1) {
      throw StateError('归档条目集合与清单不一致。');
    }
    for (final entry in rawHashes.entries) {
      final path = entry.key;
      final expectedHash = entry.value;
      final file = entries[path];
      if (path is! String ||
          expectedHash is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedHash) ||
          file == null ||
          sha256.convert(file.content as List<int>).toString() !=
              expectedHash) {
        throw StateError('归档条目校验失败：$path');
      }
    }
    if (rawIds.keys.any((path) => !rawHashes.containsKey(path))) {
      throw StateError('归档文档 ID 与源文件清单不一致。');
    }
    final candidatesFile = zip.files
        .where((f) => f.name == 'candidates.json')
        .firstOrNull;
    if (candidatesFile == null || !rawHashes.containsKey('candidates.json')) {
      throw StateError('归档缺少候选清单。');
    }
    final candidates =
        jsonDecode(utf8.decode(candidatesFile.content as List<int>)) as List;
    await _results.purgeArchivedGlobalKnowledge(
      documentHashes: {
        for (final e in rawHashes.entries)
          if (rawIds.containsKey(e.key)) e.key.toString(): e.value.toString(),
      },
      documentIds: {
        for (final e in rawIds.entries) e.key.toString(): e.value.toString(),
      },
      candidateSnapshots: {
        for (final rawCandidate in candidates)
          if (rawCandidate is Map)
            rawCandidate['id'].toString(): (
              digest: rawCandidate['digest'].toString(),
              status: rawCandidate['status'].toString(),
            ),
      },
      conflictHashes: {
        for (final e in rawHashes.entries)
          if (e.key.toString().startsWith('vault/conflicts/'))
            e.key.toString(): e.value.toString(),
      },
    );
  }

  bool _relatesToLegacy(String text) =>
      _results.documents.any(
        (d) => d.isGlobalKnowledge && text.contains(d.id),
      ) ||
      _results.globalKnowledgeCandidates.any(
        (c) =>
            text.contains(c.id) ||
            (c.targetId != null && text.contains(c.targetId!)),
      );
}
