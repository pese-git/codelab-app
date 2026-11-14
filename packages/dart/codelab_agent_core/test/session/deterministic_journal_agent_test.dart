import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../subagents/subagent_rig.dart';

/// Побайтово одинаковый журнал со вложенным `agent` (agent-sessions «Запись
/// журнала из событий», сценарий «Побайтово одинаковый журнал»; PKG-6;
/// design.md change `add-subagents-and-tasks`, D36 Т6).
///
/// Продолжение `deterministic_journal_test.dart` для сценария с `read`,
/// `edit`, `task_create` и `agent`; вынесено в отдельный файл, чтобы красный
/// тест не ронял compile-ошибкой уже зелёный сценарий без `agent`. Красный
/// до задач 2.4–2.7: нет `agent`, записей `subagent` и журнала ребёнка.
///
/// Особенность: id ребёнка резервирует `SubagentTool.present` через
/// `IdGenerator` (D28), а лечение (`_heal` → `present`) id не расходует (Т6),
/// иначе последовательность id зависела бы от лечения. Поэтому два прогона
/// на `SequentialIdGenerator` дают один и тот же `sub_…`.
void main() {
  Future<(String, String)> run() async {
    final clock = FakeClock(start: DateTime.utc(2026, 10, 21, 8));
    final env = MemoryExecutionEnv(cwd: '/proj', clock: clock);
    await env.writeText('/proj/a.txt', 'Hello\n');
    final rig = SubagentRig(
      clock: clock,
      baseEnv: env,
      scripts: {
        'Rename the greeting': [
          oneCallStep('c1', 'read', {'path': 'a.txt'}),
          oneCallStep('c2', 'edit', {
            'path': 'a.txt',
            'oldText': 'Hello',
            'newText': 'Hi',
          }),
          oneCallStep('c3', 'task_create', {'subject': 'Check the greeting'}),
          oneCallStep(
            'c4',
            'agent',
            agentArgs('verify a.txt', type: 'explore'),
          ),
          replyStep('Done.'),
        ],
        'verify a.txt': [
          oneCallStep('r1', 'read', {'path': 'a.txt'}),
          replyStep('a.txt says Hi'),
        ],
      },
      config: rigConfig(mode: ModeId.bypass),
    );
    await rig.open();
    await rig.run('Rename the greeting');
    final child = rig.eventsOf<SubagentStarted>().single.childSessionId;
    final texts = (rig.rootJournal, rig.store.textOf(child)!);
    await rig.core.runtime.dispose();
    return texts;
  }

  test(
    'same script with agent yields identical root and child journals',
    () async {
      final (rootA, childA) = await run();
      final (rootB, childB) = await run();

      expect(rootB, rootA);
      expect(childB, childA);
      List<Object?> types(String text) => [
        for (final line in const LineSplitter().convert(text))
          (jsonDecode(line) as Map<String, Object?>)['type'],
      ];
      expect(
        types(rootA),
        containsAllInOrder(['session', 'subagent', 'subagent']),
      );
      expect(types(childA).first, 'session');
      expect(rootA, contains('"type":"task"'));
    },
  );
}
