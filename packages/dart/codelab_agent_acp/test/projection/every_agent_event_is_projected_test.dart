import 'dart:io';

import 'package:codelab_agent_acp/src/event_projection.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../../../codelab_agent_core/test/support/package_dir.dart';

/// ACP-6: у каждого подтипа `AgentEvent` есть строка таблицы §13.7 —
/// кадр или пометка «не передаётся» (задача 4.1, DoD итерации 2).
///
/// `switch` в `projectEvent` исчерпывающий без `default`, поэтому новый
/// подтип без ветки не компилируется; тест ловит обратное — подтип, который
/// попал в `switch`, но не в таблицу, и строку таблицы без подтипа. Подтипы
/// читаются из исходника иерархии: в тестах пакета нет `dart:mirrors`.
void main() {
  test('projectionTable lists exactly the subtypes of AgentEvent', () {
    // corePath, а не Isolate.resolvePackageUri: под flutter test его нет.
    final source = File(
      corePath('lib/src/loop/agent_events.dart'),
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

  // change `add-usage-extension`, задача 1.4 (D18 Т5): usage уходит не в
  // `session/update`, а уведомлением `_codelab/session/usage`; поэтому строки
  // `StepEnded`, `TurnEnded` и `ContextCompacted` называют его, а не
  // «not sent» (ACP-6: таблица — единственное место, где видно, во что
  // проецируется событие). Остальные строки не меняются.
  for (final type in [StepEnded, TurnEnded, ContextCompacted]) {
    test('the $type row names _codelab/session/usage', () {
      expect(projectionTable[type], contains('_codelab/session/usage'));
    });
  }
}
