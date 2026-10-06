import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';

void main() {
  late MemoryVaultStore vault;
  late MemoryIndexDatabase index;
  late ResultRepository repository;

  setUp(() async {
    vault = MemoryVaultStore();
    index = MemoryIndexDatabase();
    repository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'test-device',
    );
    await repository.initialize();
  });

  test('writes one markdown file and rebuilds index from it', () async {
    final created = await repository.create(
      type: ResultType.knowledge,
      title: '离线知识',
      body: '正文',
      tags: const ['测试'],
    );

    expect(vault.files.keys, contains(created.markdownPath));
    await index.clear();
    expect(await index.listResults(), isEmpty);

    await repository.rebuildIndex();
    final indexed = await index.listResults();
    expect(indexed, hasLength(1));
    expect(indexed.single.id, created.id);
    expect(indexed.single.localHash, startsWith('sha256:'));
  });

  test('deletes by writing a tombstone instead of removing the file', () async {
    final created = await repository.create(
      type: ResultType.todo,
      title: '买牛奶',
      body: '',
      due: DateTime(2026, 10, 5, 18),
    );

    await repository.delete(created.id);
    final raw = vault.files[created.markdownPath]!;
    final indexed = await index.findResult(created.id);

    expect(raw, contains('deleted: true'));
    expect(indexed!.deleted, isTrue);
    expect(await repository.listDocuments(), isEmpty);
  });
}
