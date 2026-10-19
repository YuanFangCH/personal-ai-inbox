import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

class ExtractedFileText {
  const ExtractedFileText({
    required this.fileName,
    required this.text,
    required this.truncated,
  });

  final String fileName;
  final String text;
  final bool truncated;
}

class FileInputException implements Exception {
  const FileInputException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PickedFileBytes {
  const PickedFileBytes({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

typedef PickFileBytes = Future<PickedFileBytes?> Function();

/// Selects and extracts local files into bounded plain text; source bytes are
/// discarded after parsing and never copied into conversation attachments.
class FileInputService {
  const FileInputService({this.pdfTextExtractor, this.pickFileBytes});

  static const allowedExtensions = ['txt', 'md', 'csv', 'pdf', 'docx', 'xlsx'];
  static const maxFileBytes = 8 * 1024 * 1024;
  static const maxFileTextChars = 12000;
  static const maxZipEntries = 256;
  static const maxZipExpandedBytes = 24 * 1024 * 1024;
  static const maxPdfPages = 50;
  static const maxSpreadsheetSheets = 12;
  static const maxSpreadsheetRows = 200;
  static const maxSpreadsheetCells = 5000;

  final Future<String> Function(Uint8List bytes, String fileName)?
  pdfTextExtractor;
  final PickFileBytes? pickFileBytes;

  Future<ExtractedFileText?> pickAndExtract({
    int maxTextChars = maxFileTextChars,
  }) async {
    final picker = pickFileBytes;
    late final PickedFileBytes selected;
    if (picker == null) {
      final file = await FilePicker.pickFile(
        dialogTitle: '选择要分析的文件',
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );
      if (file == null) return null;
      final size = await file.length();
      if (size != null && size > maxFileBytes) {
        throw const FileInputException('文件超过 8 MiB 大小限制。');
      }
      selected = PickedFileBytes(
        fileName: file.name,
        bytes: await file.readAsBytes(),
      );
    } else {
      final value = await picker();
      if (value == null) return null;
      selected = value;
    }
    if (selected.bytes.length > maxFileBytes) {
      throw const FileInputException('文件超过 8 MiB 大小限制。');
    }
    return extractBytes(
      fileName: selected.fileName,
      bytes: selected.bytes,
      maxTextChars: maxTextChars,
    );
  }

  Future<ExtractedFileText> extractBytes({
    required String fileName,
    required Uint8List bytes,
    int maxTextChars = maxFileTextChars,
  }) async {
    if (bytes.length > maxFileBytes) {
      throw const FileInputException('文件超过 8 MiB 大小限制。');
    }
    if (maxTextChars < 1) {
      throw const FileInputException('本条消息的文件文字预算已用完。');
    }
    final extension = _extension(fileName);
    if (!allowedExtensions.contains(extension)) {
      throw FileInputException('暂不支持 .$extension 文件。');
    }
    late final String extracted;
    try {
      extracted = switch (extension) {
        'txt' || 'md' || 'csv' => _decodeUtf8(bytes),
        'docx' => _extractDocx(bytes),
        'xlsx' => _extractXlsx(bytes),
        'pdf' => await _extractPdf(bytes, fileName),
        _ => throw FileInputException('暂不支持 .$extension 文件。'),
      };
    } on FileInputException {
      rethrow;
    } on Object catch (_) {
      throw FileInputException('无法读取 .$extension 文件；请检查文件是否损坏或受密码保护。');
    }
    final text = extracted.trim();
    if (text.isEmpty) {
      throw const FileInputException('文件中没有可提取的文字。');
    }
    final runes = text.runes;
    final truncated = runes.length > maxTextChars;
    final bounded = truncated
        ? String.fromCharCodes(runes.take(maxTextChars))
        : text;
    return ExtractedFileText(
      fileName: fileName,
      text: bounded,
      truncated: truncated,
    );
  }

  String _decodeUtf8(Uint8List bytes) {
    try {
      final text = utf8.decode(bytes, allowMalformed: false);
      return text.startsWith('\uFEFF') ? text.substring(1) : text;
    } on FormatException {
      throw const FileInputException('文件不是有效的 UTF-8 文本。');
    }
  }

  String _extractDocx(Uint8List bytes) {
    final archive = _decodeOfficeArchive(bytes);
    final documentFile = _archiveFile(archive, 'word/document.xml');
    if (documentFile == null) {
      throw const FileInputException('DOCX 文件缺少正文内容，或文件已损坏。');
    }
    final xml = XmlDocument.parse(utf8.decode(documentFile.readBytes()!));
    final output = StringBuffer();
    for (final paragraph in _elements(xml, 'p')) {
      final paragraphText = StringBuffer();
      void collect(XmlNode node) {
        if (node is XmlElement) {
          switch (node.name.local) {
            case 't':
              paragraphText.write(node.innerText);
              return;
            case 'tab':
              paragraphText.write('\t');
              return;
            case 'br' || 'cr':
              paragraphText.write('\n');
              return;
          }
        }
        for (final child in node.children) {
          collect(child);
        }
      }

      collect(paragraph);
      if (paragraphText.isNotEmpty) output.writeln(paragraphText);
    }
    return output.toString();
  }

  String _extractXlsx(Uint8List bytes) {
    final archive = _decodeOfficeArchive(bytes);
    final sharedStringsFile = _archiveFile(archive, 'xl/sharedStrings.xml');
    final sharedStrings = sharedStringsFile == null
        ? const <String>[]
        : _sharedStrings(
            XmlDocument.parse(utf8.decode(sharedStringsFile.readBytes()!)),
          );
    final workbookFile = _archiveFile(archive, 'xl/workbook.xml');
    final relationshipFile = _archiveFile(
      archive,
      'xl/_rels/workbook.xml.rels',
    );
    final namesByPath = <String, String>{};
    if (workbookFile != null && relationshipFile != null) {
      final workbook = XmlDocument.parse(
        utf8.decode(workbookFile.readBytes()!),
      );
      final relationships = XmlDocument.parse(
        utf8.decode(relationshipFile.readBytes()!),
      );
      final targets = <String, String>{
        for (final relation in _elements(relationships, 'Relationship'))
          if (_attribute(relation, 'Id') != null &&
              _attribute(relation, 'Target') != null)
            _attribute(relation, 'Id')!: _normalizeOfficePath(
              _attribute(relation, 'Target')!,
            ),
      };
      for (final sheet in _elements(workbook, 'sheet')) {
        final id = _attribute(sheet, 'id');
        final name = _attribute(sheet, 'name');
        if (id != null && name != null && targets[id] != null) {
          namesByPath[targets[id]!] = name;
        }
      }
    }

    final sheets =
        archive.files
            .where(
              (file) =>
                  file.isFile &&
                  RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(file.name),
            )
            .toList(growable: false)
          ..sort((left, right) => left.name.compareTo(right.name));
    if (sheets.isEmpty) {
      throw const FileInputException('XLSX 文件中没有可读取的工作表。');
    }
    if (sheets.length > maxSpreadsheetSheets) {
      throw const FileInputException('XLSX 工作表超过 12 个的解析上限。');
    }

    final output = StringBuffer();
    var cellCount = 0;
    for (final sheet in sheets) {
      final sheetName = namesByPath[sheet.name] ?? sheet.name.split('/').last;
      output.writeln('[工作表：$sheetName]');
      final xml = XmlDocument.parse(utf8.decode(sheet.readBytes()!));
      var rowCount = 0;
      for (final row in _elements(xml, 'row')) {
        if (rowCount++ >= maxSpreadsheetRows) {
          output.writeln('[工作表其余行已省略]');
          break;
        }
        final cells = <String>[];
        for (final cell in _elements(row, 'c')) {
          if (++cellCount > maxSpreadsheetCells) {
            output.writeln('[工作簿其余单元格已省略]');
            return output.toString();
          }
          final reference = _attribute(cell, 'r') ?? '';
          final type = _attribute(cell, 't');
          final value = _elements(cell, 'v').firstOrNull?.innerText ?? '';
          final formula = _elements(cell, 'f').firstOrNull?.innerText;
          String cellText;
          if (type == 's') {
            final index = int.tryParse(value);
            cellText =
                index != null && index >= 0 && index < sharedStrings.length
                ? sharedStrings[index]
                : '';
          } else if (type == 'inlineStr') {
            cellText = _elements(
              cell,
              't',
            ).map((node) => node.innerText).join();
          } else if (formula != null) {
            cellText = value.isEmpty ? '[公式未执行] $formula' : '$value（公式未执行）';
          } else {
            cellText = value;
          }
          if (cellText.isNotEmpty) {
            cells.add(reference.isEmpty ? cellText : '$reference=$cellText');
          }
        }
        if (cells.isNotEmpty) output.writeln(cells.join(' | '));
      }
    }
    return output.toString();
  }

  Future<String> _extractPdf(Uint8List bytes, String fileName) async {
    final extractor = pdfTextExtractor;
    if (extractor != null) {
      final text = await extractor(bytes, fileName);
      if (text.trim().isEmpty) {
        throw const FileInputException('PDF 未包含可提取的文字层；扫描件 OCR 暂不支持。');
      }
      return text;
    }
    await pdfrxFlutterInitialize();
    PdfDocument? document;
    try {
      document = await PdfDocument.openData(
        bytes,
        sourceName: fileName,
        useProgressiveLoading: false,
      );
      if (document.isEncrypted) {
        throw const FileInputException('PDF 已加密，暂不支持提取。');
      }
      if (document.pages.length > maxPdfPages) {
        throw const FileInputException('PDF 页数超过 50 页的解析上限。');
      }
      final output = StringBuffer();
      for (var index = 0; index < document.pages.length; index++) {
        final page = await document.pages[index].loadText();
        if (page == null || page.fullText.trim().isEmpty) continue;
        output
          ..writeln('[第 ${index + 1} 页]')
          ..writeln(page.fullText);
      }
      final text = output.toString();
      if (text.trim().isEmpty) {
        throw const FileInputException('PDF 未包含可提取的文字层；扫描件 OCR 暂不支持。');
      }
      return text;
    } on FileInputException {
      rethrow;
    } on PdfPasswordException {
      throw const FileInputException('PDF 已加密或需要密码，无法提取。');
    } finally {
      await document?.dispose();
    }
  }

  Archive _decodeOfficeArchive(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    if (archive.files.length > maxZipEntries) {
      throw const FileInputException('Office 文档包含过多压缩条目。');
    }
    final expandedBytes = archive.files.fold<int>(
      0,
      (total, file) => total + (file.isFile ? file.size : 0),
    );
    if (expandedBytes > maxZipExpandedBytes ||
        archive.files.any((file) => file.isFile && file.size > maxFileBytes)) {
      throw const FileInputException('Office 文档解压后的内容超过安全上限。');
    }
    return archive;
  }

  ArchiveFile? _archiveFile(Archive archive, String path) {
    for (final file in archive.files) {
      if (file.name == path) return file;
    }
    return null;
  }

  List<String> _sharedStrings(XmlDocument document) => [
    for (final item in _elements(document, 'si'))
      _elements(item, 't').map((node) => node.innerText).join(),
  ];

  Iterable<XmlElement> _elements(XmlNode node, String localName) sync* {
    for (final child in node.children) {
      if (child is XmlElement) {
        if (child.name.local == localName) yield child;
        yield* _elements(child, localName);
      }
    }
  }

  String? _attribute(XmlElement element, String localName) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  String _normalizeOfficePath(String target) {
    final components = <String>[];
    for (final part in target.replaceAll('\\', '/').split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (components.isNotEmpty) components.removeLast();
      } else {
        components.add(part);
      }
    }
    if (components.firstOrNull != 'xl') components.insert(0, 'xl');
    return components.join('/');
  }

  String _extension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  }
}
