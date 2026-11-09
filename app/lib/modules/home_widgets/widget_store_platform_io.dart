import 'dart:io';

import 'widget_store_backend.dart';

WidgetStoreBackend createWidgetStoreBackend(String directory) =>
    _IoWidgetStoreBackend(Directory(directory));

class _IoWidgetStoreBackend implements WidgetStoreBackend {
  _IoWidgetStoreBackend(this.directory)
    : stateFile = File('${directory.path}/state.json'),
      backupFile = File('${directory.path}/state.json.bak'),
      temporaryFile = File('${directory.path}/state.json.tmp');

  final Directory directory;
  final File stateFile;
  final File backupFile;
  final File temporaryFile;

  @override
  Future<String?> read() async {
    await directory.create(recursive: true);
    await _recoverPreviousWrite();
    if (!await stateFile.exists()) return null;
    return stateFile.readAsString();
  }

  @override
  Future<void> write(String contents) async {
    await directory.create(recursive: true);
    await temporaryFile.writeAsString(contents, flush: true);
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    if (await stateFile.exists()) {
      await stateFile.rename(backupFile.path);
    }
    try {
      await temporaryFile.rename(stateFile.path);
    } on Object {
      if (!await stateFile.exists() && await backupFile.exists()) {
        await backupFile.rename(stateFile.path);
      }
      rethrow;
    }
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
  }

  Future<void> _recoverPreviousWrite() async {
    if (await stateFile.exists()) {
      if (await temporaryFile.exists()) await temporaryFile.delete();
      if (await backupFile.exists()) await backupFile.delete();
      return;
    }
    if (await backupFile.exists()) {
      await backupFile.rename(stateFile.path);
      if (await temporaryFile.exists()) await temporaryFile.delete();
      return;
    }
    if (await temporaryFile.exists()) {
      await temporaryFile.rename(stateFile.path);
    }
  }
}
