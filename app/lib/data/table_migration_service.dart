import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/markdown_codec.dart';
import '../core/models.dart';
import '../core/table_markdown_codec.dart';
import '../core/table_models.dart';
import 'index_database.dart';
import 'table_repository.dart';
import 'vault_store.dart';

typedef TableMigrationWriteBarrier = Future<TableMigrationReceipt> Function(
  Future<TableMigrationReceipt> Function() operation,
);

/// Plans and copies accepted legacy Markdown into the table format.
///
/// Legacy files are retained. Promotion only adds table-format files and is
/// replayable from its journal; switching application read/write entry points
/// remains a separate, later migration gate.
class TableMigrationService {
  TableMigrationService({
    required VaultStore vault,
    required IndexDatabase index,
    MarkdownCodec legacyCodec = const MarkdownCodec(),
    TableMarkdownCodec tableCodec = const TableMarkdownCodec(),
    DateTime Function()? clock,
    Future<String> Function(String migrationId)? createDatabaseSnapshot,
    Future<int> Function()? estimateDatabaseSnapshotBytes,
    Future<int?> Function(String vaultRoot)? availableSpaceProbe,
    TableMigrationWriteBarrier? runWithWriteBarrier,
  }) : _vault = vault,
       _index = index,
       _legacyCodec = legacyCodec,
       _tableCodec = tableCodec,
       _clock = clock ?? DateTime.now,
       _createDatabaseSnapshot = createDatabaseSnapshot,
       _estimateDatabaseSnapshotBytes = estimateDatabaseSnapshotBytes,
       _availableSpaceProbe = availableSpaceProbe,
       _runWithWriteBarrier = runWithWriteBarrier;

  final VaultStore _vault;
  final IndexDatabase _index;
  final MarkdownCodec _legacyCodec;
  final TableMarkdownCodec _tableCodec;
  final DateTime Function() _clock;
  final Future<String> Function(String migrationId)? _createDatabaseSnapshot;
  final Future<int> Function()? _estimateDatabaseSnapshotBytes;
  final Future<int?> Function(String vaultRoot)? _availableSpaceProbe;
  final TableMigrationWriteBarrier? _runWithWriteBarrier;

