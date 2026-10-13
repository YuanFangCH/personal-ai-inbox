import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/data/io_vault_store.dart';

void main() {
  test(
    'separate vault adapters serialize writes through the OS lock',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'inbox-vault-lock',
      );
      addTearDown(() => directory.delete(recursive: true));
      final first = IoVaultStore.at(directory);
      final second = IoVaultStore.at(directory);
      final firstInside = Completer<void>();
      final releaseFirst = Completer<void>();
      var secondInside = false;

      final firstWrite = first.exclusive(() async {
        firstInside.complete();
        await releaseFirst.future;
        await first.write('vault/knowledge/item.md', 'first');
      });
      await firstInside.future;
      final secondWrite = second.exclusive(() async {
        secondInside = true;
        await second.write('vault/knowledge/item.md', 'second');
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(secondInside, isFalse);

      releaseFirst.complete();
      await Future.wait([firstWrite, secondWrite]);
      expect(await first.read('vault/knowledge/item.md'), 'second');
    },
  );
}
