import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/modules/home_widgets/home_widget_contract.dart';
import 'package:personal_ai_inbox/modules/home_widgets/widget_store.dart';

void main() {
  test('persists cards and visibility atomically across reopen', () async {
    final directory = await Directory.systemTemp.createTemp('widget-store');
    addTearDown(() => directory.delete(recursive: true));
    final store = WidgetStore(directory.path);
    final card = CardDefinition(
      cardId: 'card_1',
      revision: 2,
      archived: false,
      visibility: WidgetVisibility.fields,
      spec: CardSpec(title: '学习'),
    );
    final state = WidgetStoreState(
      cards: {card.cardId: card},
      visibility: {card.cardId: card.visibility},
    );

    await store.writeState(state);
    final reopened = await WidgetStore(directory.path).readState();

    expect(reopened.cards['card_1']!.spec.title, '学习');
    expect(reopened.cards['card_1']!.visibility, WidgetVisibility.fields);
    expect(File('${directory.path}/state.json').existsSync(), isTrue);
  });

  test(
    'recovers the previous complete state when a later write is torn',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'widget-store-recovery',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = WidgetStore(directory.path);
      await store.writeState(
        WidgetStoreState(
          cards: {
            'card_1': CardDefinition(
              cardId: 'card_1',
              revision: 1,
              archived: false,
              spec: CardSpec(title: '原状态'),
            ),
          },
        ),
      );
      final stateFile = File('${directory.path}/state.json');
      await stateFile.rename('${directory.path}/state.json.bak');
      await File('${directory.path}/state.json.tmp')
          .writeAsString('{incomplete');

      final reopened = await WidgetStore(directory.path).readState();

      expect(reopened.cards['card_1']!.spec.title, '原状态');
      expect(File('${directory.path}/state.json').existsSync(), isTrue);
    },
  );
}
