import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';

/// S-05 на уровне ядра (agent-sessions «Список сессий и автоматический
/// заголовок», design.md D6).
void main() {
  test(
    'the first turn gives the title, the second does not change it',
    () async {
      final store = MemorySessionStore();
      final h = CoreHarness.build(
        baseEnv: MemoryExecutionEnv(cwd: '/proj'),
        narrow: noExec,
        gate: FakeGate(),
        sessions: store,
        steps: [textStep('Looking.'), textStep('Done.')],
      );
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      final events = <AgentEvent>[];
      session.events.listen(events.add);

      await session.prompt(const [TextContent('Почини тест парсера')]);
      await session.prompt(const [TextContent('И ещё один')]);
      await pumpEventQueue();

      final titles = events.whereType<SessionTitleChanged>().toList();
      expect(titles.single.title, 'Почини тест парсера');
      // Заголовок — после TurnEnded первого хода.
      final firstEnd = events.indexWhere((e) => e is TurnEnded);
      expect(events.indexOf(titles.single), greaterThan(firstEnd));
      final infos = [
        for (final line in const LineSplitter().convert(
          store.textOf(session.id)!,
        ))
          if (jsonDecode(line) case {'type': 'session_info'} && final info)
            info,
      ];
      expect(infos.single['title'], 'Почини тест парсера');
      expect(infos.single['source'], 'auto');
      expect(
        (await h.core.runtime.listSessions()).items.single.title,
        'Почини тест парсера',
      );
    },
  );

  test('a cancelled first turn still gives the title', () async {
    final h = CoreHarness.build(
      baseEnv: MemoryExecutionEnv(cwd: '/proj'),
      narrow: noExec,
      gate: FakeGate(),
      steps: [
        {'waitForCancel': true},
      ],
    );
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    final events = <AgentEvent>[];
    session.events.listen(events.add);

    final turn = session.prompt(const [TextContent('Long task')]);
    await pumpEventQueue();
    await session.cancel();
    await turn;
    await pumpEventQueue();

    expect(events.whereType<SessionTitleChanged>().single.title, 'Long task');
  });
}
