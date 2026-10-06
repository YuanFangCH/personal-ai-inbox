import 'package:flutter/material.dart';

enum ResultType {
  matter('matter', '事项', Icons.account_tree_outlined),
  todo('todo', '待办', Icons.check_circle_outline),
  event('event', '事件', Icons.event_outlined),
  knowledge('knowledge', '知识', Icons.menu_book_outlined);

  const ResultType(this.wireName, this.label, this.icon);

  final String wireName;
  final String label;
  final IconData icon;

  String get directory => switch (this) {
    ResultType.matter => 'matters',
    ResultType.todo => 'todos',
    ResultType.event => 'calendar',
    ResultType.knowledge => 'knowledge',
  };

  static ResultType parse(String value) {
    return ResultType.values.firstWhere(
      (type) => type.wireName == value,
      orElse: () => throw FormatException('Unsupported result type: $value'),
    );
  }
}

enum ResultStatus {
  draft('draft', '草稿'),
  reviewed('reviewed', '已复核'),
  canonical('canonical', '定稿');

  const ResultStatus(this.wireName, this.label);

  final String wireName;
  final String label;

  static ResultStatus parse(String value) {
    return ResultStatus.values.firstWhere(
      (status) => status.wireName == value,
      orElse: () => ResultStatus.draft,
    );
  }
}

enum SyncState {
  synced('已同步'),
  pendingUpload('待上传'),
  pendingDownload('待下载'),
  conflict('冲突'),
  deleted('已删除');

  const SyncState(this.label);

  final String label;
}

enum CaptureSourceType {
  text('text', '文本'),
  image('image', '图片'),
  url('url', '链接'),
  file('file', '文件');

  const CaptureSourceType(this.wireName, this.label);

  final String wireName;
  final String label;

  static CaptureSourceType parse(String value) {
    return CaptureSourceType.values.firstWhere(
      (source) => source.wireName == value,
      orElse: () => CaptureSourceType.text,
    );
  }
}

enum CaptureStatus {
  queued('queued'),
  processing('processing'),
  accepted('accepted'),
  needsReview('needs_review'),
  failed('failed');

  const CaptureStatus(this.wireName);

  final String wireName;

  static CaptureStatus parse(String value) {
    return CaptureStatus.values.firstWhere(
      (status) => status.wireName == value,
      orElse: () => CaptureStatus.queued,
    );
  }
}

class ResultDocument {
  const ResultDocument({
    required this.id,
    required this.type,
    required this.title,
    required this.status,
    required this.originDevice,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    required this.body,
    this.deleted = false,
    this.tags = const [],
    this.links = const [],
    this.due,
    this.done = false,
    this.matterId,
    this.start,
    this.end,
    this.allDay = false,
    this.recurrence,
    this.sourceEventIds = const [],
    this.sourceHashes = const [],
  });

  final String id;
  final ResultType type;
  final String title;
  final ResultStatus status;
  final String originDevice;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;
  final List<String> tags;
  final List<String> links;
  final String body;
  final DateTime? due;
  final bool done;
  final String? matterId;
  final DateTime? start;
  final DateTime? end;
  final bool allDay;
  final String? recurrence;
  final List<String> sourceEventIds;
  final List<String> sourceHashes;

  String get markdownPath => 'vault/${type.directory}/$id.md';

  bool get isActionable => type == ResultType.todo || type == ResultType.event;

  bool get isInboxItem => status == ResultStatus.draft;

  ResultDocument copyWith({
    String? id,
    ResultType? type,
    String? title,
    ResultStatus? status,
    String? originDevice,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? deleted,
    List<String>? tags,
    List<String>? links,
    String? body,
    Object? due = _unset,
    bool? done,
    Object? matterId = _unset,
    Object? start = _unset,
    Object? end = _unset,
    bool? allDay,
    Object? recurrence = _unset,
    List<String>? sourceEventIds,
    List<String>? sourceHashes,
  }) {
    return ResultDocument(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      status: status ?? this.status,
      originDevice: originDevice ?? this.originDevice,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      tags: tags ?? this.tags,
      links: links ?? this.links,
      body: body ?? this.body,
      due: identical(due, _unset) ? this.due : due as DateTime?,
      done: done ?? this.done,
      matterId: identical(matterId, _unset)
          ? this.matterId
          : matterId as String?,
      start: identical(start, _unset) ? this.start : start as DateTime?,
      end: identical(end, _unset) ? this.end : end as DateTime?,
      allDay: allDay ?? this.allDay,
      recurrence: identical(recurrence, _unset)
          ? this.recurrence
          : recurrence as String?,
      sourceEventIds: sourceEventIds ?? this.sourceEventIds,
      sourceHashes: sourceHashes ?? this.sourceHashes,
    );
  }
}

