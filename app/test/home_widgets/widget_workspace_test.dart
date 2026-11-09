import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/modules/home_widgets/home_widgets.dart';
import 'package:personal_ai_inbox/modules/tables/table_library.dart';

void main() {
  late Directory directory;
  late TableRepository repository;
  late _TestTableLibrary tables;
  late WidgetWorkspace workspace;
  late bool blocked;
  late bool failPublish;
  late Future<void> Function(String)? publishSideEffect;
  late int clearCount;
  late List<String> published;
  late int notifyCount;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('widget-workspace');
    repository = TableRepository(
      vault: MemoryVaultStore(),
      index: MemoryIndexDatabase(),
    );
    await repository.initialize();
    await repository.ensureDefaultTables();
    tables = _TestTableLibrary(repository);
    await tables.refresh();
    blocked = false;
    failPublish = false;
    publishSideEffect = null;
    clearCount = 0;
    published = [];
    notifyCount = 0;
    workspace =
        WidgetWorkspace(
          tables: tables,
          store: WidgetStore(directory.path),
          publish: (snapshot) async {
            published.add(snapshot);
            if (failPublish) throw StateError('widget bridge unavailable');
            await publishSideEffect?.call(snapshot);
            return const WidgetPublishResult.published(submittedCount: 1);
          },
          clear: () async {
            clearCount++;
          },
          blocked: () => blocked,
        )..addListener(() {
          notifyCount++;
        });
  });

  tearDown(() async {
    workspace.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'commits commands idempotently with revision and undo semantics',
    () async {
      final table = await repository.createTable(title: '作业');
      await tables.refresh();
      await workspace.initialize();
      final original = CardSpec(
        title: '学习',
        sections: [SectionSpec(tableId: table.id)],
      );
      final create = CardCommand.create(original);

      final created = await workspace.applyCardCommand(
        create,
        operationId: 'op_create',
        authorize: () async => true,
      );
      expect(created.status, CardWriteStatus.applied);
      expect(created.revision, 1);
      expect(created.publishStatus, WidgetPublishStatus.published);
      expect(notifyCount, greaterThanOrEqualTo(2));

      final publishCount = published.length;
      final replay = await workspace.applyCardCommand(
        create,
        operationId: 'op_create',
        authorize: () async => true,
      );
      expect(replay.toJson(), created.toJson());
      expect(published, hasLength(publishCount));

      final conflict = await workspace.applyCardCommand(
        CardCommand.archive(
          cardId: created.cardId,
          expectedRevision: created.revision,
        ),
        operationId: 'op_create',
        authorize: () async => true,
      );
      expect(conflict.error, WidgetCommandError.operationConflict);

      final stale = await workspace.applyCardCommand(
        CardCommand.replace(
          cardId: created.cardId,
          expectedRevision: 99,
          spec: original,
        ),
        operationId: 'op_stale',
        authorize: () async => true,
      );
      expect(stale.error, WidgetCommandError.revisionConflict);

      final replaced = await workspace.applyCardCommand(
        CardCommand.replace(
          cardId: created.cardId,
          expectedRevision: 1,
          spec: CardSpec(
            title: '改过的标题',
            sections: [SectionSpec(tableId: table.id)],
          ),
        ),
        operationId: 'op_replace',
        authorize: () async => true,
      );
      expect(replaced.revision, 2);

      final undone = await workspace.applyCardCommand(
        CardCommand.undo(
          cardId: created.cardId,
          expectedRevision: 2,
          targetOperationId: 'op_replace',
        ),
        operationId: 'op_undo',
        authorize: () async => true,
      );
      expect(undone.revision, 3);
      expect((await workspace.getCard(created.cardId))!.spec.title, '学习');

      final hidden = await workspace.applyCardCommand(
        CardCommand.setVisibility(
          cardId: created.cardId,
          expectedRevision: 3,
          visibility: WidgetVisibility.hidden,
        ),
        operationId: 'op_hidden',
        authorize: () async => true,
      );
      expect(hidden.revision, 4);
      final envelope = WidgetSnapshotEnvelope.parseJson(published.last);
      expect(envelope.cards.single.title, '桌面小组件');
      expect(envelope.cards.single.rows, isEmpty);
    },
  );

  test('undoing creation archives the card', () async {
    final table = await repository.createTable(title: '作业');
    await tables.refresh();
    await workspace.initialize();
    final created = await workspace.applyCardCommand(
      CardCommand.create(
        CardSpec(
          title: '学习',
          sections: [SectionSpec(tableId: table.id)],
        ),
      ),
      operationId: 'op_create',
      authorize: () async => true,
    );

    final undone = await workspace.applyCardCommand(
      CardCommand.undo(
        cardId: created.cardId,
        expectedRevision: 1,
        targetOperationId: 'op_create',
      ),
      operationId: 'op_undo_create',
      authorize: () async => true,
    );

    expect(undone.revision, 2);
    expect((await workspace.getCard(created.cardId))!.archived, isTrue);
    expect(await workspace.listCards(), isEmpty);
    expect(await workspace.listCards(includeArchived: true), hasLength(1));
  });

  test(
    'publish failure keeps the committed config and pending receipt',
    () async {
      final table = await repository.createTable(title: '作业');
      await tables.refresh();
      await workspace.initialize();
      failPublish = true;

      final receipt = await workspace.applyCardCommand(
        CardCommand.create(
          CardSpec(
            title: '学习',
            sections: [SectionSpec(tableId: table.id)],
          ),
        ),
        operationId: 'op_publish_failure',
        authorize: () async => true,
      );

      expect(receipt.status, CardWriteStatus.applied);
      expect(receipt.publishStatus, WidgetPublishStatus.pending);
      expect(await workspace.getCard(receipt.cardId), isNotNull);
    },
  );

  test(
    'receipt update failure returns the original applied pending receipt',
    () async {
      await workspace.initialize();
      publishSideEffect = (_) async {
        publishSideEffect = null;
        await Directory('${directory.path}/state.json.bak').create();
      };

      final receipt = await workspace.applyCardCommand(
        CardCommand.create(CardSpec(title: '学习')),
        operationId: 'op_receipt_update_failure',
        authorize: () async => true,
      );

      expect(receipt.status, CardWriteStatus.applied);
      expect(receipt.publishStatus, WidgetPublishStatus.pending);
      expect(await workspace.getCard(receipt.cardId), isNotNull);
    },
  );

  test('rechecks authorization immediately before commit', () async {
    await workspace.initialize();
    var authorizationCalls = 0;

    final receipt = await workspace.applyCardCommand(
      CardCommand.create(CardSpec(title: '学习')),
      operationId: 'op_recheck',
      authorize: () async {
        authorizationCalls++;
        return authorizationCalls == 1;
      },
    );

    expect(receipt.error, WidgetCommandError.forbidden);
    expect(await workspace.listCards(), isEmpty);
  });

  test('blocked mode clears during refresh and forbids writes', () async {
    blocked = true;
    final preInitialize = await workspace.refreshWidgets();
    expect(preInitialize.status, WidgetPublishStatus.cleared);

    await workspace.initialize();
    expect(clearCount, greaterThanOrEqualTo(2));
    expect(published, isEmpty);

    final rejected = await workspace.applyCardCommand(
      CardCommand.create(CardSpec(title: '学习')),
      operationId: 'op_blocked',
      authorize: () async => true,
    );
    expect(rejected.error, WidgetCommandError.forbidden);
    expect(clearCount, greaterThanOrEqualTo(2));
  });

  test(
    'clears when the migration gate closes during content snapshot',
    () async {
      final table = await repository.createTable(title: '作业');
      await tables.refresh();
      await workspace.initialize();
      await workspace.applyCardCommand(
        CardCommand.create(
          CardSpec(
            title: '学习',
            sections: [SectionSpec(tableId: table.id)],
          ),
        ),
        operationId: 'op_create',
        authorize: () async => true,
      );
      final before = published.length;
      final clearsBefore = clearCount;
      tables.onSnapshot = () async {
        blocked = true;
      };

      final result = await workspace.refreshWidgets();

      expect(result.status, WidgetPublishStatus.cleared);
      expect(published, hasLength(before));
      expect(clearCount, clearsBefore + 1);
    },
  );

  test(
    'coalesces table changes and publishes after the refresh delay',
    () async {
      await workspace.initialize();
      final before = published.length;
      tables.emitChange();
      tables.emitChange();

      await Future<void>.delayed(const Duration(milliseconds: 360));

      expect(published, hasLength(before + 1));
    },
  );

  test('serializes overlapping refresh requests', () async {
    final firstStarted = Completer<void>();
    final firstRelease = Completer<void>();
    var calls = 0;
    workspace.dispose();
    workspace = WidgetWorkspace(
      tables: tables,
      store: WidgetStore(directory.path),
      publish: (snapshot) async {
        calls++;
        if (calls == 1) {
          firstStarted.complete();
          await firstRelease.future;
        }
        return const WidgetPublishResult.published();
      },
      clear: () async {},
      blocked: () => false,
    );

    final first = workspace.refreshWidgets();
    await firstStarted.future;
    final second = workspace.refreshWidgets();
    firstRelease.complete();

    await Future.wait([first, second]);
    expect(calls, 2);
  });
}

class _TestTableLibrary extends TableLibrary {
  _TestTableLibrary(TableRepository repository) : super(repository: repository);

  Future<void> Function()? onSnapshot;

  @override
  Future<TableContentSnapshot> contentSnapshot() async {
    await onSnapshot?.call();
    return super.contentSnapshot();
  }

  void emitChange() => notifyListeners();
}
