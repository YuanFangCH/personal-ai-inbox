import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/services/agent_tool_executor.dart';
import 'package:personal_ai_inbox/services/agent_tool_registry.dart';

void main() {
  const executor = AgentToolExecutor(maxParallelToolCalls: 2);

  test('plan groups parallel reads and isolates every write', () {
    final batches = executor.plan(const [
      'table_list',
      'content_read',
      'content_update',
      'table_search',
    ], wireName: (name) => name);

    expect(batches, hasLength(3));
    expect(batches[0].readOnly, isTrue);
    expect(batches[0].calls, ['table_list', 'content_read']);
    expect(batches[1].readOnly, isFalse);
    expect(batches[1].calls, ['content_update']);
    expect(batches[2].readOnly, isTrue);
    expect(batches[2].calls, ['table_search']);
  });

  test('parallel reads preserve order and obey the concurrency cap', () async {
    var active = 0;
    var peak = 0;
    final release = Completer<void>();
    final started = <int>[];
    final future = executor.executeReads(
      const [1, 2, 3, 4],
      execute: (value) async {
        active++;
        if (active > peak) peak = active;
        started.add(value);
        if (value <= 2) await release.future;
        active--;
        return value * 10;
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(started, [1, 2]);
    release.complete();

    expect(await future, [10, 20, 30, 40]);
    expect(peak, 2);
  });

  test('registry exposes complete table recovery and inbox tools', () {
    const registry = AgentToolRegistry();

    expect(registry.isRead('recovery.list'), isTrue);
    expect(registry.isRead('recovery.preview'), isTrue);
    expect(registry.isRead('inbox.targets.read'), isTrue);
    expect(registry.isWrite('recovery.restore'), isTrue);
    expect(registry.isParallelSafe('recovery.list'), isTrue);
    expect(registry.isParallelSafe('recovery.restore'), isFalse);
  });

  test('widget reads stay parallel and management is an exclusive write', () {
    const registry = AgentToolRegistry();

    expect(registry.isRead('widget.list'), isTrue);
    expect(registry.isRead('widget.get'), isTrue);
    expect(registry.isParallelSafe('widget.list'), isTrue);
    expect(registry.isParallelSafe('widget.get'), isTrue);
    expect(registry.isWrite('widget.manage'), isTrue);
    expect(registry.isParallelSafe('widget.manage'), isFalse);
  });
}
