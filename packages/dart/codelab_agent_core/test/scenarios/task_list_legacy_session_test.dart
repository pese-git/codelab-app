import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';
import '../session/journal_lines.dart';

/// `core/task-list-legacy-session-continues` (agent-sessions «Список задач
/// из журнала», сценарий «Старая сессия с update_plan»; D12, TSK-6;
/// `agent-core/17-16-task-list.md` §17.16.6 «Старые сессии»).
///
/// Красный до задачи 1.3: нет чтения `plan` как списка задач, `TaskRecord` и
/// `AgentSession.tasks`.
void main() {
  const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

  test('journal with plan records only: list #1-#3, journal untouched, '
      'task_update writes one task record', () async {
    final text = journal([
      header(cwd: '/proj'),
      user('u1', null, text: 'plan the work'),
      plan('p1', 'u1', ['read']),
      plan('p2', 'p1', ['read', 'fix', 'run']),
    ]);
    final store = MemorySessionStore()..putText(id, text);
    final h = CoreHarness.build(
      baseEnv: MemoryExecutionEnv(cwd: '/proj'),
      narrow: noExec,
      gate: FakeGate(),
      sessions: store,
      steps: [
        callStep('c1', 'task_update', {'id': '2', 'status': 'completed'}),
        textStep('done'),
      ],
    );

    final session = await h.core.runtime.loadSession(
      id,
      const SessionHostPorts(),
    );

    // Последний plan целиком становится списком; owner main, без зависимостей.
    expect(
      [for (final i in session.tasks.items) (i.id, i.subject)],
      [('1', 'read'), ('2', 'fix'), ('3', 'run')],
    );
    expect(
      session.tasks.items.every(
        (i) => i.owner == TaskOwner.main && i.blockedBy.isEmpty,
      ),
      isTrue,
    );
    expect(store.textOf(id), text, reason: 'журнал побайтово не изменён');

    await session.prompt(const [TextContent('finish the second one')]);

    final appended = store.textOf(id)!.substring(text.length);
    final tasks = [
      for (final line in const LineSplitter().convert(appended))
        if ((jsonDecode(line) as Map<String, Object?>)['type'] == 'task')
          jsonDecode(line) as Map<String, Object?>,
    ];
    expect(tasks, hasLength(1), reason: 'одна запись task на одну операцию');
    expect(tasks.single['op'], 'update');
    expect(tasks.single['actor'], 'main');
    expect((tasks.single['items']! as List).single, containsPair('id', '2'));
    expect(
      (tasks.single['items']! as List).single,
      containsPair('status', 'completed'),
    );
    expect(appended, isNot(contains('"type":"plan"')));
    expect(
      [for (final i in session.tasks.items) i.status.name],
      ['pending', 'completed', 'pending'],
    );
  });
}
