import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/modules/home_widgets/home_widgets.dart';

void main() {
  test('parses the shared snapshot fixture', () {
    final source = File('test/fixtures/widget_snapshot_v1.json')
        .readAsStringSync();

    final envelope = decodeWidgetSnapshotEnvelope(source);

    expect(envelope.schemaVersion, 1);
    expect(envelope.cards, hasLength(1));
    expect(envelope.cards.single.cardId, 'card_fixture');
    expect(envelope.cards.single.rows, hasLength(4));
    expect(
      WidgetSnapshotEnvelope.parseJson(envelope.toJsonString())
          .cards
          .single
          .dataDay,
      '2026-11-10',
    );
  });

  test('round-trips contract constructors and command parsers', () {
    final spec = CardSpec(
      title: '学习总览',
      sourceMode: WidgetSourceMode.allTables,
      sections: [
        SectionSpec(
          tableId: 'tb_work',
          label: '作业',
          types: const [TableContentType.todo],
          daysAhead: 7,
          sort: const WidgetSort(
            key: WidgetSortKey.businessTime,
            direction: WidgetSortDirection.asc,
          ),
          limit: 6,
          fields: [
            const WidgetField.builtin(WidgetBuiltinField.time),
            WidgetField.custom('fld_course'),
          ],
        ),
      ],
      excludedTableIds: const ['tb_archive'],
      hideEmptySections: true,
      theme: WidgetTheme.dark,
    );
    final command = CardCommand.replace(
      cardId: 'card_1',
      expectedRevision: 3,
      spec: spec,
    );

    final parsedSpec = parseCardSpec(spec.toJson());
    final parsedCommand = parseCardCommand(command.toJson());

    expect(parsedSpec.sourceMode, WidgetSourceMode.allTables);
    expect(parsedSpec.sections.single.daysAhead, 7);
    expect(parsedSpec.sections.single.fields.first.wireName, 'builtin:time');
    expect(parsedSpec.sections.single.toJson()['fields'], [
      'builtin:time',
      'custom:fld_course',
    ]);
    expect(parsedCommand.kind, CardCommandKind.replace);
    expect(parsedCommand.expectedRevision, 3);
    expect(parsedCommand.normalizedSignature, command.normalizedSignature);
  });

  test('parses all command constructors', () {
    final commands = [
      CardCommand.create(CardSpec(title: '首页')),
      CardCommand.replace(
        cardId: 'card_1',
        expectedRevision: 1,
        spec: CardSpec(title: '新标题'),
      ),
      CardCommand.archive(cardId: 'card_1', expectedRevision: 2),
      CardCommand.restore(cardId: 'card_1', expectedRevision: 3),
      CardCommand.setVisibility(
        cardId: 'card_1',
        expectedRevision: 4,
        visibility: WidgetVisibility.hidden,
      ),
      CardCommand.undo(
        cardId: 'card_1',
        expectedRevision: 5,
        targetOperationId: 'op_1',
      ),
    ];

    expect(
      commands.map((item) => CardCommand.parse(item.toJson()).kind),
      CardCommandKind.values,
    );
  });

  test('rejects stale or malformed contract shapes', () {
    expect(
      () => CardDefinition.parse({
        'schema_version': 2,
        'card_id': 'card_1',
        'revision': 1,
        'archived': false,
        'spec': CardSpec(title: '首页').toJson(),
      }),
      throwsFormatException,
    );
    expect(
      () => SectionSpec(
        tableId: 'tb_work',
        fields: [
          WidgetField.custom('1'),
          WidgetField.custom('2'),
          WidgetField.custom('3'),
          WidgetField.custom('4'),
        ],
      ),
      throwsFormatException,
    );
    expect(() => WidgetField.parse('builtin:unknown'), throwsFormatException);
  });

  test('publish result carries optional bridge counts', () {
    const defaults = WidgetPublishResult.published();
    const bridge = WidgetPublishResult(
      status: WidgetPublishStatus.published,
      submittedCount: 3,
      failedCount: 1,
    );

    expect(defaults.submittedCount, 0);
    expect(defaults.failedCount, 0);
    expect(bridge.toJson()['submitted_count'], 3);
    expect(bridge.toJson()['failed_count'], 1);
  });
}
