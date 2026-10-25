import 'dart:io';
import 'dart:isolate';

import 'package:codelab_agent_acp/src/event_projection.dart';
import 'package:test/test.dart';

/// ACP-6: у каждого подтипа `AgentEvent` есть строка таблицы §13.7 —
/// кадр или пометка «не передаётся» (задача 4.1, DoD итерации 2).
///
/// `switch` в `projectEvent` исчерпывающий без `default`, поэтому новый
/// подтип без ветки не компилируется; тест ловит обратное — подтип, который
/// попал в `switch`, но не в таблицу, и строку таблицы без подтипа. Подтипы
/// читаются из исходника иерархии: в тестах пакета нет `dart:mirrors`.
void main() {
  test('projectionTable lists exactly the subtypes of AgentEvent', () {
    final source = File.fromUri(
      Isolate.resolvePackageUriSync(
        Uri.parse('package:codelab_agent_core/src/loop/agent_events.dart'),
      )!,
    ).readAsStringSync();
    final subtypes = {
      for (final match in RegExp(
        r'class (\w+) extends AgentEvent\b',
      ).allMatches(source))
        match[1]!,
    };

    expect(subtypes, isNotEmpty);
    expect({for (final type in projectionTable.keys) '$type'}, subtypes);
  });

  test('every row says what goes to the client', () {
    for (final MapEntry(key: type, value: row) in projectionTable.entries) {
      expect(row, isNotEmpty, reason: '$type');
    }
  });
}