const Object _unset = Object();

class CaptureRecord {
  const CaptureRecord({
    required this.id,
    required this.deviceId,
    required this.capturedAt,
    required this.sourceType,
    required this.text,
    required this.status,
    this.resultId,
    this.candidateType,
    this.candidateTitle,
    this.candidateAt,
    this.confidence,
    this.reviewReason,
  });

  final String id;
  final String deviceId;
  final DateTime capturedAt;
  final CaptureSourceType sourceType;
  final String text;
  final CaptureStatus status;
  final String? resultId;
  final ResultType? candidateType;
  final String? candidateTitle;
  final DateTime? candidateAt;
  final double? confidence;
  final String? reviewReason;

  CaptureRecord copyWith({
    CaptureStatus? status,
    String? resultId,
    ResultType? candidateType,
    String? candidateTitle,
    Object? candidateAt = _unset,
    double? confidence,
    String? reviewReason,
  }) {
    return CaptureRecord(
      id: id,
      deviceId: deviceId,
      capturedAt: capturedAt,
      sourceType: sourceType,
      text: text,
      status: status ?? this.status,
      resultId: resultId ?? this.resultId,
      candidateType: candidateType ?? this.candidateType,
      candidateTitle: candidateTitle ?? this.candidateTitle,
      candidateAt: identical(candidateAt, _unset)
          ? this.candidateAt
          : candidateAt as DateTime?,
      confidence: confidence ?? this.confidence,
      reviewReason: reviewReason ?? this.reviewReason,
    );
  }
}

class ClassificationCandidate {
  const ClassificationCandidate({
    required this.type,
    required this.title,
    required this.confidence,
    this.summary = '',
    this.tags = const [],
    this.start,
    this.end,
    this.due,
    this.allDay = false,
    this.recurrence,
    this.needsReview = false,
    this.reviewReason,
  });

  final ResultType type;
  final String title;
  final double confidence;
  final String summary;
  final List<String> tags;
  final DateTime? start;
  final DateTime? end;
  final DateTime? due;
  final bool allDay;
  final String? recurrence;
  final bool needsReview;
  final String? reviewReason;
}

class IndexedResult {
  const IndexedResult({
    required this.id,
    required this.type,
    required this.title,
    required this.status,
    required this.revision,
    required this.updatedAt,
    required this.deleted,
    required this.mdPath,
    required this.localHash,
    required this.lastSyncedHash,
    required this.syncState,
    this.matterId,
    this.remoteEtag,
  });

  final String id;
  final ResultType type;
  final String title;
  final ResultStatus status;
  final int revision;
  final DateTime updatedAt;
  final bool deleted;
  final String mdPath;
  final String localHash;
  final String? lastSyncedHash;
  final String? remoteEtag;
  final String? matterId;
  final SyncState syncState;

  IndexedResult copyWith({
    String? localHash,
    String? lastSyncedHash,
    String? remoteEtag,
    SyncState? syncState,
  }) {
    return IndexedResult(
      id: id,
      type: type,
      title: title,
      status: status,
      revision: revision,
      updatedAt: updatedAt,
      deleted: deleted,
      mdPath: mdPath,
      localHash: localHash ?? this.localHash,
      lastSyncedHash: lastSyncedHash ?? this.lastSyncedHash,
      remoteEtag: remoteEtag ?? this.remoteEtag,
      matterId: matterId,
      syncState: syncState ?? this.syncState,
    );
  }
}

class SyncRemoteObject {
  const SyncRemoteObject({
    required this.id,
    required this.path,
    required this.content,
    required this.hash,
    required this.etag,
  });

  final String id;
  final String path;
  final String content;
  final String hash;
  final String etag;

  SyncRemoteObject copyWith({
    String? path,
    String? content,
    String? hash,
    String? etag,
  }) {
    return SyncRemoteObject(
      id: id,
      path: path ?? this.path,
      content: content ?? this.content,
      hash: hash ?? this.hash,
      etag: etag ?? this.etag,
    );
  }
}

class SyncReport {
  const SyncReport({
    required this.uploaded,
    required this.downloaded,
    required this.conflicts,
    required this.unchanged,
    required this.failed,
    required this.finishedAt,
    this.message,
  });

  final int uploaded;
  final int downloaded;
  final int conflicts;
  final int unchanged;
  final int failed;
  final DateTime finishedAt;
  final String? message;

  bool get hasChanges => uploaded + downloaded + conflicts > 0;
}

class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.path,
    required this.localTitle,
    required this.remotePath,
    required this.createdAt,
  });

  final String id;
  final String path;
  final String localTitle;
  final String remotePath;
  final DateTime createdAt;
}
