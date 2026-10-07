import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';

void main() {
  late MemoryVaultStore vault;
  late MemoryIndexDatabase index;
  late ResultRepository repository;
  late ResultLibrary library;

  setUp(() async {
    vault = MemoryVaultStore();
    index = MemoryIndexDatabase();
    repository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'test-device',
    );
    library = ResultLibrary(repository: repository);
    await library.initialize();
  });

  test('publishes immutable snapshots with derived result lists', () async {
    var notifications = 0;
    library.addListener(() {
      notifications++;
    });
    final emptySnapshot = library.documents;

    final matter = await library.createManual(
      type: ResultType.matter,
      title: '英语比赛',
      tags: ['比赛'],
    );
    final todo = await library.createManual(
      type: ResultType.todo,
      title: '提交报名表',
      due: DateTime(2026, 10, 9, 18),
      matterId: matter.id,
    );
    final event = await library.createManual(
      type: ResultType.event,
      title: '赛前会议',
      start: DateTime(2026, 10, 8, 10),
      end: DateTime(2026, 10, 8, 11),
      matterId: matter.id,
    );
    final knowledge = await library.createManual(
      type: ResultType.knowledge,
      title: '比赛规则',
      body: '规则正文',
    );
    final draft = await library.createManual(
      type: ResultType.knowledge,
      title: '待整理资料',
      status: ResultStatus.draft,
      body: '草稿正文',
    );

    expect(notifications, 5);
    expect(identical(emptySnapshot, library.documents), isFalse);
    expect(library.documents, hasLength(5));
    expect(library.canonicalDocuments, hasLength(4));
    expect(library.draftDocuments.single.id, draft.id);
    expect(library.todos.single.id, todo.id);
    expect(library.events.single.id, event.id);
    expect(library.matters.single.id, matter.id);
    expect(library.knowledge.single.id, knowledge.id);
    expect(library.vaultRoot, '内存存储');
    expect(() => library.documents.clear(), throwsUnsupportedError);
    expect(
      () => library.matters.single.tags.add('新标签'),
      throwsUnsupportedError,
    );
  });

  test('saveDocument updates content and replaces the snapshot', () async {
    final created = await library.createManual(
      type: ResultType.knowledge,
      title: '原始标题',
      body: '原始正文',
      tags: ['旧标签'],
    );
    final previousSnapshot = library.documents;

    await library.saveDocument(
      created.copyWith(title: '更新标题', body: '更新正文', tags: ['新标签']),
    );

    final updated = library.findDocument(created.id)!;
    expect(identical(previousSnapshot, library.documents), isFalse);
    expect(updated.title, '更新标题');
    expect(updated.body, '更新正文');
    expect(updated.revision, 2);
    expect(updated.tags, ['新标签']);
  });

  test('toggleTodo updates only todo documents', () async {
    final todo = await library.createManual(
      type: ResultType.todo,
      title: '买牛奶',
      due: DateTime(2026, 10, 8, 18),
    );
    final knowledge = await library.createManual(
      type: ResultType.knowledge,
      title: '牛奶保存说明',
    );

    await library.toggleTodo(todo, true);
    await library.toggleTodo(knowledge, true);

    expect(library.findDocument(todo.id)!.done, isTrue);
    expect(library.findDocument(todo.id)!.revision, 2);
    expect(library.findDocument(knowledge.id)!.done, isFalse);
    expect(library.findDocument(knowledge.id)!.revision, 1);
  });

  test(
    'deleteDocument writes a tombstone and removes it from snapshots',
    () async {
      final created = await library.createManual(
        type: ResultType.todo,
        title: '删除我',
        body: '正文',
        due: DateTime(2026, 10, 8, 18),
      );

      await library.deleteDocument(created.id);

      expect(library.documents, isEmpty);
      expect(library.findDocument(created.id), isNull);
      expect(vault.files.keys, contains(created.markdownPath));
      expect(vault.files[created.markdownPath], contains('deleted: true'));
      expect((await index.findResult(created.id))!.deleted, isTrue);
    },
  );

  test('rebuildIndex restores snapshots from markdown', () async {
    final matter = await library.createManual(
      type: ResultType.matter,
      title: '重建事项',
      body: '事项正文',
    );
    final knowledge = await library.createManual(
      type: ResultType.knowledge,
      title: '重建知识',
      body: '知识正文',
    );

    await index.clear();
    expect(await index.listResults(), isEmpty);

    await library.rebuildIndex();

    expect(await index.listResults(), hasLength(2));
    expect(library.documents, hasLength(2));
    expect(library.findDocument(matter.id)!.title, '重建事项');
    expect(library.findDocument(knowledge.id)!.title, '重建知识');
  });

  test('createFromCandidate preserves candidate result fields', () async {
    final candidate = ClassificationCandidate(
      type: ResultType.event,
      title: '客户会议',
      summary: '讨论交付计划',
      confidence: 0.96,
      tags: ['客户', '会议'],
      start: DateTime(2026, 10, 9, 14),
      end: DateTime(2026, 10, 9, 15),
      allDay: false,
      recurrence: 'FREQ=WEEKLY;COUNT=4',
    );

    final created = await library.createFromCandidate(candidate);

    expect(created.status, ResultStatus.canonical);
    expect(created.type, ResultType.event);
    expect(created.title, '客户会议');
    expect(created.body, '讨论交付计划');
    expect(created.tags, ['客户', '会议']);
    expect(created.start, DateTime(2026, 10, 9, 14));
    expect(created.end, DateTime(2026, 10, 9, 15));
    expect(created.recurrence, 'FREQ=WEEKLY;COUNT=4');
    expect(library.events.single.id, created.id);
  });

  test('internal access exposes conflict and raw files only', () async {
    final internal = resultLibraryInternal(library);
    const path = 'vault/conflicts/kn_1.conflict-tablet.md';

    await internal.writeRaw(path, 'conflict');
    expect(await internal.readRaw(path), 'conflict');
    expect(await internal.listConflictFiles(), contains(path));

    await internal.deleteRaw(path);
    expect(await internal.readRaw(path), isNull);
  });
}