  Future<TableMigrationPreview> preview({
    DateTime? now,
    int? availableBytes,
  }) => _vault.exclusive(() async {
    final migrationTime = (now ?? _clock()).toLocal();
    final issues = <TableMigrationIssue>[];
    var measuredAvailableBytes = availableBytes;
    if (measuredAvailableBytes == null && _availableSpaceProbe != null) {
      try {
        measuredAvailableBytes = await _availableSpaceProbe(
          await _vault.describeRoot(),
        );
      } on Object catch (error) {
        issues.add(TableMigrationIssue('vault', '读取磁盘可用空间失败：$error'));
      }
    }
    final allMarkdownPaths =
        (await _vault.listMarkdownFiles())
            .where((path) => !path.startsWith('vault/.table-migrations/'))
            .toList(growable: false)
          ..sort();
    var estimatedBackupBytes = 0;
    for (final path in allMarkdownPaths) {
      final source = await _vault.read(path);
      if (source == null) {
        issues.add(TableMigrationIssue(path, '计算备份空间时源文件消失。'));
      } else {
        estimatedBackupBytes += utf8.encode(source).length;
      }
    }
    final paths = allMarkdownPaths.where(_isLegacyPath).toList(growable: false);
    final documents = <ResultDocument>[];
    final sourceHashes = <String, String>{};
    final seenIds = <String, String>{};
    for (final path in paths) {
      final source = await _vault.read(path);
      if (source == null) {
        issues.add(TableMigrationIssue(path, '源文件在预检期间消失。'));
        continue;
      }
      sourceHashes[path] = _hash(source);
      try {
        final document = _legacyCodec.decode(source);
        if (document.markdownPath != path) {
          issues.add(TableMigrationIssue(path, '文件路径与成果 ID/type 不一致。'));
          continue;
        }
        final priorPath = seenIds[document.id];
        if (priorPath != null) {
          issues.add(
            TableMigrationIssue(path, '成果 ID 与 $priorPath 重复：${document.id}'),
          );
          continue;
        }
        seenIds[document.id] = path;
        documents.add(document);
      } on Object catch (error) {
        issues.add(TableMigrationIssue(path, '旧 Markdown 无法读取：$error'));
      }
    }

    final matterIds = documents
        .where((document) => document.type == ResultType.matter)
        .map((document) => document.id)
        .toSet();
    final tables = <TableDocument>[];
    final entries = <TableEntryDocument>[];
    final skipped = <String>[];
    for (final document in documents) {
      final conflict = await _index.findConflict(document.id);
      if (conflict != null) {
        skipped.add(document.id);
        issues.add(
          TableMigrationIssue(document.markdownPath, '存在未解决同步冲突，保留旧格式。'),
        );
        continue;
      }
      if (document.isGlobalKnowledge) {
        skipped.add(document.id);
        continue;
      }
      if (document.deleted || document.status != ResultStatus.canonical) {
        skipped.add(document.id);
        issues.add(
          TableMigrationIssue(
            document.markdownPath,
            document.deleted ? '已删除成果保留旧格式，不自动恢复或清除。' : '非 canonical 状态保留旧格式。',
          ),
        );
        continue;
      }
      if (document.type == ResultType.event &&
          (document.start == null || !document.start!.isAfter(migrationTime))) {
        skipped.add(document.id);
        issues.add(
          TableMigrationIssue(
            document.markdownPath,
            '旧日历项缺少未来开始时间，不能推断它已发生；需人工判定后再迁移。',
          ),
        );
        continue;
      }
      if (document.type == ResultType.matter) {
        if (_isDefaultTableId(document.id)) {
          issues.add(
            TableMigrationIssue(
              document.markdownPath,
              '旧事项 ID 与默认表保留 ID 冲突：${document.id}',
            ),
          );
          skipped.add(document.id);
          continue;
        }
        tables.add(
          TableDocument(
            id: document.id,
            role: TableRole.custom,
            title: document.title,
            revision: document.revision,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt,
            body: document.body,
          ),
        );
        continue;
      }
      final tableId = _ownerTableId(document, matterIds, issues);
      if (tableId == null) {
        skipped.add(document.id);
        continue;
      }
      final type = switch (document.type) {
        ResultType.matter => throw StateError('Matter is not an entry'),
        ResultType.todo => TableContentType.todo,
        ResultType.event => TableContentType.schedule,
        ResultType.knowledge => TableContentType.note,
      };
      entries.add(
        TableEntryDocument(
          id: document.id,
          type: type,
          tableId: tableId,
          title: document.title,
          revision: document.revision,
          createdAt: document.createdAt,
          updatedAt: document.updatedAt,
          body: document.body,
          tags: document.tags,
          links: document.links,
          due: document.due,
          done: document.done,
          start: type == TableContentType.schedule ? document.start : null,
          end: type == TableContentType.schedule ? document.end : null,
          allDay: type == TableContentType.schedule && document.allDay,
          recurrence: type == TableContentType.schedule
              ? document.recurrence
              : null,
        ),
      );
    }

    final tableById = <String, TableDocument>{
      for (final table in tables) table.id: table,
    };
    for (final entry in entries) {
      if (entry.tableId == 'tb_default_todo' ||
          entry.tableId == 'tb_default_schedule' ||
          entry.tableId == 'tb_default_event') {
        continue;
      }
      if (!tableById.containsKey(entry.tableId)) {
        issues.add(
          TableMigrationIssue(entry.id, '关联表不存在或不可迁移：${entry.tableId}'),
        );
        skipped.add(entry.id);
      }
    }
    entries.removeWhere((entry) => skipped.contains(entry.id));

    final outputs = <String, String>{};
    try {
      for (final table in tables) {
        outputs[TableRepository.tablePath(table.id)] = _tableCodec.encodeTable(
          table,
        );
      }
      for (final entry in entries) {
        final table = tableById[entry.tableId];
        if (table == null && !_isDefaultTableId(entry.tableId)) {
          continue;
        }
        outputs[TableRepository.entryPath(entry.id)] = _tableCodec.encodeEntry(
          entry,
          fields: table?.fields ?? const [],
        );
      }
    } on Object catch (error) {
      issues.add(TableMigrationIssue('vault', '目标数据不满足表 schema：$error'));
      outputs.clear();
    }
    final sourceDigest = sourceHashes.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join('\n');
    final outputDigest = outputs.entries
        .map((entry) => '${entry.key}:${_hash(entry.value)}')
        .join('\n');
    final migrationId =
        'tm_${_hash('$sourceDigest\n$outputDigest').substring(0, 24)}';
    final legacyRecords = documents
        .map(
          (document) => LegacyMigrationRecord(
            id: document.id,
            type: document.type,
            title: document.title,
            body: document.body,
            status: document.status,
            deleted: document.deleted,
            sourcePath: document.markdownPath,
          ),
        )
        .toList(growable: false);
    final hasLegacyContent =
        documents.any((document) => !document.isGlobalKnowledge) ||
        paths.length > documents.length;
    for (final output in outputs.entries) {
      final existing = await _vault.read(output.key);
      if (existing != null &&
          !await _journalOwnsTarget(migrationId, output.key, existing)) {
        issues.add(
          TableMigrationIssue(output.key, '迁移目标路径已存在且不属于本次可重放事务，禁止覆盖。'),
        );
      }
    }
    final estimatedOutputBytes = outputs.values.fold<int>(
      0,
      (sum, markdown) => sum + utf8.encode(markdown).length,
    );
    int? estimatedDatabaseBackupBytes;
    final estimateDatabaseSnapshotBytes = _estimateDatabaseSnapshotBytes;
    if (estimateDatabaseSnapshotBytes == null) {
      issues.add(
        const TableMigrationIssue('databases', '数据库快照空间估算未接入，拒绝执行迁移。'),
      );
    } else {
      try {
        estimatedDatabaseBackupBytes = await estimateDatabaseSnapshotBytes();
        if (estimatedDatabaseBackupBytes < 0) {
          throw StateError('数据库快照空间估算为负数。');
        }
      } on Object catch (error) {
        issues.add(TableMigrationIssue('databases', '数据库快照空间估算失败：$error'));
      }
    }
    final estimatedRequiredBytes =
        estimatedBackupBytes +
        estimatedOutputBytes * 2 +
        (estimatedDatabaseBackupBytes ?? 0) +
        4096;
    if (measuredAvailableBytes == null) {
      issues.add(
        const TableMigrationIssue('vault', '未提供 vault 可用磁盘空间读数，拒绝执行迁移。'),
      );
    } else if (measuredAvailableBytes < estimatedRequiredBytes) {
      issues.add(
        TableMigrationIssue(
          'vault',
          '可用空间不足：预计需要 $estimatedRequiredBytes bytes，当前 $measuredAvailableBytes bytes。',
        ),
      );
    }
    if (_createDatabaseSnapshot == null) {
      issues.add(
        const TableMigrationIssue('databases', '数据库、会话与设置备份回调未接入，拒绝执行迁移。'),
      );
    }
    if (_runWithWriteBarrier == null) {
      issues.add(const TableMigrationIssue('runtime', '应用级写暂停门未接入，拒绝执行迁移。'));
    }
    return TableMigrationPreview._(
      migrationId: migrationId,
      sourceHashes: Map.unmodifiable(sourceHashes),
      legacyRecords: List.unmodifiable(legacyRecords),
      hasLegacyContent: hasLegacyContent,
      tables: List.unmodifiable(tables),
      entries: List.unmodifiable(entries),
      outputs: Map.unmodifiable(outputs),
      issues: List.unmodifiable(issues),
      retainedGlobalKnowledgeIds: List.unmodifiable(
        documents
            .where((document) => document.isGlobalKnowledge)
            .map((document) => document.id),
      ),
      skippedIds: List.unmodifiable(skipped.toSet()),
      estimatedBackupBytes: estimatedBackupBytes,
      estimatedOutputBytes: estimatedOutputBytes,
      estimatedDatabaseBackupBytes: estimatedDatabaseBackupBytes,
      estimatedRequiredBytes: estimatedRequiredBytes,
      availableBytes: measuredAvailableBytes,
    );
  });

