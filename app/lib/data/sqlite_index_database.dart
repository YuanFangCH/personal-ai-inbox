import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../core/models.dart';
import 'index_database.dart';

class SqliteIndexDatabase implements IndexDatabase {
  SqliteIndexDatabase(this.path);

  final String path;
  late final Database _database;

  @override
  Future<void> open() async {
    final parent = Directory(p.dirname(path));
    await parent.create(recursive: true);
    _database = sqlite3.open(path);
    _database
      ..execute('PRAGMA journal_mode = WAL')
      ..execute('PRAGMA foreign_keys = ON')
      ..execute('''
        CREATE TABLE IF NOT EXISTS objects (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          title TEXT NOT NULL,
          status TEXT NOT NULL,
          revision INTEGER NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL,
          md_path TEXT NOT NULL,
          local_hash TEXT NOT NULL,
          last_synced_hash TEXT,
          remote_etag TEXT,
          matter_id TEXT,
          sync_state TEXT NOT NULL
        )
      ''')
      ..execute('''
        CREATE TABLE IF NOT EXISTS captures (
          id TEXT PRIMARY KEY,
          device_id TEXT NOT NULL,
          captured_at TEXT NOT NULL,
          source_type TEXT NOT NULL,
          text TEXT NOT NULL,
          status TEXT NOT NULL,
          result_id TEXT,
          candidate_type TEXT,
          candidate_title TEXT,
          candidate_at TEXT,
          confidence REAL,
          review_reason TEXT
        )
      ''');
  }

  @override
  Future<void> close() async {
    _database.close();
  }

  @override
  Future<void> upsertResult(IndexedResult result) async {
    _database.execute(
      '''
      INSERT INTO objects (
        id, type, title, status, revision, updated_at, deleted, md_path,
        local_hash, last_synced_hash, remote_etag, matter_id, sync_state
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        type = excluded.type,
        title = excluded.title,
        status = excluded.status,
        revision = excluded.revision,
        updated_at = excluded.updated_at,
        deleted = excluded.deleted,
        md_path = excluded.md_path,
        local_hash = excluded.local_hash,
        last_synced_hash = excluded.last_synced_hash,
        remote_etag = excluded.remote_etag,
        matter_id = excluded.matter_id,
        sync_state = excluded.sync_state
      ''',
      [
        result.id,
        result.type.wireName,
        result.title,
        result.status.wireName,
        result.revision,
        result.updatedAt.toIso8601String(),
        result.deleted ? 1 : 0,
        result.mdPath,
        result.localHash,
        result.lastSyncedHash,
        result.remoteEtag,
        result.matterId,
        result.syncState.name,
      ],
    );
  }

  @override
  Future<void> removeResult(String id) async {
    _database.execute('DELETE FROM objects WHERE id = ?', [id]);
  }

  @override
  Future<List<IndexedResult>> listResults() async {
    final rows = _database.select(
      'SELECT * FROM objects ORDER BY updated_at DESC',
    );
    return rows.map(_resultFromRow).toList(growable: false);
  }

  @override
  Future<IndexedResult?> findResult(String id) async {
    final rows = _database.select('SELECT * FROM objects WHERE id = ?', [id]);
    if (rows.isEmpty) {
      return null;
    }
    return _resultFromRow(rows.first);
  }

  @override
  Future<void> replaceResults(List<IndexedResult> results) async {
    _database.execute('BEGIN');
    try {
      _database.execute('DELETE FROM objects');
      for (final result in results) {
        await upsertResult(result);
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> insertCapture(CaptureRecord capture) async {
    await updateCapture(capture);
  }

  @override
  Future<void> updateCapture(CaptureRecord capture) async {
    _database.execute(
      '''
      INSERT INTO captures (
        id, device_id, captured_at, source_type, text, status, result_id,
        candidate_type, candidate_title, candidate_at, confidence, review_reason
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        status = excluded.status,
        result_id = excluded.result_id,
        candidate_type = excluded.candidate_type,
        candidate_title = excluded.candidate_title,
        candidate_at = excluded.candidate_at,
        confidence = excluded.confidence,
        review_reason = excluded.review_reason
      ''',
      [
        capture.id,
        capture.deviceId,
        capture.capturedAt.toIso8601String(),
        capture.sourceType.wireName,
        capture.text,
        capture.status.wireName,
        capture.resultId,
        capture.candidateType?.wireName,
        capture.candidateTitle,
        capture.candidateAt?.toIso8601String(),
        capture.confidence,
        capture.reviewReason,
      ],
    );
  }

  @override
  Future<List<CaptureRecord>> listCaptures({bool reviewOnly = false}) async {
    final rows = reviewOnly
        ? _database.select(
            'SELECT * FROM captures WHERE status = ? ORDER BY captured_at DESC',
            [CaptureStatus.needsReview.wireName],
          )
        : _database.select('SELECT * FROM captures ORDER BY captured_at DESC');
    return rows.map(_captureFromRow).toList(growable: false);
  }

  @override
  Future<void> deleteCapture(String id) async {
    _database.execute('DELETE FROM captures WHERE id = ?', [id]);
  }

  @override
  Future<void> clear() async {
    _database
      ..execute('DELETE FROM objects')
      ..execute('DELETE FROM captures');
  }

  IndexedResult _resultFromRow(Row row) {
    return IndexedResult(
      id: row['id'] as String,
      type: ResultType.parse(row['type'] as String),
      title: row['title'] as String,
      status: ResultStatus.parse(row['status'] as String),
      revision: row['revision'] as int,
      updatedAt: DateTime.parse(row['updated_at'] as String),
      deleted: row['deleted'] == 1,
      mdPath: row['md_path'] as String,
      localHash: row['local_hash'] as String,
      lastSyncedHash: row['last_synced_hash'] as String?,
      remoteEtag: row['remote_etag'] as String?,
      matterId: row['matter_id'] as String?,
      syncState: SyncState.values.firstWhere(
        (state) => state.name == row['sync_state'],
        orElse: () => SyncState.pendingUpload,
      ),
    );
  }

  CaptureRecord _captureFromRow(Row row) {
    final candidateType = row['candidate_type'] as String?;
    final candidateAt = row['candidate_at'] as String?;
    return CaptureRecord(
      id: row['id'] as String,
      deviceId: row['device_id'] as String,
      capturedAt: DateTime.parse(row['captured_at'] as String),
      sourceType: CaptureSourceType.parse(row['source_type'] as String),
      text: row['text'] as String,
      status: CaptureStatus.parse(row['status'] as String),
      resultId: row['result_id'] as String?,
      candidateType: candidateType == null
          ? null
          : ResultType.parse(candidateType),
      candidateTitle: row['candidate_title'] as String?,
      candidateAt: candidateAt == null ? null : DateTime.tryParse(candidateAt),
      confidence: (row['confidence'] as num?)?.toDouble(),
      reviewReason: row['review_reason'] as String?,
    );
  }
}
