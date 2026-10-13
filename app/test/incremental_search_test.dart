import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/markdown_codec.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';

void main() {
  test(
    'a 10k result search reads only the requested page of Markdown',
    () async {
      final vault = _CountingVaultStore();
      final index = MemoryIndexDatabase();
      final repository = ResultRepository(
        vault: vault,
        index: index,
        deviceId: 'test-device',
      );
      await repository.initialize();
      const codec = MarkdownCodec();
      final baseTime = DateTime.utc(2026, 1, 1);

      for (var number = 0; number < 10000; number++) {
        final id = 'kn_perf_${number.toString().padLeft(5, '0')}';
        final timestamp = baseTime.add(Duration(minutes: number));
        final document = ResultDocument(
          id: id,
          type: ResultType.knowledge,
          title: 'Knowledge $number',
          status: ResultStatus.canonical,
          originDevice: 'test-device',
          revision: 1,
          createdAt: timestamp,
          updatedAt: timestamp,
          body: 'needle body $number',
          tags: ['needle'],
        );
        final markdown = codec.encode(document);
        await vault.write(document.markdownPath, markdown);
        await index.upsertResult(
          IndexedResult(
            id: id,
            type: document.type,
            title: document.title,
            status: document.status,
            revision: document.revision,
            updatedAt: timestamp,
            deleted: false,
            mdPath: document.markdownPath,
            localHash: repository.hashMarkdown(markdown),
            lastSyncedHash: null,
            syncState: SyncState.pendingUpload,
            searchText: '${document.title}\n${document.body}\nneedle'
                .toLowerCase(),
          ),
        );
      }

      vault.readCount = 0;
      final page = await repository.searchDocuments(
        query: 'needle',
        type: ResultType.knowledge,
        offset: 0,
        limit: 50,
      );

      expect(page, hasLength(50));
      expect(vault.readCount, 50);
    },
  );
}

class _CountingVaultStore extends MemoryVaultStore {
  int readCount = 0;

  @override
  Future<String?> read(String relativePath) {
    readCount++;
    return super.read(relativePath);
  }
}
