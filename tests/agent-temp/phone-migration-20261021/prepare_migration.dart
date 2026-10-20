import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'package:personal_ai_inbox/core/markdown_codec.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';

// Reads private backup data supplied as arguments; no personal content is logged.
Future<void> main(List<String> args) async {
  if (args.length < 2) {
    throw ArgumentError(
      'Usage: prepare_migration.dart BACKUP_DIR OUTPUT_DIR [VERIFY_VAULT_DIR]',
    );
  }
  final backup = Directory(args[0]);
  final output = Directory(args[1]);
  final manifest = jsonDecode(
    await File(p.join(backup.path, 'manifest.json')).readAsString(),
  ) as List;
  if (manifest.length != 47) throw StateError('Expected 47 backup records');
  const codec = MarkdownCodec();
  final vault = MemoryVaultStore();
  final expected = <ResultDocument>[];
  final mapping = <Map<String, Object?>>[];
  final hashes = <String, String>{};

  for (final entry in manifest) {
    final item = entry as Map<String, dynamic>;
    final oldId = item['id'] as String;
    final record = jsonDecode(
      await File(p.join(backup.path, '$oldId.json')).readAsString(),
    ) as Map<String, dynamic>;
    final body = await File(p.join(backup.path, '$oldId-body.md'))
        .readAsString();
    if (sha256.convert(utf8.encode(body)).toString() != item['bodySha256'] ||
        body != record['body']) {
      throw StateError('Backup hash/body mismatch: $oldId');
    }
    final detail = (record['detail'] as List).cast<Map<String, dynamic>>();
    final top = (record['editorTop'] as List).cast<Map<String, dynamic>>();
    String property(String label) {
      final index = detail.indexWhere((node) => node['description'] == label);
      if (index < 0 || index + 1 >= detail.length)
        throw StateError('Missing $label: $oldId');
      final next = detail[index + 1];
      return (next['description'] as String).isNotEmpty
          ? next['description'] as String
          : next['text'] as String;
    }

    String? editorProperty(String label) {
      final matches = top.where(
        (node) => (node['description'] as String).startsWith('$label\n'),
      );
      if (matches.isEmpty) return null;
      return (matches.single['description'] as String).substring(
        label.length + 1,
      );
    }

    DateTime? date(String? text) {
      if (text == null || text == '未设置') return null;
      if (!RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(text))
        throw FormatException('Unexpected date: $oldId');
      return DateTime.parse('${text.replaceFirst(' ', 'T')}:00+08:00')
          .toLocal();
    }

    final type = ResultType.parse(record['type'] as String);
    final prefix = {
      ResultType.todo: 'td',
      ResultType.event: 'ev',
      ResultType.matter: 'mt',
    }[type];
    if (prefix == null) throw StateError('Unexpected result type');
    final id = '${prefix}_recovered_20261021_${oldId.split('-').last}';
    final xml = XmlDocument.parse(
      await File(p.join(backup.path, '$oldId-editor-top.xml')).readAsString(),
    );
    final fields = xml
        .findAllElements('node')
        .where(
          (node) => node.getAttribute('class') == 'android.widget.EditText',
        )
        .toList();
    if (fields.first.getAttribute('text') != record['title'] ||
        fields.last.getAttribute('text') != body) {
      throw StateError('Backup source UI mismatch: $oldId');
    }
    final updatedText = detail
        .map((node) => node['description'] as String)
        .firstWhere(
          (text) => RegExp(r' · \d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(text),
        );
    final updated = date(updatedText.split(' · ').last)!;
    final matter = editorProperty('所属事项');
    if (matter != null && matter != '无')
      throw StateError('Relationship needs explicit ID mapping: $oldId');
    if (editorProperty('状态') != '定稿')
      throw StateError('Unexpected status: $oldId');
    final recurrenceText = type == ResultType.event
        ? fields[2].getAttribute('text')!
        : '';
    final allDayNodes = top.where(
      (node) =>
          node['class'] == 'android.widget.Switch' &&
          node['description'] == '全天',
    );
    final document = ResultDocument(
      id: id,
      type: type,
      title: record['title'] as String,
      status: ResultStatus.canonical,
      originDevice: property('来源端'),
      revision: int.parse(property('版本').substring(1)),
      createdAt: updated,
      updatedAt: updated,
      body: body,
      tags: (record['tagsText'] as String)
          .split(RegExp(r'[,，\s]+'))
          .where((value) => value.isNotEmpty)
          .toList(),
      due: type == ResultType.todo ? date(editorProperty('截止时间')) : null,
      done:
          type == ResultType.todo &&
          detail.any((node) => node['description'] == '已完成'),
      start: type == ResultType.event ? date(editorProperty('开始')) : null,
      end: type == ResultType.event ? date(editorProperty('结束')) : null,
      allDay: allDayNodes.isNotEmpty && allDayNodes.single['checked'] == 'true',
      recurrence: recurrenceText.isEmpty ? null : recurrenceText,
      extensionFields: {
        'recovery': {
          'source_version': '1.1.1',
          'backup_record': oldId,
          'original_id_unavailable': true,
          'created_at_estimated_from_visible_updated_at': true,
          'timestamp_precision': 'minute',
        },
      },
    );
    final source = codec.encode(document);
    final decoded = codec.decode(source);
    if (decoded.body != body ||
        decoded.title != document.title ||
        decoded.done != document.done ||
        decoded.due != document.due ||
        decoded.start != document.start ||
        decoded.end != document.end ||
        decoded.recurrence != document.recurrence) {
      throw StateError('Codec round trip mismatch: $oldId');
    }
    final relative = document.markdownPath;
    final file = File(p.join(output.path, 'vault', relative));
    await file.parent.create(recursive: true);
    if (await file.exists() && await file.readAsString() != source)
      throw StateError('Refusing to replace a different prepared file');
    await file.writeAsString(source);
    await vault.write(relative, source);
    hashes[relative] = sha256.convert(utf8.encode(source)).toString();
    mapping.add({
      'backup_record': oldId,
      'new_id': id,
      'relative_path': relative,
    });
    expected.add(document);
  }
  final index = MemoryIndexDatabase();
  await index.open();
  final repository = ResultRepository(
    vault: vault,
    index: index,
    deviceId: 'migration-validation',
  );
  await repository.initialize();
  final restored = await repository.listDocuments();
  if (restored.length != 47 ||
      restored.where((item) => item.type == ResultType.todo).length != 36 ||
      restored.where((item) => item.type == ResultType.event).length != 10 ||
      restored.where((item) => item.type == ResultType.matter).length != 1 ||
      restored.where((item) => item.done).length != 11) {
    final report = await repository.rebuildIndex();
    stdout.writeln(
      'Rebuild diagnostics: ${report.diagnostics.map((item) => '${item.path}: ${item.message}').join('; ')}',
    );
    throw StateError(
      'Repository rebuild totals mismatch: ${restored.length} total, ${restored.where((item) => item.done).length} completed',
    );
  }
  for (final document in expected) {
    final actual = restored.singleWhere((item) => item.id == document.id);
    if (codec.encode(actual) != codec.encode(document))
      throw StateError('Repository round trip mismatch');
  }
  await File(p.join(output.path, 'id-map.json'))
      .writeAsString(const JsonEncoder.withIndent('  ').convert(mapping));
  await File(p.join(output.path, 'vault-sha256.json'))
      .writeAsString(const JsonEncoder.withIndent('  ').convert(hashes));
  if (args.length > 2) {
    final files = await Directory(args[2])
        .list(recursive: true)
        .where((file) => file is File && file.path.endsWith('.md'))
        .cast<File>()
        .toList();
    if (files.length != 47)
      throw StateError('Installed vault file count mismatch');
    for (final entry in hashes.entries) {
      final actual = await File(p.join(args[2], entry.key)).readAsBytes();
      if (sha256.convert(actual).toString() != entry.value)
        throw StateError('Installed vault hash mismatch: ${entry.key}');
    }
    stdout.writeln('Installed vault verified: all 47 file hashes match.');
  }
  stdout.writeln(
    'Prepared and repository-validated: 47 results, 36 todos, 10 events, 1 matter, 11 completed todos.',
  );
}