  Future<TableMigrationReceipt> apply(TableMigrationPreview plan) async {
    if (!plan.canApply) throw StateError('迁移预检存在阻断项，拒绝写入。');
    final runWithWriteBarrier = _runWithWriteBarrier;
    if (runWithWriteBarrier == null) {
      throw StateError('应用级写暂停门未接入，拒绝迁移。');
    }
    return runWithWriteBarrier(
      () => _vault.exclusive(() async {
        final createDatabaseSnapshot = _createDatabaseSnapshot;
        if (createDatabaseSnapshot == null) {
          throw StateError('数据库、会话与设置备份未接入，拒绝迁移。');
        }
        final journalPath = _journalPath(plan.migrationId);
        final journalSource = await _vault.read(journalPath);
        if (journalSource != null) {
          final journal = _decodeJournal(journalSource, plan.migrationId);
          if (journal['status'] == 'complete') {
            for (final output in plan.outputs.entries) {
              final current = await _vault.read(output.key);
              if (current == null || _hash(current) != _hash(output.value)) {
                throw StateError('已完成迁移目标发生变化：${output.key}');
              }
            }
            return TableMigrationReceipt.fromJournal(journal);
          }
        }
        for (final source in plan.sourceHashes.entries) {
          final current = await _vault.read(source.key);
          if (current == null || _hash(current) != source.value) {
            throw StateError('旧资料在预检后发生变化：${source.key}');
          }
        }
        final expected = plan.outputs.map(
          (path, markdown) => MapEntry(path, _hash(markdown)),
        );
        final backup = await _createBackupUnlocked(plan.migrationId);
        final databaseBackup = await createDatabaseSnapshot(plan.migrationId);
        final journal = <String, Object?>{
          'schema_version': 1,
          'migration_id': plan.migrationId,
          'status': 'prepared',
          'backup_manifest': backup,
          'database_backup_manifest': databaseBackup,
          'targets': expected,
        };
        await _vault.write(journalPath, jsonEncode(journal));
        for (final output in plan.outputs.entries) {
          final stagedPath = _stagedPath(plan.migrationId, output.key);
          await _vault.write(stagedPath, output.value);
          final staged = await _vault.read(stagedPath);
          if (staged == null || _hash(staged) != expected[output.key]) {
            throw StateError('迁移暂存校验失败：${output.key}');
          }
          _verifyTarget(output.key, staged);
        }
        journal['status'] = 'promoting';
        await _vault.write(journalPath, jsonEncode(journal));
        for (final output in plan.outputs.entries) {
          final existing = await _vault.read(output.key);
          if (existing != null) {
            if (_hash(existing) != expected[output.key]) {
              throw StateError('迁移目标被并发修改：${output.key}');
            }
          } else {
            await _vault.write(output.key, output.value);
          }
        }
        journal['status'] = 'complete';
        journal['completed_at'] = DateTime.now().toIso8601String();
        await _vault.write(journalPath, jsonEncode(journal));
        return TableMigrationReceipt.fromJournal(journal);
      }),
    );
  }

