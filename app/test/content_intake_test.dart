import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/modules/conversation/content_duplicate_policy.dart';
import 'package:personal_ai_inbox/modules/conversation/content_intake.dart';
import 'package:personal_ai_inbox/modules/tables/table_library.dart';

void main() {
  test('fresh intake replays the original durable receipt', () async {
    final harness = await _Harness.create();
    final table = await harness.tables.createTable(title: '恢复');
    final request = _noteRequest(
      operationId: 'durable-op',
      tableId: table.id,
      title: '同一操作',
      body: '原文',
      evidence: const [],
    );
    final first = ContentIntake(tables: harness.tables);
    final created = await first.commit(await first.prepare(request));
    final restarted = ContentIntake(tables: harness.tables);
    final replayed = await restarted.commit(await restarted.prepare(request));
    expect(replayed.replayed, isTrue);
    expect(replayed.outcome, ContentIntakeOutcome.created);
    expect(replayed.entryId, created.entryId);
    expect(replayed.oldRevision, 0);
    expect(replayed.newRevision, created.newRevision);
  });
  test('normalized exact content reuses the same business object', () async {
    final harness = await _Harness.create();
    addTearDown(harness.close);
    final table = await harness.tables.createTable(title: '课程');
    final otherTable = await harness.tables.createTable(title: '归档');
    final intake = ContentIntake(
      tables: harness.tables,
      entryIdFactory: _SequentialIdFactory().call,
      clock: () => DateTime.parse('2026-11-03T09:00:00+08:00'),
    );

    final first = await intake.prepare(
      _noteRequest(
        operationId: 'exact-first',
        tableId: table.id,
        title: 'ＧＰＵ 复习',
        body: '第一行\r\n第二行',
        evidence: const ['course:gpu'],
      ),
    );
    final created = await intake.commit(first);
    expect(created.outcome, ContentIntakeOutcome.created);
    expect(created.coverage.exactFingerprintScopeComplete, isTrue);
    expect(created.coverage.semanticUniquenessProven, isFalse);

    final second = await intake.prepare(
      _noteRequest(
        operationId: 'exact-second',
        tableId: otherTable.id,
        title: 'gpu  复习',
        body: '第一行\n 第二行',
        evidence: const [' COURSE:GPU '],
      ),
    );
    final reused = await intake.commit(second);

    expect(reused.outcome, ContentIntakeOutcome.reused);
    expect(reused.entryId, created.entryId);
    expect(reused.oldRevision, reused.newRevision);
    expect(
      await harness.tables.searchEntries(
        query: '',
        tableId: table.id,
        limit: 100,
      ),
      hasLength(1),
    );
  });

  test('same title with another object or time remains independent', () async {
    final harness = await _Harness.create();
    addTearDown(harness.close);
    final table = await harness.tables.createTable(title: '考试安排');
    var id = 0;
    final intake = ContentIntake(
      tables: harness.tables,
      entryIdFactory: (_) => 'sc_intake_${id++}',
    );
    final firstStart = DateTime.parse('2026-11-10T09:00:00+08:00');

    Future<ContentIntakeResult> ingest({
      required String operationId,
      required String evidence,
      required DateTime start,
      required String objectLink,
    }) async {
      final preparation = await intake.prepare(
        ContentIntakeRequest(
          operationId: operationId,
          tableId: table.id,
          type: TableContentType.schedule,
          title: '期中考试',
          body: '闭卷',
          identity: ContentBusinessIdentity(evidence: [evidence]),
          links: [objectLink],
          start: start,
          end: start.add(const Duration(hours: 2)),
        ),
      );
      return intake.commit(preparation);
    }

    final signals = await ingest(
      operationId: 'schedule-signals',
      evidence: 'course:signals',
      start: firstStart,
      objectLink: 'entry:course_signals',
    );
    final networks = await ingest(
      operationId: 'schedule-networks',
      evidence: 'course:networks',
      start: firstStart,
      objectLink: 'entry:course_networks',
    );
    final laterSignals = await ingest(
      operationId: 'schedule-signals-later',
      evidence: 'course:signals',
      start: firstStart.add(const Duration(days: 7)),
      objectLink: 'entry:course_signals',
    );

    expect(signals.outcome, ContentIntakeOutcome.created);
    expect(networks.outcome, ContentIntakeOutcome.created);
    expect(laterSignals.outcome, ContentIntakeOutcome.created);
    expect({
      signals.entryId,
      networks.entryId,
      laterSignals.entryId,
    }, hasLength(3));
  });

  test(
    'normalized exact content reuses without caller identity evidence',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final table = await harness.tables.createTable(title: '无身份参数');
      var nextId = 0;
      final intake = ContentIntake(
        tables: harness.tables,
        entryIdFactory: (_) => 'nt_no_identity_${nextId++}',
      );

      final first = await intake.commit(
        await intake.prepare(
          ContentIntakeRequest(
            operationId: 'no-identity-first',
            tableId: table.id,
            type: TableContentType.note,
            title: '普通笔记',
            body: '完全相同 的正文',
          ),
        ),
      );
      final second = await intake.commit(
        await intake.prepare(
          ContentIntakeRequest(
            operationId: 'no-identity-second',
            tableId: table.id,
            type: TableContentType.note,
            title: ' 普通笔记 ',
            body: '完全相同    的正文',
          ),
        ),
      );

      expect(second.outcome, ContentIntakeOutcome.reused);
      expect(second.entryId, first.entryId);
      expect(
        await harness.tables.searchEntries(query: '', limit: 100),
        hasLength(1),
      );
    },
  );

  test('content type remains part of exact duplicate identity', () async {
    final harness = await _Harness.create();
    addTearDown(harness.close);
    final table = await harness.tables.createTable(title: '类型区分');
    var nextId = 0;
    final intake = ContentIntake(
      tables: harness.tables,
      entryIdFactory: (_) => 'nt_type_${nextId++}',
    );

    final note = await intake.commit(
      await intake.prepare(
        ContentIntakeRequest(
          operationId: 'type-note',
          tableId: table.id,
          type: TableContentType.note,
          title: '同名内容',
          body: '正文',
        ),
      ),
    );
    final todo = await intake.commit(
      await intake.prepare(
        ContentIntakeRequest(
          operationId: 'type-todo',
          tableId: table.id,
          type: TableContentType.todo,
          title: '同名内容',
          body: '正文',
        ),
      ),
    );

    expect(note.outcome, ContentIntakeOutcome.created);
    expect(todo.outcome, ContentIntakeOutcome.created);
    expect(todo.entryId, isNot(note.entryId));
  });

  test(
    'commit authorization guard blocks create and augment after prepare',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final table = await harness.tables.createTable(title: '写前授权');
      final authorizations = <ContentIntakeWriteAuthorization>[];
      var allowWrites = true;
      var nextId = 0;
      final intake = ContentIntake(
        tables: harness.tables,
        entryIdFactory: (_) => 'nt_auth_${nextId++}',
        semanticDecisionSource: _DecisionSource((request) async {
          return SemanticDuplicateDecision(
            action: SemanticDuplicateAction.augment,
            targetId: request.candidates.single.entry.id,
            expectedRevision: request.candidates.single.entry.revision,
            evidence: const ['course:signals'],
            bodyAddition: '补充事实',
          );
        }),
      );
      Future<bool> guard(ContentIntakeWriteAuthorization authorization) async {
        authorizations.add(authorization);
        return allowWrites;
      }

      final createPreparation = await intake.prepare(
        ContentIntakeRequest(
          operationId: 'auth-create',
          tableId: table.id,
          type: TableContentType.note,
          title: '授权测试',
          body: '初始正文',
          identity: ContentBusinessIdentity(evidence: const ['course:signals']),
        ),
      );
      final created = await intake.commit(
        createPreparation,
        authorizationGuard: guard,
      );
      expect(created.outcome, ContentIntakeOutcome.created);
      expect(authorizations.single.kind, ContentIntakeWriteKind.create);
      expect(authorizations.single.tableId, table.id);

      final augmentPreparation = await intake.prepare(
        ContentIntakeRequest(
          operationId: 'auth-augment',
          tableId: table.id,
          type: TableContentType.note,
          title: '授权测试',
          body: '补充事实',
          identity: ContentBusinessIdentity(evidence: const ['course:signals']),
        ),
      );
      allowWrites = false;
      final denied = await intake.commit(
        augmentPreparation,
        authorizationGuard: guard,
      );

      expect(denied.outcome, ContentIntakeOutcome.conflict);
      expect(authorizations.last.kind, ContentIntakeWriteKind.augment);
      expect(authorizations.last.tableId, table.id);
      expect(authorizations.last.targetId, created.entryId);
      expect(authorizations.last.targetRevision, 1);
      expect((await harness.tables.readEntry(created.entryId!))?.body, '初始正文');
    },
  );

  test(
    'retry authorization revoked during commit leaves its operation ID open',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final table = await harness.tables.createTable(title: '重试授权撤销');
      final initial = ContentIntake(tables: harness.tables);
      final original = await initial.commit(
        await initial.prepare(
          _noteRequest(
            operationId: 'retry-auth-original',
            tableId: table.id,
            title: '课程安排',
            body: '已有内容',
            evidence: const ['course:retry-auth'],
          ),
        ),
      );
      final retryRequest = _noteRequest(
        operationId: 'retry-auth-stable-id',
        tableId: table.id,
        title: '课程安排',
        body: '重试时补充',
        evidence: const ['course:retry-auth'],
      );
      var comparisonCalls = 0;
      final intake = ContentIntake(
        tables: harness.tables,
        semanticDecisionSource: _DecisionSource((request) async {
          comparisonCalls++;
          final candidate = request.candidates.single;
          return SemanticDuplicateDecision(
            action: SemanticDuplicateAction.augment,
            targetId: candidate.entry.id,
            expectedRevision: candidate.entry.revision,
            evidence: const ['course:retry-auth'],
            bodyAddition: '重试时补充',
          );
        }),
      );
      final retryPreparation = await intake.prepare(retryRequest);
      final guardEntered = Completer<void>();
      final releaseGuard = Completer<bool>();
      final pendingCommit = intake.commit(
        retryPreparation,
        authorizationGuard: (_) {
          guardEntered.complete();
          return releaseGuard.future;
        },
        persistAuthorizationConflict: false,
      );
      await guardEntered.future;
      releaseGuard.complete(false);
      final denied = await pendingCommit;

      expect(denied.outcome, ContentIntakeOutcome.conflict);
      expect(denied.reason, contains('授权已失效'));
      expect(comparisonCalls, 1);
      expect((await harness.tables.readEntry(original.entryId!))?.body, '已有内容');

      // A restarted service with the same retry operation id must scan again,
      // proving that the denied attempt did not persist a terminal receipt.
      final restarted = ContentIntake(
        tables: harness.tables,
        semanticDecisionSource: _DecisionSource((request) async {
          comparisonCalls++;
          final candidate = request.candidates.single;
          return SemanticDuplicateDecision(
            action: SemanticDuplicateAction.augment,
            targetId: candidate.entry.id,
            expectedRevision: candidate.entry.revision,
            evidence: const ['course:retry-auth'],
            bodyAddition: '重试时补充',
          );
        }),
      );
      final rescanned = await restarted.prepare(retryRequest);
      expect(rescanned.outcome, ContentIntakeOutcome.augmented);
      expect(comparisonCalls, 2);
      final applied = await restarted.commit(
        rescanned,
        authorizationGuard: (_) async => true,
      );
      expect(applied.outcome, ContentIntakeOutcome.augmented);
      expect(
        (await harness.tables.readEntry(original.entryId!))?.body,
        contains('重试时补充'),
      );
    },
  );

  test(
    'explicit evidence recalls changed title for field augmentation',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      var table = await harness.tables.createTable(title: '数学考试');
      table = await harness.tables.updateTable(
        table.copyWith(
          fields: [
            TableFieldDefinition(
              id: 'fld_location',
              name: '地点',
              type: CustomFieldType.text,
            ),
          ],
        ),
        expectedRevision: table.revision,
      );
      var semanticCalls = 0;
      final intake = ContentIntake(
        tables: harness.tables,
        entryIdFactory: (_) => 'nt_math_exam',
        semanticDecisionSource: _DecisionSource((request) async {
          semanticCalls++;
          expect(request.signal.title, '数学考试补充地点');
          expect(request.candidates, hasLength(1));
          return SemanticDuplicateDecision(
            action: SemanticDuplicateAction.augment,
            targetId: request.candidates.single.entry.id,
            expectedRevision: request.candidates.single.entry.revision,
            evidence: const ['course:signals'],
            bodyAddition: '地点：三教 101',
            fieldAdditions: const {'fld_location': '三教 101'},
          );
        }),
      );
      final first = await intake.commit(
        await intake.prepare(
          ContentIntakeRequest(
            operationId: 'math-exam-first',
            tableId: table.id,
            type: TableContentType.note,
            title: '数学考试安排',
            body: '考试范围：第二章',
            identity: ContentBusinessIdentity(
              evidence: const ['course:signals', 'exam:midterm-2026'],
            ),
          ),
        ),
      );
      final preparation = await intake.prepare(
        ContentIntakeRequest(
          operationId: 'math-exam-location',
          tableId: table.id,
          type: TableContentType.note,
          title: '数学考试补充地点',
          body: '地点：三教 101',
          identity: ContentBusinessIdentity(
            evidence: const ['course:signals', 'exam:midterm-2026'],
          ),
        ),
      );
      final augmented = await intake.commit(preparation);

      expect(semanticCalls, 1);
      expect(preparation.outcome, ContentIntakeOutcome.augmented);
      expect(augmented.entryId, first.entryId);
      expect(augmented.entry?.body, contains('考试范围：第二章'));
      expect(augmented.entry?.body, contains('地点：三教 101'));
      expect(augmented.entry?.customValues['fld_location'], '三教 101');
    },
  );

  test('derived title hash alone never recalls a semantic merge', () async {
    final harness = await _Harness.create();
    addTearDown(harness.close);
    final table = await harness.tables.createTable(title: '无显式身份');
    var semanticCalls = 0;
    var nextId = 0;
    final intake = ContentIntake(
      tables: harness.tables,
      entryIdFactory: (_) => 'nt_derived_${nextId++}',
      semanticDecisionSource: _DecisionSource((request) async {
        semanticCalls++;
        return SemanticDuplicateDecision(
          action: SemanticDuplicateAction.conflict,
        );
      }),
    );
    await intake.commit(
      await intake.prepare(
        ContentIntakeRequest(
          operationId: 'derived-first',
          tableId: table.id,
          type: TableContentType.note,
          title: '数学考试安排',
          body: '第二章',
        ),
      ),
    );
    final second = await intake.commit(
      await intake.prepare(
        ContentIntakeRequest(
          operationId: 'derived-second',
          tableId: table.id,
          type: TableContentType.note,
          title: '数学考试补充地点',
          body: '地点：三教 101',
        ),
      ),
    );

    expect(semanticCalls, 0);
    expect(second.outcome, ContentIntakeOutcome.created);
    expect(
      await harness.tables.searchEntries(query: '', limit: 100),
      hasLength(2),
    );
  });

  test(
    'legacy entries without stored evidence still deduplicate exactly',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final table = await harness.tables.createTable(title: '旧内容');
      final createdAt = DateTime.parse('2026-11-03T08:00:00+08:00');
      await harness.tables.createEntry(
        TableEntryDocument(
          id: 'nt_legacy_existing',
          type: TableContentType.note,
          tableId: table.id,
          title: '旧入口内容',
          revision: 1,
          createdAt: createdAt,
          updatedAt: createdAt,
          body: '旧数据正文',
        ),
      );
      final intake = ContentIntake(tables: harness.tables);
      final preparation = await intake.prepare(
        ContentIntakeRequest(
          operationId: 'legacy-entry-match',
          tableId: table.id,
          type: TableContentType.note,
          title: '旧入口内容',
          body: '旧数据正文',
          identity: ContentBusinessIdentity(
            evidence: [
              contentObjectEvidenceKey(
                type: TableContentType.note,
                title: '旧入口内容',
              ),
            ],
          ),
        ),
      );
      final result = await intake.commit(preparation);

      expect(result.outcome, ContentIntakeOutcome.reused);
      expect(result.entryId, 'nt_legacy_existing');
    },
  );

  test(
    'semantic evidence augments existing content without losing it',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      var table = await harness.tables.createTable(title: '考试');
      table = await harness.tables.updateTable(
        table.copyWith(
          fields: [
            TableFieldDefinition(
              id: 'fld_room',
              name: '地点',
              type: CustomFieldType.text,
            ),
          ],
        ),
        expectedRevision: table.revision,
      );
      final decisionSource = _DecisionSource(
        (request) async => SemanticDuplicateDecision(
          action: SemanticDuplicateAction.augment,
          targetId: request.candidates.single.entry.id,
          expectedRevision: request.candidates.single.entry.revision,
          evidence: const ['exam:signals-midterm'],
          bodyAddition: '新增范围：第三章',
          fieldAdditions: const {'fld_room': '三教 101'},
        ),
      );
      final intake = ContentIntake(
        tables: harness.tables,
        semanticDecisionSource: decisionSource,
        entryIdFactory: (_) => 'nt_augment_source',
      );
      final initial = _noteRequest(
        operationId: 'augment-initial',
        tableId: table.id,
        title: '期中考试范围',
        body: '原范围：第一章',
        evidence: const ['exam:signals-midterm'],
      );
      final first = await intake.commit(await intake.prepare(initial));

      final later = await intake.prepare(
        _noteRequest(
          operationId: 'augment-later',
          tableId: table.id,
          title: '期中考试范围',
          body: '原范围：第一章；新增范围：第三章',
          evidence: const ['exam:signals-midterm'],
        ),
      );
      final augmented = await intake.commit(later);

      expect(first.outcome, ContentIntakeOutcome.created);
      expect(later.outcome, ContentIntakeOutcome.augmented);
      expect(augmented.outcome, ContentIntakeOutcome.augmented);
      expect(augmented.entryId, first.entryId);
      expect(augmented.oldRevision, 1);
      expect(augmented.newRevision, 2);
      expect(augmented.entry?.body, contains('原范围：第一章'));
      expect(augmented.entry?.body, contains('新增范围：第三章'));
      expect(augmented.entry?.customValues['fld_room'], '三教 101');
      expect(augmented.changes.bodyAppended, isTrue);
      expect(augmented.changes.fieldChanges, contains('fld_room'));
    },
  );

  test('conflicting semantic field values stop before writing', () async {
    final harness = await _Harness.create();
    addTearDown(harness.close);
    var table = await harness.tables.createTable(title: '教室');
    table = await harness.tables.updateTable(
      table.copyWith(
        fields: [
          TableFieldDefinition(
            id: 'fld_room',
            name: '地点',
            type: CustomFieldType.text,
          ),
        ],
      ),
      expectedRevision: table.revision,
    );
    final bootstrap = ContentIntake(
      tables: harness.tables,
      entryIdFactory: (_) => 'nt_field_conflict',
    );
    final initial = ContentIntakeRequest(
      operationId: 'field-conflict-initial',
      tableId: table.id,
      type: TableContentType.note,
      title: '期末考试地点',
      body: '原通知',
      identity: ContentBusinessIdentity(evidence: const ['exam:field']),
      customValues: const {'fld_room': '三教 101'},
    );
    await bootstrap.commit(await bootstrap.prepare(initial));
    final decisionSource = _DecisionSource(
      (request) async => SemanticDuplicateDecision(
        action: SemanticDuplicateAction.augment,
        targetId: request.candidates.single.entry.id,
        expectedRevision: request.candidates.single.entry.revision,
        evidence: const ['exam:field'],
        bodyAddition: '另一张通知',
        fieldAdditions: const {'fld_room': '四教 202'},
      ),
    );
    final intake = ContentIntake(
      tables: harness.tables,
      semanticDecisionSource: decisionSource,
    );
    final preparation = await intake.prepare(
      ContentIntakeRequest(
        operationId: 'field-conflict-later',
        tableId: table.id,
        type: TableContentType.note,
        title: '期末考试地点',
        body: '原通知和另一张通知',
        identity: ContentBusinessIdentity(evidence: const ['exam:field']),
        customValues: const {'fld_room': '四教 202'},
      ),
    );

    expect(preparation.outcome, ContentIntakeOutcome.conflict);
    expect(preparation.reason, contains('不能自动覆盖'));
    expect(
      (await harness.tables.readEntry('nt_field_conflict'))?.customValues,
      {'fld_room': '三教 101'},
    );
  });

  test('full-access conflict policy creates a separate review item', () async {
    final harness = await _Harness.create();
    addTearDown(harness.close);
    final table = await harness.tables.createTable(title: '考试');
    final bootstrap = ContentIntake(
      tables: harness.tables,
      entryIdFactory: (_) => 'nt_conflict_existing',
    );
    await bootstrap.commit(
      await bootstrap.prepare(
        _noteRequest(
          operationId: 'conflict-existing',
          tableId: table.id,
          title: '期中考试',
          body: '第三章',
          evidence: const ['exam:midterm'],
        ),
      ),
    );
    final intake = ContentIntake(
      tables: harness.tables,
      entryIdFactory: (_) => 'nt_conflict_review',
      semanticDecisionSource: _DecisionSource(
        (_) async => SemanticDuplicateDecision(
          action: SemanticDuplicateAction.conflict,
          reason: '候选可能是同一考试，但范围不同。',
        ),
      ),
    );
    final preparation = await intake.prepare(
      _noteRequest(
        operationId: 'conflict-create-review',
        tableId: table.id,
        title: '期中考试',
        body: '第四章',
        evidence: const ['exam:midterm'],
        conflictPolicy: ContentIntakeConflictPolicy.createWithReview,
      ),
    );

    expect(preparation.outcome, ContentIntakeOutcome.created);
    expect(preparation.reviewRequired, isTrue);
    final result = await intake.commit(preparation);
    expect(result.outcome, ContentIntakeOutcome.created);
    expect(result.reviewRequired, isTrue);
    expect(result.entryId, 'nt_conflict_review');
    expect(
      await harness.tables.searchEntries(
        query: '期中考试',
        tableId: table.id,
        limit: 20,
      ),
      hasLength(2),
    );
  });

  test('local policy rejects semantic evidence it cannot verify', () async {
    final harness = await _Harness.create();
    addTearDown(harness.close);
    final table = await harness.tables.createTable(title: '笔记');
    final bootstrap = ContentIntake(
      tables: harness.tables,
      entryIdFactory: (_) => 'nt_policy_source',
    );
    await bootstrap.commit(
      await bootstrap.prepare(
        _noteRequest(
          operationId: 'policy-initial',
          tableId: table.id,
          title: '同一标题',
          body: '完整原文',
          evidence: const ['entity:alpha'],
        ),
      ),
    );
    final unsafeDecision = _DecisionSource(
      (request) async => SemanticDuplicateDecision(
        action: SemanticDuplicateAction.augment,
        targetId: request.candidates.single.entry.id,
        expectedRevision: request.candidates.single.entry.revision,
        evidence: const ['title:同一标题'],
        bodyAddition: '模型声称是同一件事',
      ),
    );
    final intake = ContentIntake(
      tables: harness.tables,
      semanticDecisionSource: unsafeDecision,
    );
    final preparation = await intake.prepare(
      _noteRequest(
        operationId: 'policy-unsafe',
        tableId: table.id,
        title: '同一标题',
        body: '完整原文和新增内容',
        evidence: const ['entity:alpha'],
      ),
    );
    final result = await intake.commit(preparation);

    expect(preparation.outcome, ContentIntakeOutcome.conflict);
    expect(result.outcome, ContentIntakeOutcome.conflict);
    expect(result.reason, contains('证据'));
    final entries = await harness.tables.searchEntries(
      query: '',
      tableId: table.id,
      limit: 100,
    );
    expect(entries.single.body, '完整原文');
  });

  test('commit rejects a target changed after preparation', () async {
    final harness = await _Harness.create();
    addTearDown(harness.close);
    final table = await harness.tables.createTable(title: '并发目标');
    final bootstrap = ContentIntake(
      tables: harness.tables,
      entryIdFactory: (_) => 'nt_stale_target',
    );
    final created = await bootstrap.commit(
      await bootstrap.prepare(
        _noteRequest(
          operationId: 'stale-initial',
          tableId: table.id,
          title: '课程安排',
          body: '原内容',
          evidence: const ['course:stale'],
        ),
      ),
    );
    final decisionSource = _DecisionSource(
      (request) async => SemanticDuplicateDecision(
        action: SemanticDuplicateAction.augment,
        targetId: request.candidates.single.entry.id,
        expectedRevision: request.candidates.single.entry.revision,
        evidence: const ['course:stale'],
        bodyAddition: '模型补充',
      ),
    );
    final intake = ContentIntake(
      tables: harness.tables,
      semanticDecisionSource: decisionSource,
    );
    final preparation = await intake.prepare(
      _noteRequest(
        operationId: 'stale-later',
        tableId: table.id,
        title: '课程安排',
        body: '原内容和模型补充',
        evidence: const ['course:stale'],
      ),
    );
    final original = (await harness.tables.readEntry(created.entryId!))!;
    await harness.tables.updateEntry(
      original.copyWith(body: '人工并发修改'),
      expectedRevision: original.revision,
    );

    final result = await intake.commit(preparation);

    expect(result.outcome, ContentIntakeOutcome.conflict);
    expect(result.reason, contains('版本'));
    expect((await harness.tables.readEntry(created.entryId!))?.body, '人工并发修改');
  });

  test(
    'commit rejects a table structure version changed after preparation',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final table = await harness.tables.createTable(title: '结构版本');
      final bootstrap = ContentIntake(
        tables: harness.tables,
        entryIdFactory: (_) => 'nt_table_version',
      );
      final created = await bootstrap.commit(
        await bootstrap.prepare(
          _noteRequest(
            operationId: 'table-version-initial',
            tableId: table.id,
            title: '课程变化',
            body: '原正文',
            evidence: const ['course:version'],
          ),
        ),
      );
      final decisionSource = _DecisionSource(
        (request) async => SemanticDuplicateDecision(
          action: SemanticDuplicateAction.augment,
          targetId: request.candidates.single.entry.id,
          expectedRevision: request.candidates.single.entry.revision,
          evidence: const ['course:version'],
          bodyAddition: '补充正文',
        ),
      );
      final intake = ContentIntake(
        tables: harness.tables,
        semanticDecisionSource: decisionSource,
      );
      final preparation = await intake.prepare(
        _noteRequest(
          operationId: 'table-version-later',
          tableId: table.id,
          title: '课程变化',
          body: '原正文和补充正文',
          evidence: const ['course:version'],
        ),
      );
      final currentTable = harness.tables.findTable(table.id)!;
      await harness.tables.updateTable(
        currentTable.copyWith(body: '并发修改表正文'),
        expectedRevision: currentTable.revision,
      );

      final result = await intake.commit(preparation);

      expect(result.outcome, ContentIntakeOutcome.conflict);
      expect(result.reason, contains('所属表'));
      expect((await harness.tables.readEntry(created.entryId!))?.body, '原正文');
    },
  );

  test(
    'commit rechecks exact duplicates and does not create another copy',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final table = await harness.tables.createTable(title: '并发新增');
      final firstIntake = ContentIntake(
        tables: harness.tables,
        entryIdFactory: (_) => 'nt_parallel_first',
      );
      final secondIntake = ContentIntake(
        tables: harness.tables,
        entryIdFactory: (_) => 'nt_parallel_second',
      );
      final firstPreparation = await firstIntake.prepare(
        _noteRequest(
          operationId: 'parallel-first',
          tableId: table.id,
          title: '考试地点',
          body: '三教 101',
          evidence: const ['exam:parallel'],
        ),
      );
      final secondPreparation = await secondIntake.prepare(
        _noteRequest(
          operationId: 'parallel-second',
          tableId: table.id,
          title: '考试地点',
          body: '三教 101',
          evidence: const ['exam:parallel'],
        ),
      );
      final parallel = await Future.wait([
        firstIntake.commit(firstPreparation),
        secondIntake.commit(secondPreparation),
      ]);
      final replayed = await secondIntake.commit(secondPreparation);

      expect(
        parallel.map((result) => result.outcome),
        containsAll([
          ContentIntakeOutcome.created,
          ContentIntakeOutcome.reused,
        ]),
      );
      expect(parallel[0].entryId, parallel[1].entryId);
      expect(replayed.replayed, isTrue);
      expect(replayed.entryId, parallel[0].entryId);
      expect(
        await harness.tables.searchEntries(
          query: '',
          tableId: table.id,
          limit: 100,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'create commit rejects a table snapshot changed after preparation',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final table = await harness.tables.createTable(title: '授权等待并发');
      final intake = ContentIntake(
        tables: harness.tables,
        entryIdFactory: (_) => 'nt_auth_wait',
      );
      final preparation = await intake.prepare(
        _noteRequest(
          operationId: 'auth-wait-create',
          tableId: table.id,
          title: '新内容',
          body: '新正文',
          evidence: const [],
        ),
      );
      await harness.tables.createEntry(
        TableEntryDocument(
          id: 'nt_auth_wait_concurrent',
          type: TableContentType.note,
          tableId: table.id,
          title: '另一个写入',
          revision: 1,
          createdAt: DateTime.utc(2026, 11, 4),
          updatedAt: DateTime.utc(2026, 11, 4),
          body: '准备后发生的并发写入。',
        ),
      );
      final result = await intake.commit(preparation);

      expect(result.outcome, ContentIntakeOutcome.conflict);
      expect(await harness.tables.readEntry('nt_auth_wait'), isNull);
      expect(
        await harness.tables.readEntry('nt_auth_wait_concurrent'),
        isNotNull,
      );
    },
  );

  test(
    'augment commit rejects a target snapshot changed after preparation',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final table = await harness.tables.createTable(title: '授权等待目标');
      final initialIntake = ContentIntake(
        tables: harness.tables,
        entryIdFactory: (_) => 'nt_auth_wait_target',
      );
      final initialPreparation = await initialIntake.prepare(
        _noteRequest(
          operationId: 'auth-wait-target-base',
          tableId: table.id,
          title: '考试安排',
          body: '已有安排',
          evidence: const ['exam:auth-wait'],
        ),
      );
      final created = await initialIntake.commit(initialPreparation);
      final intake = ContentIntake(
        tables: harness.tables,
        semanticDecisionSource: _DecisionSource((request) async {
          return SemanticDuplicateDecision(
            action: SemanticDuplicateAction.augment,
            targetId: request.candidates.single.entry.id,
            expectedRevision: request.candidates.single.entry.revision,
            evidence: const ['exam:auth-wait'],
            bodyAddition: '后来补充',
          );
        }),
      );
      final preparation = await intake.prepare(
        _noteRequest(
          operationId: 'auth-wait-target-augment',
          tableId: table.id,
          title: '考试安排',
          body: '后来补充',
          evidence: const ['exam:auth-wait'],
        ),
      );
      final current = (await harness.tables.readEntry(created.entryId!))!;
      await harness.tables.updateEntry(
        current.copyWith(body: '准备后发生的外部修改'),
        expectedRevision: current.revision,
      );
      final result = await intake.commit(preparation);

      expect(result.outcome, ContentIntakeOutcome.conflict);
      expect(
        (await harness.tables.readEntry(created.entryId!))?.body,
        '准备后发生的外部修改',
      );
    },
  );

  test('revocation while ContentIntake waits for the Repository lock writes nothing', () async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    final tables = TableLibrary(
      repository: TableRepository(vault: vault, index: index),
    );
    await tables.initialize();
    final table = await tables.createTable(title: '锁内撤权');
    final intake = ContentIntake(
      tables: tables,
      entryIdFactory: (_) => 'nt_revoked_before_lock',
    );
    final preparation = await intake.prepare(
      _noteRequest(
        operationId: 'revoked-before-repository-lock',
        tableId: table.id,
        title: '未授权内容',
        body: '不应落盘',
        evidence: const [],
      ),
    );
    var allowWrites = true;
    var guardCalls = 0;
    late Future<ContentIntakeResult> pendingCommit;

    await vault.exclusive(() async {
      pendingCommit = intake.commit(
        preparation,
        authorizationGuard: (_) async {
          guardCalls++;
          return allowWrites;
        },
        persistAuthorizationConflict: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(guardCalls, 0);
      allowWrites = false;
    });

    final result = await pendingCommit;
    expect(result.outcome, ContentIntakeOutcome.conflict);
    expect(guardCalls, 1);
    expect(await tables.readEntry('nt_revoked_before_lock'), isNull);
    expect(index.findTableEntry('nt_revoked_before_lock'), completion(isNull));
    expect(
      vault.files[TableRepository.entryPath('nt_revoked_before_lock')],
      isNull,
    );
    expect(
      vault.files[TableRepository.intakeOperationPath(
        'revoked-before-repository-lock',
      )],
      isNull,
    );
  });

  test(
    'automatic intake cannot persist a forged manual keep-both exception',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final table = await harness.tables.createTable(title: '例外凭据边界');
      final intake = ContentIntake(tables: harness.tables);
      final preparation = await intake.prepare(
        ContentIntakeRequest(
          operationId: 'forged-manual-exception',
          tableId: table.id,
          type: TableContentType.note,
          title: '普通内容',
          body: '不允许模型提供人工例外凭据。',
          extensionFields: {
            'manual_duplicate_exception': {
              'decision': 'keep_both',
              'reason': '伪造的模型选择',
            },
          },
        ),
      );
      final result = await intake.commit(preparation);

      expect(result.outcome, ContentIntakeOutcome.created);
      expect(
        result.entry!.extensionFields,
        isNot(contains('manual_duplicate_exception')),
      );
    },
  );

  test(
    'semantic create decision accepts a distinct item beside a candidate',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final table = await harness.tables.createTable(title: '相似候选但不同事项');
      await _seedSemanticCandidates(harness, table, count: 1);
      final intake = ContentIntake(
        tables: harness.tables,
        semanticDecisionSource: _DecisionSource(
          (_) async =>
              SemanticDuplicateDecision(action: SemanticDuplicateAction.create),
        ),
      );

      final preparation = await intake.prepare(
        _noteRequest(
          operationId: 'semantic-distinct-item',
          tableId: table.id,
          title: '同一课程',
          body: '这是不同日期的另一件事。',
          evidence: const ['course:signals'],
        ),
      );

      expect(preparation.outcome, ContentIntakeOutcome.created);
      expect(preparation.coverage.semanticCandidatesChecked, 1);
      expect(preparation.coverage.semanticComparisonComplete, isTrue);

      final result = await intake.commit(preparation);
      expect(result.outcome, ContentIntakeOutcome.created);
      expect(harness.tables.entries, hasLength(2));
    },
  );

  test('semantic intake pages past ten candidates and augments the later unique target', () async {
    final harness = await _Harness.create();
    addTearDown(harness.close);
    final table = await harness.tables.createTable(title: '分页候选');
    final target = await _seedSemanticCandidates(harness, table, count: 11);
    final pageSizes = <int>[];
    final intake = ContentIntake(
      tables: harness.tables,
      semanticDecisionSource: _DecisionSource((request) async {
        pageSizes.add(request.candidates.length);
        final hasTarget = request.candidates.any(
          (candidate) => candidate.entry.id == target.id,
        );
        if (!hasTarget) {
          return SemanticDuplicateDecision(
            action: SemanticDuplicateAction.create,
          );
        }
        final match = request.candidates.firstWhere(
          (candidate) => candidate.entry.id == target.id,
        );
        return SemanticDuplicateDecision(
          action: SemanticDuplicateAction.augment,
          targetId: match.entry.id,
          expectedRevision: match.entry.revision,
          evidence: const ['course:signals'],
          bodyAddition: '后页核实出的补充事实',
        );
      }),
    );
    final preparation = await intake.prepare(
      _noteRequest(
        operationId: 'intake-late-page-target',
        tableId: table.id,
        title: '同一课程',
        body: '后页核实出的补充事实',
        evidence: const ['course:signals'],
      ),
    );

    expect(preparation.coverage.semanticCandidatesTotal, 11);
    expect(pageSizes, [10, 1]);
    expect(preparation.outcome, ContentIntakeOutcome.augmented);
    expect(preparation.targetId, target.id);
    expect(preparation.coverage.semanticCandidatesChecked, 11);
    expect(preparation.coverage.semanticCandidatesTotal, 11);
    expect(preparation.coverage.semanticCandidatesRemaining, 0);
    expect(preparation.coverage.semanticComparisonComplete, isTrue);

    final result = await intake.commit(preparation);
    expect(result.outcome, ContentIntakeOutcome.augmented);
    expect(
      (await harness.tables.readEntry(target.id))?.body,
      contains('后页核实出的补充事实'),
    );
    expect(harness.tables.entries, hasLength(11));
  });

  test(
    'semantic intake blocks conflicting targets found on different pages',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final table = await harness.tables.createTable(title: '跨页冲突');
      await _seedSemanticCandidates(harness, table, count: 11);
      var page = 0;
      final intake = ContentIntake(
        tables: harness.tables,
        semanticDecisionSource: _DecisionSource((request) async {
          page++;
          final candidate = request.candidates.first;
          return SemanticDuplicateDecision(
            action: SemanticDuplicateAction.augment,
            targetId: candidate.entry.id,
            expectedRevision: candidate.entry.revision,
            evidence: const ['course:signals'],
            bodyAddition: '补充事实 $page',
          );
        }),
      );
      final preparation = await intake.prepare(
        _noteRequest(
          operationId: 'intake-cross-page-conflict',
          tableId: table.id,
          title: '同一课程',
          body: '补充事实',
          evidence: const ['course:signals'],
        ),
      );

      expect(page, 2);
      expect(preparation.outcome, ContentIntakeOutcome.conflict);
      expect(preparation.reason, contains('不同内容'));
      expect(preparation.coverage.semanticCandidatesChecked, 11);
      expect(preparation.coverage.semanticComparisonComplete, isTrue);
    },
  );

  test(
    'semantic intake reports unexamined pages when budget runs out',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final table = await harness.tables.createTable(title: '分页预算');
      await _seedSemanticCandidates(harness, table, count: 11);
      var page = 0;
      final intake = ContentIntake(
        tables: harness.tables,
        semanticDecisionSource: _DecisionSource((request) async {
          page++;
          if (page == 1) {
            return SemanticDuplicateDecision(
              action: SemanticDuplicateAction.create,
            );
          }
          return SemanticDuplicateDecision(
            action: SemanticDuplicateAction.conflict,
            reason: '共享模型请求预算已用尽。',
            comparisonComplete: false,
          );
        }),
      );
      final request = _noteRequest(
        operationId: 'intake-page-budget',
        tableId: table.id,
        title: '同一课程',
        body: '新信息',
        evidence: const ['course:signals'],
      );
      final preparation = await intake.prepare(request);

      expect(page, 2);
      expect(preparation.outcome, ContentIntakeOutcome.conflict);
      expect(preparation.reason, contains('预算已用尽'));
      expect(preparation.coverage.semanticCandidatesChecked, 10);
      expect(preparation.coverage.semanticCandidatesTotal, 11);
      expect(preparation.coverage.semanticCandidatesRemaining, 1);
      expect(preparation.coverage.semanticComparisonComplete, isFalse);

      final result = await intake.commit(preparation);
      expect(result.outcome, ContentIntakeOutcome.conflict);
      expect(result.coverage.semanticCandidatesRemaining, 1);
      expect(result.coverage.semanticComparisonComplete, isFalse);
      expect(result.reason, contains('预算已用尽'));

      final resumed = await ContentIntake(tables: harness.tables)
          .prepare(request);
      expect(resumed.outcome, ContentIntakeOutcome.conflict);
      expect(resumed.coverage.semanticCandidatesRemaining, 1);
      expect(resumed.coverage.semanticComparisonComplete, isFalse);
    },
  );

  test(
    'semantic intake records revoked permission as incomplete coverage',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final table = await harness.tables.createTable(title: '分页撤权');
      await _seedSemanticCandidates(harness, table, count: 11);
      var page = 0;
      final intake = ContentIntake(
        tables: harness.tables,
        semanticDecisionSource: _DecisionSource((request) async {
          page++;
          if (page == 1) {
            return SemanticDuplicateDecision(
              action: SemanticDuplicateAction.create,
            );
          }
          return SemanticDuplicateDecision(
            action: SemanticDuplicateAction.conflict,
            reason: '候选读取权限已撤销。',
            comparisonComplete: false,
          );
        }),
      );
      final request = _noteRequest(
        operationId: 'intake-page-permission-revoked',
        tableId: table.id,
        title: '同一课程',
        body: '新信息',
        evidence: const ['course:signals'],
      );
      final preparation = await intake.prepare(request);
      expect(preparation.outcome, ContentIntakeOutcome.conflict);
      expect(preparation.reason, contains('权限已撤销'));
      expect(preparation.coverage.semanticCandidatesChecked, 10);
      expect(preparation.coverage.semanticCandidatesTotal, 11);
      expect(preparation.coverage.semanticCandidatesRemaining, 1);
      expect(preparation.coverage.semanticComparisonComplete, isFalse);

      final result = await intake.commit(preparation);
      expect(result.outcome, ContentIntakeOutcome.conflict);
      expect(result.coverage.semanticCandidatesRemaining, 1);
      expect(result.coverage.semanticComparisonComplete, isFalse);
    },
  );
}

