import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/table_markdown_codec.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/modules/conversation/manual_content_intake.dart';
import 'package:personal_ai_inbox/modules/tables/table_library.dart';

void main() {
  late MemoryVaultStore vault;
  late TableLibrary tables;
  late TableDocument target;
  late DateTime now;

  setUp(() async {
    vault = MemoryVaultStore();
    tables = TableLibrary(
      repository: TableRepository(vault: vault, index: MemoryIndexDatabase()),
    );
    await tables.initialize();
    target = await tables.createTable(title: '手工查重测试');
    now = DateTime.utc(2026, 11, 4, 3);
  });

  TableEntryDocument note(
    String id, {
    String body = '信号系统第二章',
    int revision = 1,
  }) => TableEntryDocument(
    id: id,
    type: TableContentType.note,
    tableId: target.id,
    title: '考试范围',
    revision: revision,
    createdAt: now,
    updatedAt: now,
    body: body,
  );

  test(
    'exact manual duplicate can reuse original ID without writing a copy',
    () async {
      final original = await tables.createEntry(note('nt_manual_original'));
      final intake = ManualContentIntake(tables);
      final review = await intake.review(note('nt_manual_new'));

      expect(review.exactIds, contains(original.id));
      final result = await intake.commit(
        review,
        choice: ManualDuplicateChoice.reuse,
      );

      expect(result.id, original.id);
      expect((await tables.readEntry('nt_manual_new')), isNull);
    },
  );

  test(
    'keep both stores an explicit exception bound to exact reviewed candidates',
    () async {
      final original = await tables.createEntry(note('nt_manual_original'));
      final intake = ManualContentIntake(tables, clock: () => now);
      final input = note('nt_manual_new', body: '信号系统第二章及第三章');
      final review = await intake.review(input);
      expect(review.exactIds, isEmpty);
      expect(review.matches.map((entry) => entry.id), contains(original.id));

      final saved = await intake.commit(
        review,
        choice: ManualDuplicateChoice.keepBoth,
      );
      final credential =
          saved.extensionFields['manual_duplicate_exception'] as Map;
      expect(credential['decision'], 'keep_both');
      expect(credential['input_fingerprint'], isA<String>());
      expect(credential['target_table_id'], target.id);
      expect((credential['candidates'] as List).single['id'], original.id);
      expect(
        tables.entries.where((entry) => entry.tableId == target.id),
        hasLength(2),
      );
    },
  );

  test(
    'candidate added or changed after review blocks a keep-both save',
    () async {
      await tables.createEntry(note('nt_manual_original'));
      final intake = ManualContentIntake(tables);
      final review = await intake.review(
        note('nt_manual_new', body: '信号系统第二章及第三章'),
      );
      await tables.createEntry(
        note('nt_manual_new_candidate', body: '信号系统第二章及第三章'),
      );

      await expectLater(
        intake.commit(review, choice: ManualDuplicateChoice.keepBoth),
        throwsA(isA<StateError>()),
      );
      expect(await tables.readEntry('nt_manual_new'), isNull);
    },
  );

  test(
    'same-revision candidate file edit after review blocks the save',
    () async {
      await tables.createEntry(note('nt_manual_original'));
      final intake = ManualContentIntake(tables);
      final review = await intake.review(
        note('nt_manual_new', body: '信号系统第二章及第三章'),
      );
      final changed = note('nt_manual_original', body: '信号系统第三章');
      await vault.write(
        TableRepository.entryPath(changed.id),
        const TableMarkdownCodec().encodeEntry(changed),
      );

      await expectLater(
        intake.commit(review, choice: ManualDuplicateChoice.keepBoth),
        throwsA(isA<StateError>()),
      );
      expect(await tables.readEntry('nt_manual_new'), isNull);
    },
  );

  test('target field revision change after review blocks the save', () async {
    await tables.createEntry(note('nt_manual_original'));
    final intake = ManualContentIntake(tables);
    final review = await intake.review(
      note('nt_manual_new', body: '信号系统第二章及第三章'),
    );
    await tables.updateTable(
      target.copyWith(
        fields: [
          TableFieldDefinition(
            id: 'fld_term',
            name: '学期',
            type: CustomFieldType.text,
          ),
        ],
      ),
      expectedRevision: target.revision,
    );

    await expectLater(
      intake.commit(review, choice: ManualDuplicateChoice.keepBoth),
      throwsA(isA<StateError>()),
    );
    expect(await tables.readEntry('nt_manual_new'), isNull);
  });

  test('a prior keep-both credential cannot authorize a later save', () async {
    final original = await tables.createEntry(
      note('nt_manual_original').copyWith(
        extensionFields: {
          'manual_duplicate_exception': {
            'decision': 'keep_both',
            'input_fingerprint': 'old-decision',
          },
        },
      ),
    );
    final intake = ManualContentIntake(tables);
    final review = await intake.review(note('nt_manual_new'));

    expect(review.exactIds, contains(original.id));
    expect(() => intake.commit(review), throwsA(isA<StateError>()));
    expect(await tables.readEntry('nt_manual_new'), isNull);
  });

  test(
    'edit cannot reuse a duplicate and rechecks the edited object before reuse',
    () async {
      final original = await tables.createEntry(note('nt_manual_original'));
      final edited = await tables.createEntry(
        note('nt_manual_edited', body: '旧正文'),
      );
      final intake = ManualContentIntake(tables);
      final proposed = edited.copyWith(
        title: original.title,
        body: original.body,
      );
      final review = await intake.review(
        proposed,
        expectedRevision: edited.revision,
      );

      expect(
        () => intake.commit(review, choice: ManualDuplicateChoice.reuse),
        throwsA(isA<StateError>()),
      );

      final staleReview = await intake.review(
        proposed,
        expectedRevision: edited.revision,
      );
      await tables.updateEntry(
        edited.copyWith(body: '并发更新'),
        expectedRevision: edited.revision,
      );
      await expectLater(
        intake.commit(staleReview, choice: ManualDuplicateChoice.keepBoth),
        throwsA(isA<StateError>()),
      );
      expect((await tables.readEntry(edited.id))?.body, '并发更新');
    },
  );
}
