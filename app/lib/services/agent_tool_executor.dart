import 'dart:async';

import 'agent_tool_registry.dart';

class AgentToolExecutionBatch<T> {
  const AgentToolExecutionBatch({
    required this.calls,
    required this.readOnly,
  });

  final List<T> calls;
  final bool readOnly;
}

/// Plans and executes tool batches.
///
/// Parallel-safe reads may run together; every write is an exclusive barrier.
/// Results are always returned in model-call order.
class AgentToolExecutor {
  const AgentToolExecutor({
    this.registry = const AgentToolRegistry(),
    this.maxParallelToolCalls = 10,
  }) : assert(maxParallelToolCalls > 0);

  final AgentToolRegistry registry;
  final int maxParallelToolCalls;

  List<AgentToolExecutionBatch<T>> plan<T>(
    List<T> calls, {
    required String Function(T call) wireName,
  }) {
    final batches = <AgentToolExecutionBatch<T>>[];
    var reads = <T>[];

    void flushReads() {
      if (reads.isEmpty) return;
      batches.add(
        AgentToolExecutionBatch<T>(
          calls: List.unmodifiable(reads),
          readOnly: true,
        ),
      );
      reads = <T>[];
    }

    for (final call in calls) {
      final spec = registry.byWireName(wireName(call));
      if (spec?.access == AgentToolAccess.read && spec!.parallelSafe) {
        reads.add(call);
      } else {
        flushReads();
        batches.add(
          AgentToolExecutionBatch<T>(
            calls: List.unmodifiable([call]),
            readOnly: false,
          ),
        );
      }
    }
    flushReads();
    return List.unmodifiable(batches);
  }

  Future<List<R>> executeReads<T, R>(
    List<T> calls, {
    required Future<R> Function(T call) execute,
  }) async {
    final results = List<R?>.filled(calls.length, null);
    var cursor = 0;
    while (cursor < calls.length) {
      final end = (cursor + maxParallelToolCalls).clamp(0, calls.length);
      final window = calls.sublist(cursor, end);
      final values = await Future.wait([
        for (var index = 0; index < window.length; index++)
          execute(window[index]).then((value) => (cursor + index, value)),
      ]);
      for (final (index, value) in values) {
        results[index] = value;
      }
      cursor = end;
    }
    return List<R>.unmodifiable(results.cast<R>());
  }
}
