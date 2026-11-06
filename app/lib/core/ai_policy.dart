/// Legacy conversation capability snapshot.
///
/// Persisted conversations and settings still store these three booleans.
/// New code should resolve an [AiPolicy] instead of consuming this directly.
class AiPermissions {
  const AiPermissions({
    this.read = true,
    this.create = true,
    this.modifyDelete = true,
  });

  final bool read;
  final bool create;
  final bool modifyDelete;

  AiPermissions copyWith({bool? read, bool? create, bool? modifyDelete}) =>
      AiPermissions(
        read: read ?? this.read,
        create: create ?? this.create,
        modifyDelete: modifyDelete ?? this.modifyDelete,
      );

  Map<String, Object?> toJson() => {
    'read': read,
    'create': create,
    'modify_delete': modifyDelete,
  };

  static AiPermissions fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AiPermissions();
    bool flag(String key) {
      final value = json[key];
      if (value is! bool) throw FormatException('AI 权限字段 $key 类型错误');
      return value;
    }

    return AiPermissions(
      read: flag('read'),
      create: flag('create'),
      modifyDelete: flag('modify_delete'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AiPermissions &&
      other.read == read &&
      other.create == create &&
      other.modifyDelete == modifyDelete;

  @override
  int get hashCode => Object.hash(read, create, modifyDelete);
}

/// User-visible policy shortcut. A policy always contains concrete action
/// decisions; a preset only creates the initial map.
enum AiPolicyPreset {
  readOnly('read_only'),
  standard('standard'),
  fullAccess('full_access'),
  custom('custom');

  const AiPolicyPreset(this.wireName);

  final String wireName;

  static AiPolicyPreset parse(String value) {
    return AiPolicyPreset.values.firstWhere(
      (preset) => preset.wireName == value,
      orElse: () =>
          throw FormatException('Unsupported AI policy preset: $value'),
    );
  }
}

/// Decision returned by the local execution point.
enum AiPolicyDecision {
  allow('allow'),
  ask('ask'),
  deny('deny');

  const AiPolicyDecision(this.wireName);

  final String wireName;

  static AiPolicyDecision parse(String value) {
    return AiPolicyDecision.values.firstWhere(
      (decision) => decision.wireName == value,
      orElse: () =>
          throw FormatException('Unsupported AI policy decision: $value'),
    );
  }
}

/// Every app-level action that the secretary can request.
///
/// Credential access, arbitrary files, SQL, operating-system controls,
/// conversation mutation, and policy mutation are intentionally absent.
enum AiPermissionAction {
  tableRead('table_read'),
  contentRead('content_read'),
  contentCreate('content_create'),
  contentUpdate('content_update'),
  contentDelete('content_delete'),
  contentMove('content_move'),
  tableBodyUpdate('table_body_update'),
  tableCreate('table_create'),
  tableUpdate('table_update'),
  tableDelete('table_delete'),
  fieldAdjust('field_adjust'),
  inboxTargetAdjust('inbox_target_adjust'),
  restore('restore'),
  globalKnowledgeRead('global_knowledge_read'),
  globalKnowledgeSearch('global_knowledge_search'),
  globalKnowledgeCreate('global_knowledge_create'),
  globalKnowledgeUpdate('global_knowledge_update'),
  globalKnowledgeDelete('global_knowledge_delete'),
  conversationHistorySearch('conversation_history_search'),
  conversationHistoryRead('conversation_history_read');

  const AiPermissionAction(this.wireName);

  final String wireName;

  static AiPermissionAction parse(String value) {
    return AiPermissionAction.values.firstWhere(
      (action) => action.wireName == value,
      orElse: () =>
          throw FormatException('Unsupported AI permission action: $value'),
    );
  }

  bool get isReadAction => const {
    AiPermissionAction.tableRead,
    AiPermissionAction.contentRead,
    AiPermissionAction.globalKnowledgeRead,
    AiPermissionAction.globalKnowledgeSearch,
    AiPermissionAction.conversationHistorySearch,
    AiPermissionAction.conversationHistoryRead,
  }.contains(this);

  bool get requiresTableScope => const {
    AiPermissionAction.tableRead,
    AiPermissionAction.contentRead,
    AiPermissionAction.contentCreate,
    AiPermissionAction.contentUpdate,
    AiPermissionAction.contentDelete,
    AiPermissionAction.contentMove,
    AiPermissionAction.tableBodyUpdate,
    AiPermissionAction.tableCreate,
    AiPermissionAction.tableUpdate,
    AiPermissionAction.tableDelete,
    AiPermissionAction.fieldAdjust,
    AiPermissionAction.inboxTargetAdjust,
    AiPermissionAction.restore,
  }.contains(this);

  bool get requiresKnowledgeReadScope => const {
    AiPermissionAction.globalKnowledgeRead,
    AiPermissionAction.globalKnowledgeSearch,
  }.contains(this);

  bool get requiresConversationReadScope => const {
    AiPermissionAction.conversationHistorySearch,
    AiPermissionAction.conversationHistoryRead,
  }.contains(this);
}

enum AiResourceScopeKind {
  none('none'),
  selected('selected'),
  all('all');

  const AiResourceScopeKind(this.wireName);

  final String wireName;

  static AiResourceScopeKind parse(String value) {
    return AiResourceScopeKind.values.firstWhere(
      (kind) => kind.wireName == value,
      orElse: () => throw FormatException('Unsupported AI scope kind: $value'),
    );
  }
}

/// Scope for tables, global knowledge records, or other conversations.
///
/// [selected] stores normalized stable IDs and is immutable. A direct
/// execution point should call [covers] before returning content. List/search
/// tools should filter their source data with the same scope.
class AiResourceScope {
  const AiResourceScope.all() : kind = AiResourceScopeKind.all, _ids = const {};

  const AiResourceScope.none()
    : kind = AiResourceScopeKind.none,
      _ids = const {};

  factory AiResourceScope.selected(Iterable<String> ids) {
    final normalized = <String>{};
    for (final rawId in ids) {
      final id = rawId.trim();
      if (id.isEmpty) {
        throw ArgumentError.value(rawId, 'ids', 'ID 不能为空');
      }
      normalized.add(id);
    }
    if (normalized.isEmpty) return const AiResourceScope.none();
    return AiResourceScope._(
      AiResourceScopeKind.selected,
      Set<String>.unmodifiable(normalized),
    );
  }

  const AiResourceScope._(this.kind, this._ids);

  final AiResourceScopeKind kind;
  final Set<String> _ids;

  Set<String> get ids => _ids;

  bool get isAll => kind == AiResourceScopeKind.all;

  bool get isNone => kind == AiResourceScopeKind.none;

  bool covers(String id) => switch (kind) {
    AiResourceScopeKind.all => true,
    AiResourceScopeKind.none => false,
    AiResourceScopeKind.selected => _ids.contains(id),
  };

  bool coversAll(Iterable<String> resourceIds) => resourceIds.every(covers);

  Map<String, Object?> toJson() => {
    'kind': kind.wireName,
    'ids': _ids.toList(growable: false),
  };

  static AiResourceScope fromJson(Object? json) {
    if (json is! Map) throw const FormatException('AI 范围必须是对象');
    final rawKind = json['kind'];
    if (rawKind is! String) throw const FormatException('AI 范围 kind 类型错误');
    final kind = AiResourceScopeKind.parse(rawKind);
    if (kind == AiResourceScopeKind.all) return const AiResourceScope.all();
    if (kind == AiResourceScopeKind.none) return const AiResourceScope.none();
    final rawIds = json['ids'];
    if (rawIds is! List || rawIds.any((id) => id is! String)) {
      throw const FormatException('AI 范围 ids 类型错误');
    }
    return AiResourceScope.selected(rawIds.cast<String>());
  }

  @override
  bool operator ==(Object other) =>
      other is AiResourceScope &&
      other.kind == kind &&
      _sameSet(other._ids, _ids);

  @override
  int get hashCode => Object.hash(kind, Object.hashAllUnordered(_ids));
}

/// Immutable local authorization snapshot for one conversation.
///
/// The policy is resolved again before every model dispatch, tool execution,
/// confirmation, restore, and replay. Missing action entries fail closed.
class AiPolicy {
  AiPolicy._({
    required this.version,
    required this.preset,
    required this.tableScope,
    required this.knowledgeReadScope,
    required this.conversationHistoryReadScope,
    required Map<AiPermissionAction, AiPolicyDecision> decisions,
  }) : _decisions = Map<AiPermissionAction, AiPolicyDecision>.unmodifiable(
         decisions,
       ) {
    if (version < 1) {
      throw ArgumentError.value(version, 'version', '策略版本必须为正数');
    }
  }

  factory AiPolicy.forPreset(
    AiPolicyPreset preset, {
    int version = 1,
    AiResourceScope tableScope = const AiResourceScope.all(),
    AiResourceScope knowledgeReadScope = const AiResourceScope.all(),
    AiResourceScope conversationHistoryReadScope = const AiResourceScope.all(),
  }) {
    if (preset == AiPolicyPreset.custom) {
      throw ArgumentError('自定义策略必须提供动作决策');
    }
    final decisions = switch (preset) {
      AiPolicyPreset.readOnly => _readOnlyDecisions,
      AiPolicyPreset.standard => _standardDecisions,
      AiPolicyPreset.fullAccess => _fullAccessDecisions,
      AiPolicyPreset.custom => throw StateError('unreachable'),
    };
    return AiPolicy._(
      version: version,
      preset: preset,
      tableScope: tableScope,
      knowledgeReadScope: knowledgeReadScope,
      conversationHistoryReadScope: conversationHistoryReadScope,
      decisions: decisions,
    );
  }

  factory AiPolicy.custom({
    required Map<AiPermissionAction, AiPolicyDecision> decisions,
    int version = 1,
    AiResourceScope tableScope = const AiResourceScope.none(),
    AiResourceScope knowledgeReadScope = const AiResourceScope.none(),
    AiResourceScope conversationHistoryReadScope = const AiResourceScope.none(),
  }) => AiPolicy._(
    version: version,
    preset: AiPolicyPreset.custom,
    tableScope: tableScope,
    knowledgeReadScope: knowledgeReadScope,
    conversationHistoryReadScope: conversationHistoryReadScope,
    decisions: decisions,
  );

  /// Converts an existing persisted conversation without granting new scope.
  ///
  /// The result is deliberately [AiPolicyPreset.custom], never
  /// [AiPolicyPreset.fullAccess]. Existing content writes stay direct, while
  /// structure and global-knowledge writes remain confirmation-gated.
  factory AiPolicy.fromLegacyPermissions(
    AiPermissions permissions, {
    int version = 1,
    AiResourceScope tableScope = const AiResourceScope.all(),
  }) {
    final knowledgeReadScope = permissions.read
        ? const AiResourceScope.all()
        : const AiResourceScope.none();
    final historyReadScope = permissions.read
        ? const AiResourceScope.all()
        : const AiResourceScope.none();
    return AiPolicy.custom(
      version: version,
      tableScope: tableScope,
      knowledgeReadScope: knowledgeReadScope,
      conversationHistoryReadScope: historyReadScope,
      decisions: {
        for (final action in AiPermissionAction.values)
          action: switch (action) {
            AiPermissionAction.tableRead ||
            AiPermissionAction.contentRead ||
            AiPermissionAction.globalKnowledgeRead ||
            AiPermissionAction.globalKnowledgeSearch ||
            AiPermissionAction.conversationHistorySearch ||
            AiPermissionAction.conversationHistoryRead =>
              permissions.read ? AiPolicyDecision.allow : AiPolicyDecision.deny,
            AiPermissionAction.contentCreate =>
              permissions.create
                  ? AiPolicyDecision.allow
                  : AiPolicyDecision.deny,
            AiPermissionAction.tableCreate =>
              permissions.create ? AiPolicyDecision.ask : AiPolicyDecision.deny,
            AiPermissionAction.contentUpdate ||
            AiPermissionAction.contentDelete ||
            AiPermissionAction.contentMove ||
            AiPermissionAction.tableBodyUpdate =>
              permissions.modifyDelete
                  ? AiPolicyDecision.allow
                  : AiPolicyDecision.deny,
            AiPermissionAction.tableUpdate ||
            AiPermissionAction.tableDelete ||
            AiPermissionAction.fieldAdjust ||
            AiPermissionAction.inboxTargetAdjust ||
            AiPermissionAction.restore =>
              permissions.modifyDelete
                  ? AiPolicyDecision.ask
                  : AiPolicyDecision.deny,
            AiPermissionAction.globalKnowledgeCreate ||
            AiPermissionAction.globalKnowledgeUpdate ||
            AiPermissionAction.globalKnowledgeDelete =>
              permissions.create || permissions.modifyDelete
                  ? AiPolicyDecision.ask
                  : AiPolicyDecision.deny,
          },
      },
    );
  }

  final int version;
  final AiPolicyPreset preset;
  final AiResourceScope tableScope;
  final AiResourceScope knowledgeReadScope;
  final AiResourceScope conversationHistoryReadScope;
  final Map<AiPermissionAction, AiPolicyDecision> _decisions;

  Map<AiPermissionAction, AiPolicyDecision> get decisions => _decisions;

  /// Resolves the action plus any supplied resource scope.
  ///
  /// [tableIds] should contain every table touched by a table-scoped action;
  /// a move must include both source and target. For list/search operations,
  /// omit IDs and filter hits with [tableScope] so a selected scope remains a
  /// valid filter instead of being mistaken for unrestricted access.
  AiPolicyDecision decisionFor(
    AiPermissionAction action, {
    Iterable<String> tableIds = const [],
    String? knowledgeId,
    String? conversationId,
  }) {
    final baseDecision = _decisions[action] ?? AiPolicyDecision.deny;
    if (baseDecision == AiPolicyDecision.deny) {
      return AiPolicyDecision.deny;
    }
    // Creating a table has no existing target ID against which a selected
    // scope can be checked, so only an unrestricted table scope can grant it.
    if (action == AiPermissionAction.tableCreate && !tableScope.isAll) {
      return AiPolicyDecision.deny;
    }
    if (action.requiresTableScope && !tableScope.coversAll(tableIds)) {
      return AiPolicyDecision.deny;
    }
    if (action.requiresKnowledgeReadScope &&
        knowledgeId != null &&
        !knowledgeReadScope.covers(knowledgeId)) {
      return AiPolicyDecision.deny;
    }
    if (action.requiresConversationReadScope &&
        conversationId != null &&
        !conversationHistoryReadScope.covers(conversationId)) {
      return AiPolicyDecision.deny;
    }
    return baseDecision;
  }

  /// `ask` actions stay visible so the model can request a confirmation card.
  bool isToolVisible(AiPermissionAction action) =>
      decisionFor(action) != AiPolicyDecision.deny;

  AiPolicy withDecision(AiPermissionAction action, AiPolicyDecision decision) =>
      AiPolicy.custom(
        version: version + 1,
        tableScope: tableScope,
        knowledgeReadScope: knowledgeReadScope,
        conversationHistoryReadScope: conversationHistoryReadScope,
        decisions: {..._decisions, action: decision},
      );

  Map<String, Object?> toJson() => {
    'version': version,
    'preset': preset.wireName,
    'table_scope': tableScope.toJson(),
    'knowledge_read_scope': knowledgeReadScope.toJson(),
    'conversation_history_read_scope': conversationHistoryReadScope.toJson(),
    'actions': {
      for (final action in AiPermissionAction.values)
        action.wireName: (_decisions[action] ?? AiPolicyDecision.deny).wireName,
    },
  };

  static AiPolicy fromJson(Object? json) {
    if (json is! Map) throw const FormatException('AI 策略必须是对象');
    final rawVersion = json['version'];
    final rawPreset = json['preset'];
    final rawActions = json['actions'];
    if (rawVersion is! int || rawVersion < 1) {
      throw const FormatException('AI 策略 version 类型错误');
    }
    if (rawPreset is! String) {
      throw const FormatException('AI 策略 preset 类型错误');
    }
    if (rawActions is! Map) {
      throw const FormatException('AI 策略 actions 类型错误');
    }
    final decisions = <AiPermissionAction, AiPolicyDecision>{
      for (final entry in rawActions.entries)
        if (entry.key is String && entry.value is String)
          AiPermissionAction.parse(entry.key as String): AiPolicyDecision.parse(
            entry.value as String,
          ),
    };
    final preset = AiPolicyPreset.parse(rawPreset);
    if (preset != AiPolicyPreset.custom) {
      if (decisions.length != AiPermissionAction.values.length) {
        throw const FormatException('AI 预设策略 action 不完整');
      }
    }
    return AiPolicy._(
      version: rawVersion,
      preset: preset,
      tableScope: AiResourceScope.fromJson(json['table_scope']),
      knowledgeReadScope: AiResourceScope.fromJson(
        json['knowledge_read_scope'],
      ),
      conversationHistoryReadScope: AiResourceScope.fromJson(
        json['conversation_history_read_scope'],
      ),
      decisions: decisions,
    );
  }

  static const _readOnlyDecisions = <AiPermissionAction, AiPolicyDecision>{
    AiPermissionAction.tableRead: AiPolicyDecision.allow,
    AiPermissionAction.contentRead: AiPolicyDecision.allow,
    AiPermissionAction.contentCreate: AiPolicyDecision.deny,
    AiPermissionAction.contentUpdate: AiPolicyDecision.deny,
    AiPermissionAction.contentDelete: AiPolicyDecision.deny,
    AiPermissionAction.contentMove: AiPolicyDecision.deny,
    AiPermissionAction.tableBodyUpdate: AiPolicyDecision.deny,
    AiPermissionAction.tableCreate: AiPolicyDecision.deny,
    AiPermissionAction.tableUpdate: AiPolicyDecision.deny,
    AiPermissionAction.tableDelete: AiPolicyDecision.deny,
    AiPermissionAction.fieldAdjust: AiPolicyDecision.deny,
    AiPermissionAction.inboxTargetAdjust: AiPolicyDecision.deny,
    AiPermissionAction.restore: AiPolicyDecision.deny,
    AiPermissionAction.globalKnowledgeRead: AiPolicyDecision.allow,
    AiPermissionAction.globalKnowledgeSearch: AiPolicyDecision.allow,
    AiPermissionAction.globalKnowledgeCreate: AiPolicyDecision.deny,
    AiPermissionAction.globalKnowledgeUpdate: AiPolicyDecision.deny,
    AiPermissionAction.globalKnowledgeDelete: AiPolicyDecision.deny,
    AiPermissionAction.conversationHistorySearch: AiPolicyDecision.allow,
    AiPermissionAction.conversationHistoryRead: AiPolicyDecision.allow,
  };

  static const _standardDecisions = <AiPermissionAction, AiPolicyDecision>{
    AiPermissionAction.tableRead: AiPolicyDecision.allow,
    AiPermissionAction.contentRead: AiPolicyDecision.allow,
    AiPermissionAction.contentCreate: AiPolicyDecision.allow,
    AiPermissionAction.contentUpdate: AiPolicyDecision.allow,
    AiPermissionAction.contentDelete: AiPolicyDecision.allow,
    AiPermissionAction.contentMove: AiPolicyDecision.allow,
    AiPermissionAction.tableBodyUpdate: AiPolicyDecision.allow,
    AiPermissionAction.tableCreate: AiPolicyDecision.ask,
    AiPermissionAction.tableUpdate: AiPolicyDecision.ask,
    AiPermissionAction.tableDelete: AiPolicyDecision.ask,
    AiPermissionAction.fieldAdjust: AiPolicyDecision.ask,
    AiPermissionAction.inboxTargetAdjust: AiPolicyDecision.ask,
    AiPermissionAction.restore: AiPolicyDecision.ask,
    AiPermissionAction.globalKnowledgeRead: AiPolicyDecision.allow,
    AiPermissionAction.globalKnowledgeSearch: AiPolicyDecision.allow,
    AiPermissionAction.globalKnowledgeCreate: AiPolicyDecision.ask,
    AiPermissionAction.globalKnowledgeUpdate: AiPolicyDecision.ask,
    AiPermissionAction.globalKnowledgeDelete: AiPolicyDecision.ask,
    AiPermissionAction.conversationHistorySearch: AiPolicyDecision.allow,
    AiPermissionAction.conversationHistoryRead: AiPolicyDecision.allow,
  };

  static const _fullAccessDecisions = <AiPermissionAction, AiPolicyDecision>{
    AiPermissionAction.tableRead: AiPolicyDecision.allow,
    AiPermissionAction.contentRead: AiPolicyDecision.allow,
    AiPermissionAction.contentCreate: AiPolicyDecision.allow,
    AiPermissionAction.contentUpdate: AiPolicyDecision.allow,
    AiPermissionAction.contentDelete: AiPolicyDecision.allow,
    AiPermissionAction.contentMove: AiPolicyDecision.allow,
    AiPermissionAction.tableBodyUpdate: AiPolicyDecision.allow,
    AiPermissionAction.tableCreate: AiPolicyDecision.allow,
    AiPermissionAction.tableUpdate: AiPolicyDecision.allow,
    AiPermissionAction.tableDelete: AiPolicyDecision.allow,
    AiPermissionAction.fieldAdjust: AiPolicyDecision.allow,
    AiPermissionAction.inboxTargetAdjust: AiPolicyDecision.allow,
    AiPermissionAction.restore: AiPolicyDecision.allow,
    AiPermissionAction.globalKnowledgeRead: AiPolicyDecision.allow,
    AiPermissionAction.globalKnowledgeSearch: AiPolicyDecision.allow,
    AiPermissionAction.globalKnowledgeCreate: AiPolicyDecision.allow,
    AiPermissionAction.globalKnowledgeUpdate: AiPolicyDecision.allow,
    AiPermissionAction.globalKnowledgeDelete: AiPolicyDecision.allow,
    AiPermissionAction.conversationHistorySearch: AiPolicyDecision.allow,
    AiPermissionAction.conversationHistoryRead: AiPolicyDecision.allow,
  };
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