  Future<TableMigrationReceipt?> completedReceipt(TableMigrationPreview plan) =>
      _vault.exclusive(() async {
        final source = await _vault.read(_journalPath(plan.migrationId));
        if (source == null) return null;
        final journal = _decodeJournal(source, plan.migrationId);
        if (journal['status'] != 'complete') return null;
        for (final output in plan.outputs.entries) {
          final current = await _vault.read(output.key);
          if (current == null || _hash(current) != _hash(output.value)) {
            throw StateError('迁移完成目标与预检不一致：${output.key}');
          }
        }
        return TableMigrationReceipt.fromJournal(journal);
      });

  Future<void> rollback(String migrationId) => _vault.exclusive(() async {
    final path = _journalPath(migrationId);
    final source = await _vault.read(path);
    if (source == null) throw StateError('迁移记录不存在：$migrationId');
    final journal = _decodeJournal(source, migrationId);
    final targets = journal['targets'];
    if (targets is! Map<String, dynamic>) throw StateError('迁移目标清单损坏。');
    for (final entry in targets.entries) {
      final current = await _vault.read(entry.key);
      if (current == null) continue;
      if (_hash(current) != entry.value) {
        throw StateError('回滚目标已被修改，停止删除：${entry.key}');
      }
      await _vault.delete(entry.key);
    }
    for (final target in targets.keys) {
      await _vault.delete(_stagedPath(migrationId, target));
    }
    journal['status'] = 'rolled_back';
    journal['rolled_back_at'] = DateTime.now().toIso8601String();
    await _vault.write(path, jsonEncode(journal));
  });

