import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/services/file_input_service.dart';

void main() {
  test(
    'uses the injected file picker and extracts the selected file',
    () async {
      final service = FileInputService(
        pickFileBytes: () async => PickedFileBytes(
          fileName: 'picked.txt',
          bytes: Uint8List.fromList(utf8.encode('selected locally')),
        ),
      );
      final file = await service.pickAndExtract();
      expect(file?.fileName, 'picked.txt');
      expect(file?.text, 'selected locally');
    },
  );

  test('file selection cancellation creates no file input', () async {
    final service = FileInputService(pickFileBytes: () async => null);
    expect(await service.pickAndExtract(), isNull);
  });

  test('extracts UTF-8 text and clips by Unicode characters', () async {
    const service = FileInputService();
    final file = await service.extractBytes(
      fileName: '课程.md',
      bytes: Uint8List.fromList(utf8.encode('\uFEFF第一周安排：周一开始')),
      maxTextChars: 5,
    );
    expect(file.fileName, '课程.md');
    expect(file.text, '第一周安排');
    expect(file.truncated, isTrue);
  });

  test(
    'extracts CSV cells as inert UTF-8 text and rejects non-text bytes',
    () async {
      const service = FileInputService();
      final file = await service.extractBytes(
        fileName: '作业.csv',
        bytes: Uint8List.fromList(utf8.encode('周次,截止时间\n1,周五')),
      );
      expect(file.text, contains('周次,截止时间'));
      await expectLater(
        service.extractBytes(
          fileName: 'bad.txt',
          bytes: Uint8List.fromList([0xff, 0xfe, 0xfd]),
        ),
        throwsA(isA<FileInputException>()),
      );
    },
  );

  test('extracts DOCX body text without evaluating embedded content', () async {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string('word/document.xml', '''
          <w:document xmlns:w="urn:test"><w:body>
            <w:p><w:r><w:t>学期周数</w:t></w:r></w:p>
            <w:p><w:r><w:t>十六周</w:t></w:r><w:r><w:tab/></w:r><w:r><w:t>指令文本仅为资料</w:t></w:r></w:p>
          </w:body></w:document>
          '''),
      );
    final service = const FileInputService();
    final file = await service.extractBytes(
      fileName: '课程.docx',
      bytes: ZipEncoder().encodeBytes(archive),
    );
    expect(file.text, contains('学期周数'));
    expect(file.text, contains('十六周\t指令文本仅为资料'));
  });

  test(
    'extracts workbook values and labels formula results as unexecuted',
    () async {
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            'xl/sharedStrings.xml',
            '<sst xmlns="urn:test"><si><t>课程</t></si></sst>',
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'xl/workbook.xml',
            '<workbook xmlns:r="urn:rel"><sheets><sheet name="安排" r:id="rId1"/></sheets></workbook>',
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'xl/_rels/workbook.xml.rels',
            '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>',
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'xl/worksheets/sheet1.xml',
            '<worksheet><sheetData><row><c r="A1" t="s"><v>0</v></c></row><row><c r="B2"><f>1+2</f><v>3</v></c></row></sheetData></worksheet>',
          ),
        );
      final file = await const FileInputService().extractBytes(
        fileName: '校历.xlsx',
        bytes: ZipEncoder().encodeBytes(archive),
      );
      expect(file.text, contains('[工作表：安排]'));
      expect(file.text, contains('A1=课程'));
      expect(file.text, contains('B2=3（公式未执行）'));
    },
  );

  test('PDF extraction reports text and identifies scanned pages', () async {
    final service = FileInputService(
      pdfTextExtractor: (bytes, fileName) async => '第一面\n$fileName',
    );
    final pdf = await service.extractBytes(
      fileName: '课程.pdf',
      bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
    );
    expect(pdf.text, contains('课程.pdf'));
    await expectLater(
      FileInputService(pdfTextExtractor: (bytes, fileName) async => '')
          .extractBytes(
            fileName: 'scan.pdf',
            bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
          ),
      throwsA(
        isA<FileInputException>().having(
          (error) => error.message,
          'message',
          contains('OCR 暂不支持'),
        ),
      ),
    );
  });

  test('rejects unsupported, oversized and empty-budget files', () async {
    const service = FileInputService();
    await expectLater(
      service.extractBytes(
        fileName: 'macro.docm',
        bytes: Uint8List.fromList([1]),
      ),
      throwsA(isA<FileInputException>()),
    );
    await expectLater(
      service.extractBytes(
        fileName: 'big.txt',
        bytes: Uint8List(FileInputService.maxFileBytes + 1),
      ),
      throwsA(isA<FileInputException>()),
    );
    await expectLater(
      service.extractBytes(
        fileName: 'empty.txt',
        bytes: Uint8List.fromList([65]),
        maxTextChars: 0,
      ),
      throwsA(isA<FileInputException>()),
    );
  });
}
