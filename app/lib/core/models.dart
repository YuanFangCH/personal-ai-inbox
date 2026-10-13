enum ThemePreference { system, light, dark }

class AppSettings {
  static const currentSchemaVersion = 2;

  const AppSettings({
    required this.deviceId,
    required this.themeMode,
    required this.modelBaseUrl,
    required this.modelName,
    required this.hasModelKey,
    required this.showCompletedTodos,
    required this.calendarMonthDetailed,
    this.allowImageEgress = true,
    this.schemaVersion = currentSchemaVersion,
    this.modelKeySlotId,
    this.capabilityOverrides = const ModelCapabilityOverrides(),
    this.responseHeaderTimeoutSeconds = 45,
    this.streamIdleTimeoutSeconds = 60,
    this.totalTimeoutSeconds = 300,
    this.contextMessageLimit = 20,
    this.imageMessageLimit = 4,
    this.imageLimit = 8,
  });

  final String deviceId;
  final ThemePreference themeMode;
  final String modelBaseUrl;
  final String modelName;
  final bool hasModelKey;
  final bool showCompletedTodos;
  final bool calendarMonthDetailed;
  final bool allowImageEgress;
  final int schemaVersion;
  final String? modelKeySlotId;
  final ModelCapabilityOverrides capabilityOverrides;
  final int responseHeaderTimeoutSeconds;
  final int streamIdleTimeoutSeconds;
  final int totalTimeoutSeconds;
  final int contextMessageLimit;
  final int imageMessageLimit;
  final int imageLimit;

  List<String> validate() {
    final errors = <String>[];
    final uri = Uri.tryParse(modelBaseUrl.trim());
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.toLowerCase().endsWith('/chat/completions')) {
      errors.add('Base URL 必须是有效 API 根地址，不能包含凭据、查询或 fragment');
    } else if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' && _isLoopback(uri.host))) {
      errors.add('Base URL 仅允许 HTTPS；HTTP 只允许本机回环地址');
    }
    if (modelName.trim().isEmpty) errors.add('模型名称不能为空');
    if (responseHeaderTimeoutSeconds < 5 ||
        responseHeaderTimeoutSeconds > 120) {
      errors.add('响应头等待必须在 5–120 秒之间');
    }
    if (streamIdleTimeoutSeconds < 10 || streamIdleTimeoutSeconds > 180) {
      errors.add('流空闲期限必须在 10–180 秒之间');
    }
    if (totalTimeoutSeconds < 30 || totalTimeoutSeconds > 600) {
      errors.add('请求总时限必须在 30–600 秒之间');
    }
    if (totalTimeoutSeconds < responseHeaderTimeoutSeconds ||
        totalTimeoutSeconds < streamIdleTimeoutSeconds) {
      errors.add('请求总时限不能小于响应头或流空闲期限');
    }
    if (contextMessageLimit < 2 || contextMessageLimit > 20) {
      errors.add('上下文消息数必须在 2–20 条之间');
    }
    if (imageMessageLimit < 0 || imageMessageLimit > 4) {
      errors.add('含图历史消息数必须在 0–4 条之间');
    }
    if (imageLimit < 0 || imageLimit > 8) {
      errors.add('图片总数必须在 0–8 张之间');
    }
    return List.unmodifiable(errors);
  }

  static bool _isLoopback(String host) =>
      host.toLowerCase() == 'localhost' || host == '127.0.0.1' || host == '::1';

  AppSettings copyWith({
    String? deviceId,
    ThemePreference? themeMode,
    String? modelBaseUrl,
    String? modelName,
    bool? hasModelKey,
    bool? showCompletedTodos,
    bool? calendarMonthDetailed,
    bool? allowImageEgress,
    int? schemaVersion,
    String? modelKeySlotId,
    ModelCapabilityOverrides? capabilityOverrides,
    int? responseHeaderTimeoutSeconds,
    int? streamIdleTimeoutSeconds,
    int? totalTimeoutSeconds,
    int? contextMessageLimit,
    int? imageMessageLimit,
    int? imageLimit,
  }) => AppSettings(
    deviceId: deviceId ?? this.deviceId,
    themeMode: themeMode ?? this.themeMode,
    modelBaseUrl: modelBaseUrl ?? this.modelBaseUrl,
    modelName: modelName ?? this.modelName,
    hasModelKey: hasModelKey ?? this.hasModelKey,
    showCompletedTodos: showCompletedTodos ?? this.showCompletedTodos,
    calendarMonthDetailed: calendarMonthDetailed ?? this.calendarMonthDetailed,
    allowImageEgress: allowImageEgress ?? this.allowImageEgress,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    modelKeySlotId: modelKeySlotId ?? this.modelKeySlotId,
    capabilityOverrides: capabilityOverrides ?? this.capabilityOverrides,
    responseHeaderTimeoutSeconds:
        responseHeaderTimeoutSeconds ?? this.responseHeaderTimeoutSeconds,
    streamIdleTimeoutSeconds:
        streamIdleTimeoutSeconds ?? this.streamIdleTimeoutSeconds,
    totalTimeoutSeconds: totalTimeoutSeconds ?? this.totalTimeoutSeconds,
    contextMessageLimit: contextMessageLimit ?? this.contextMessageLimit,
    imageMessageLimit: imageMessageLimit ?? this.imageMessageLimit,
    imageLimit: imageLimit ?? this.imageLimit,
  );
}