  Future<String> _createBackupUnlocked(String migrationId) async {
    final manifestPath =
        'vault/.table-migrations/backups/$migrationId/manifest.json';
    final priorManifest = await _vault.read(manifestPath);
    if (priorManifest != null) {
      final decoded = jsonDecode(priorManifest);
      if (decoded is! Map<String, dynamic> ||
          decoded['migration_id'] != migrationId ||
          decoded['files'] is! Map<String, dynamic>) {
        throw StateError('既有迁移备份清单损坏：$migrationId');
      }
      final files = decoded['files'] as Map<String, dynamic>;
      for (final source in files.entries) {
        final backupPath =
            'vault/.table-migrations/backups/$migrationId/${source.key}';
        final backup = await _vault.read(backupPath);
        if (backup == null || _hash(backup) != source.value) {
          throw StateError('既有迁移备份校验失败：$backupPath');
        }
      }
      return manifestPath;
    }
    final paths =
        (await _vault.listMarkdownFiles())
            .where((path) => !path.startsWith('vault/.table-migrations/'))
            .toList(growable: false)
          ..sort();
    final files = <String, String>{};
    for (final path in paths) {
      final source = await _vault.read(path);
      if (source == null) throw StateError('备份期间源文件消失：$path');
      final backupPath = 'vault/.table-migrations/backups/$migrationId/$path';
      final existing = await _vault.read(backupPath);
      if (existing != null && existing != source) {
        throw StateError('备份路径已存在不同内容：$backupPath');
      }
      if (existing == null) await _vault.write(backupPath, source);
      final copied = await _vault.read(backupPath);
      if (copied == null || _hash(copied) != _hash(source)) {
        throw StateError('备份校验失败：$path');
      }
      files[path] = _hash(source);
    }
    final manifest = jsonEncode({
      'schema_version': 1,
      'migration_id': migrationId,
      'files': files,
    });
    await _vault.write(manifestPath, manifest);
    return manifestPath;
  }

  Future<bool> _journalOwnsTarget(
    String migrationId,
    String path,
    String contents,
  ) async {
    final source = await _vault.read(_journalPath(migrationId));
    if (source == null) return false;
    final journal = _decodeJournal(source, migrationId);
    if (!const {
      'prepared',
      'promoting',
      'complete',
    }.contains(journal['status'])) {
      return false;
    }
    final targets = journal['targets'];
    return targets is Map<String, dynamic> && targets[path] == _hash(contents);
  }

  void _verifyTarget(String path, String source) {
    if (path.startsWith('vault/tables/')) {
      final document = _tableCodec.decodeTable(source);
      if (TableRepository.tablePath(document.id) != path) {
        throw StateError('迁移表 ID/path 不一致：$path');
      }
    } else {
      final document = _tableCodec.decodeEntry(source);
      if (TableRepository.entryPath(document.id) != path) {
        throw StateError('迁移内容 ID/path 不一致：$path');
      }
    }
  }