ContentIntakeRequest _noteRequest({
  required String operationId,
  required String tableId,
  required String title,
  required String body,
  required List<String> evidence,
  ContentIntakeConflictPolicy conflictPolicy = ContentIntakeConflictPolicy.ask,
}) => ContentIntakeRequest(
  operationId: operationId,
  tableId: tableId,
  type: TableContentType.note,
  title: title,
  body: body,
  identity: ContentBusinessIdentity(evidence: evidence),
  conflictPolicy: conflictPolicy,
);

class _Harness {
  _Harness({required this.tables});

  final TableLibrary tables;

  static Future<_Harness> create() async {
    final tables = TableLibrary(
      repository: TableRepository(
        vault: MemoryVaultStore(),
        index: MemoryIndexDatabase(),
      ),
    );
    await tables.initialize();
    return _Harness(tables: tables);
  }

  Future<void> close() async {}
}

Future<TableEntryDocument> _seedSemanticCandidates(
  _Harness harness,
  TableDocument table, {
  required int count,
}) async {
  late TableEntryDocument target;
  for (var index = 0; index < count; index++) {
    final timestamp = DateTime.utc(2026, 11, 4).subtract(Duration(days: index));
    final entry = TableEntryDocument(
      id: 'nt_page_${index.toString().padLeft(2, '0')}',
      type: TableContentType.note,
      tableId: table.id,
      title: '同一课程',
      revision: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
      body: '已有信息 $index',
      extensionFields: {
        contentIntakeEvidenceExtensionKey: const ['course:signals'],
      },
    );
    await harness.tables.createEntry(entry);
    target = entry;
  }
  return target;
}

class _SequentialIdFactory {
  var _value = 0;

  String call(TableContentType _) => 'nt_exact_${_value++}';
}

class _DecisionSource implements SemanticDuplicateDecisionSource {
  _DecisionSource(this._decision);

  final Future<SemanticDuplicateDecision> Function(SemanticDuplicateRequest)
  _decision;

  @override
  Future<SemanticDuplicateDecision> decide(SemanticDuplicateRequest request) =>
      _decision(request);
}