class ModelCapabilityOverrides {
  const ModelCapabilityOverrides({
    this.vision,
    this.toolCalls,
    this.jsonOutput,
  });

  final bool? vision;
  final bool? toolCalls;
  final bool? jsonOutput;

  ModelCapabilityOverrides copyWith({
    Object? vision = _unchangedCapability,
    Object? toolCalls = _unchangedCapability,
    Object? jsonOutput = _unchangedCapability,
  }) => ModelCapabilityOverrides(
    vision: identical(vision, _unchangedCapability)
        ? this.vision
        : vision as bool?,
    toolCalls: identical(toolCalls, _unchangedCapability)
        ? this.toolCalls
        : toolCalls as bool?,
    jsonOutput: identical(jsonOutput, _unchangedCapability)
        ? this.jsonOutput
        : jsonOutput as bool?,
  );
}

const _unchangedCapability = Object();

enum ResultType {
  matter('matter'),
  todo('todo'),
  event('event'),
  knowledge('knowledge');

  const ResultType(this.wireName);

  final String wireName;

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
  draft('draft'),
  reviewed('reviewed'),
  canonical('canonical');

  const ResultStatus(this.wireName);

  final String wireName;

  static ResultStatus parse(String value) {
    return ResultStatus.values.firstWhere(
      (status) => status.wireName == value,
      orElse: () => ResultStatus.draft,
    );
  }
}

enum SyncState { synced, pendingUpload, pendingDownload, conflict, deleted }

class IndexRebuildDiagnostic {
  const IndexRebuildDiagnostic({required this.path, required this.message});

  final String path;
  final String message;
}

class IndexRebuildReport {
  const IndexRebuildReport({
    required this.scanned,
    required this.indexed,
    required this.diagnostics,
  });

  final int scanned;
  final int indexed;
  final List<IndexRebuildDiagnostic> diagnostics;

  int get failed => diagnostics.length;
}

enum CaptureSourceType {
  text('text'),
  image('image'),
  url('url'),
  file('file');

  const CaptureSourceType(this.wireName);

  final String wireName;

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
    this.schemaVersion = 1,
    this.extensionFields = const {},
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
  final int schemaVersion;
  final Map<String, Object?> extensionFields;
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
    int? schemaVersion,
    Map<String, Object?>? extensionFields,
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
      schemaVersion: schemaVersion ?? this.schemaVersion,
      extensionFields: extensionFields ?? this.extensionFields,
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
    this.searchText = '',
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
  final String searchText;

  IndexedResult copyWith({
    String? localHash,
    String? lastSyncedHash,
    String? remoteEtag,
    SyncState? syncState,
    String? searchText,
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
      searchText: searchText ?? this.searchText,
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
    this.failures = const [],
  });

  final int uploaded;
  final int downloaded;
  final int conflicts;
  final int unchanged;
  final int failed;
  final DateTime finishedAt;
  final String? message;
  final List<SyncFailure> failures;

  bool get hasChanges => uploaded + downloaded + conflicts > 0;
}

class SyncFailure {
  const SyncFailure({
    required this.stage,
    required this.code,
    required this.message,
    this.objectId,
    this.retryable = false,
    this.occurredAt,
  });

  final String stage;
  final String code;
  final String message;
  final String? objectId;
  final bool retryable;
  final DateTime? occurredAt;
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