  Map<String, dynamic> _decodeJournal(String source, String id) {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic> ||
        value['schema_version'] != 1 ||
        value['migration_id'] != id ||
        !const {
          'prepared',
          'promoting',
          'complete',
          'rolled_back',
        }.contains(value['status'])) {
      throw StateError('迁移记录损坏或版本不兼容：$id');
    }
    return value;
  }

  String? _ownerTableId(
    ResultDocument document,
    Set<String> matterIds,
    List<TableMigrationIssue> issues,
  ) {
    switch (document.type) {
      case ResultType.matter:
        return null;
      case ResultType.todo:
      case ResultType.event:
        final matterId = document.matterId;
        if (matterId == null) {
          return switch (document.type) {
            ResultType.todo => 'tb_default_todo',
            ResultType.event => 'tb_default_schedule',
            _ => throw StateError('Unreachable result type'),
          };
        }
        if (!matterIds.contains(matterId)) {
          issues.add(
            TableMigrationIssue(document.markdownPath, '关联事项不存在：$matterId'),
          );
          return null;
        }
        return matterId;
      case ResultType.knowledge:
        final linkedMatters = document.links.where(matterIds.contains).toSet();
        return linkedMatters.length == 1
            ? linkedMatters.single
            : 'tb_default_event';
    }
  }

  bool _isLegacyPath(String path) => const {
    'vault/matters/',
    'vault/todos/',
    'vault/calendar/',
    'vault/knowledge/',
  }.any(path.startsWith);

  bool _isDefaultTableId(String id) =>
      TableRepository.defaultTables.any((table) => table.$1 == id);

  String _journalPath(String id) {
    if (!RegExp(r'^tm_[a-f0-9]{24}$').hasMatch(id)) {
      throw ArgumentError.value(id, 'migrationId');
    }
    return 'vault/.table-migrations/$id.json';
  }

  String _stagedPath(String id, String target) =>
      'vault/.table-migrations/staging/$id/${target.split('/').last}';

  String _hash(String source) => sha256.convert(utf8.encode(source)).toString();
}

class TableMigrationIssue {
  const TableMigrationIssue(this.path, this.message);

  final String path;
  final String message;
}

class LegacyMigrationRecord {
  const LegacyMigrationRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.status,
    required this.deleted,
    required this.sourcePath,
  });

  final String id;
  final ResultType type;
  final String title;
  final String body;
  final ResultStatus status;
  final bool deleted;
  final String sourcePath;
}

class TableMigrationPreview {
  const TableMigrationPreview._({
    required this.migrationId,
    required this.sourceHashes,
    required this.legacyRecords,
    required this.hasLegacyContent,
    required this.tables,
    required this.entries,
    required this.outputs,
    required this.issues,
    required this.retainedGlobalKnowledgeIds,
    required this.skippedIds,
    required this.estimatedBackupBytes,
    required this.estimatedOutputBytes,
    required this.estimatedDatabaseBackupBytes,
    required this.estimatedRequiredBytes,
    required this.availableBytes,
  });

  final String migrationId;
  final Map<String, String> sourceHashes;
  final List<LegacyMigrationRecord> legacyRecords;
  final bool hasLegacyContent;
  final List<TableDocument> tables;
  final List<TableEntryDocument> entries;
  final Map<String, String> outputs;
  final List<TableMigrationIssue> issues;
  final List<String> retainedGlobalKnowledgeIds;
  final List<String> skippedIds;
  final int estimatedBackupBytes;
  final int estimatedOutputBytes;
  final int? estimatedDatabaseBackupBytes;
  final int estimatedRequiredBytes;
  final int? availableBytes;

  bool get canApply => issues.isEmpty && availableBytes != null;
}

class TableMigrationReceipt {
  const TableMigrationReceipt({
    required this.migrationId,
    required this.status,
    required this.targets,
    required this.backupManifestPath,
    required this.databaseBackupManifestPath,
  });

  final String migrationId;
  final String status;
  final Map<String, dynamic> targets;
  final String backupManifestPath;
  final String databaseBackupManifestPath;

  factory TableMigrationReceipt.fromJournal(Map<String, dynamic> journal) {
    final targets = journal['targets'];
    final backup = journal['backup_manifest'];
    final databaseBackup = journal['database_backup_manifest'];
    if (targets is! Map<String, dynamic> ||
        backup is! String ||
        databaseBackup is! String) {
      throw StateError('迁移完成记录缺少校验材料。');
    }
    return TableMigrationReceipt(
      migrationId: journal['migration_id'] as String,
      status: journal['status'] as String,
      targets: Map.unmodifiable(targets),
      backupManifestPath: backup,
      databaseBackupManifestPath: databaseBackup,
    );
  }
}
