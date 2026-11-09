import 'dart:async';
import 'dart:convert';

import 'home_widget_contract.dart';
import 'widget_store_platform.dart';

class WidgetStore {
  factory WidgetStore(String directory) =>
      WidgetStore._(createWidgetStoreBackend(directory), directory);

  WidgetStore._(this._backend, this.directory);

  final WidgetStoreBackend _backend;
  final String directory;
  Future<void> _tail = Future<void>.value();

  Future<WidgetStoreState> readState() => _serialized(_readUnlocked);

  Future<void> writeState(WidgetStoreState state) =>
      _serialized(() => _backend.write(jsonEncode(state.toJson())));

  Future<WidgetStoreState> _readUnlocked() async {
    final contents = await _backend.read();
    if (contents == null || contents.trim().isEmpty) {
      return WidgetStoreState.empty();
    }
    return WidgetStoreState.parse(jsonDecode(contents));
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

class WidgetStoreState {
  WidgetStoreState({
    Map<String, CardDefinition>? cards,
    Map<String, WidgetVisibility>? visibility,
    Map<String, WidgetStoreOperation>? operations,
    Map<String, String>? lastMutationByCard,
    Map<String, WidgetStoreUndo>? undoByCard,
  }) : cards = Map.unmodifiable(Map.of(cards ?? const {})),
       visibility = Map.unmodifiable(Map.of(visibility ?? const {})),
       operations = Map.unmodifiable(Map.of(operations ?? const {})),
       lastMutationByCard = Map.unmodifiable(
         Map.of(lastMutationByCard ?? const {}),
       ),
       undoByCard = Map.unmodifiable(Map.of(undoByCard ?? const {}));

  factory WidgetStoreState.empty() => WidgetStoreState();

  final Map<String, CardDefinition> cards;
  final Map<String, WidgetVisibility> visibility;
  final Map<String, WidgetStoreOperation> operations;
  final Map<String, String> lastMutationByCard;
  final Map<String, WidgetStoreUndo> undoByCard;

  static WidgetStoreState parse(Object? value) {
    if (value is! Map) throw const FormatException('Invalid widget store');
    final json = value.map((key, item) => MapEntry(key.toString(), item));
    if (json['schema_version'] != widgetSchemaVersion) {
      throw FormatException(
        'Unsupported widget store schema: ${json['schema_version']}',
      );
    }
    final cards = <String, CardDefinition>{};
    final visibility = <String, WidgetVisibility>{};
    final operations = <String, WidgetStoreOperation>{};
    final lastMutations = <String, String>{};
    final undoByCard = <String, WidgetStoreUndo>{};

    if (json['cards'] is Map) {
      for (final entry in (json['cards'] as Map).entries) {
        final card = CardDefinition.parse(entry.value);
        cards[entry.key.toString()] = card;
      }
    }
    if (json['visibility'] is Map) {
      for (final entry in (json['visibility'] as Map).entries) {
        visibility[entry.key.toString()] = WidgetVisibility.parse(entry.value);
      }
    }
    if (json['operations'] is Map) {
      for (final entry in (json['operations'] as Map).entries) {
        operations[entry.key.toString()] = WidgetStoreOperation.parse(
          entry.value,
        );
      }
    }
    if (json['last_mutations'] is Map) {
      for (final entry in (json['last_mutations'] as Map).entries) {
        lastMutations[entry.key.toString()] = entry.value.toString();
      }
    }
    if (json['undo'] is Map) {
      for (final entry in (json['undo'] as Map).entries) {
        undoByCard[entry.key.toString()] = WidgetStoreUndo.parse(entry.value);
      }
    }
    for (final entry in visibility.entries) {
      final card = cards[entry.key];
      if (card != null) {
        cards[entry.key] = card.copyWith(visibility: entry.value);
      }
    }
    return WidgetStoreState(
      cards: cards,
      visibility: visibility,
      operations: operations,
      lastMutationByCard: lastMutations,
      undoByCard: undoByCard,
    );
  }

  Map<String, Object?> toJson() => {
    'schema_version': widgetSchemaVersion,
    'cards': {
      for (final entry in cards.entries) entry.key: entry.value.toJson(),
    },
    'visibility': {
      for (final entry in visibility.entries) entry.key: entry.value.wireName,
    },
    'operations': {
      for (final entry in operations.entries) entry.key: entry.value.toJson(),
    },
    'last_mutations': lastMutationByCard,
    'undo': {
      for (final entry in undoByCard.entries) entry.key: entry.value.toJson(),
    },
  };
}

class WidgetStoreOperation {
  const WidgetStoreOperation({
    required this.signature,
    required this.command,
    required this.receipt,
    required this.appliedAtMs,
  });

  final String signature;
  final CardCommand command;
  final CardWriteReceipt receipt;
  final int appliedAtMs;

  static WidgetStoreOperation parse(Object? value) {
    if (value is! Map) throw const FormatException('Invalid widget operation');
    return WidgetStoreOperation(
      signature: value['signature'].toString(),
      command: CardCommand.parse(value['command']),
      receipt: CardWriteReceipt.parse(value['receipt']),
      appliedAtMs: _storeInt(value['applied_at_ms'], 'applied_at_ms'),
    );
  }

  WidgetStoreOperation copyWith({CardWriteReceipt? receipt}) =>
      WidgetStoreOperation(
        signature: signature,
        command: command,
        receipt: receipt ?? this.receipt,
        appliedAtMs: appliedAtMs,
      );

  Map<String, Object?> toJson() => {
    'signature': signature,
    'command': command.toJson(),
    'receipt': receipt.toJson(),
    'applied_at_ms': appliedAtMs,
  };
}

class WidgetStoreUndo {
  const WidgetStoreUndo({
    required this.targetOperationId,
    required this.appliedAtMs,
    required this.beforeCard,
  });

  final String targetOperationId;
  final int appliedAtMs;
  final CardDefinition? beforeCard;

  static WidgetStoreUndo parse(Object? value) {
    if (value is! Map) throw const FormatException('Invalid widget undo');
    return WidgetStoreUndo(
      targetOperationId: value['target_operation_id'].toString(),
      appliedAtMs: _storeInt(value['applied_at_ms'], 'applied_at_ms'),
      beforeCard: value['before_card'] == null
          ? null
          : CardDefinition.parse(value['before_card']),
    );
  }

  Map<String, Object?> toJson() => {
    'target_operation_id': targetOperationId,
    'applied_at_ms': appliedAtMs,
    'before_card': beforeCard?.toJson(),
  };
}

int _storeInt(Object? value, String field) {
  if (value is int) return value;
  throw FormatException('$field must be an integer');
}
