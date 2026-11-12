// Метаданные пунктов плана `_meta.codelab.task` (задача 1.1, «kit» change
// `add-subagents-and-tasks`; spec acp-client-kit «Метаданные пунктов плана»;
// design.md, D15).
//
// Красные тесты: у `PlanEntryView` пока нет полей `taskId`, `owner`,
// `blockedBy`, `openBlockers`, `ownerLabel` (задача 1.6) — файл не
// компилируется, пока их нет. Имена полей — предложение этой задачи; их же
// использует desktop (задача 1.8).

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

/// Кадр `plan`: каждый пункт — `(content, status, _meta?)`.
Map<String, Object?> _plan(
  List<(String, String, Map<String, Object?>?)> entries,
) => {
  'sessionUpdate': 'plan',
  'entries': [
    for (final (content, status, meta) in entries)
      {
        'content': content,
        'status': status,
        'priority': 'medium',
        '_meta': ?meta,
      },
  ],
};

/// `_meta.codelab.task` пункта плана (design.md, D15).
Map<String, Object?> _taskMeta(Object? task) => {
  'codelab': {'task': task},
};

void main() {
  late KitAgent agent;
  late SessionHandle session;

  setUp(() async {
    agent = KitAgent();
    await agent.start();
    session = await agent.newSession('s1');
    await agent.prompt(session, 'go');
  });
  tearDown(() => agent.dispose());

  Future<List<PlanEntryView>> planAfter(Map<String, Object?> update) async {
    agent.update('s1', update);
    await pumpEventQueue();
    return session.current.plan;
  }

  test('plan with metadata: id, owner and the open blocker of the second '
      'entry are projected', () async {
    final plan = await planAfter(
      _plan([
        ('Read code', 'pending', _taskMeta({'id': '1'})),
        (
          'Write tests',
          'pending',
          _taskMeta({
            'id': '2',
            'owner': 'sub_a1',
            'blockedBy': ['1'],
          }),
        ),
      ]),
    );

    expect(plan[0].taskId, '1');
    expect(plan[0].owner, isNull);
    expect(plan[0].blockedBy, isEmpty);
    expect(plan[1].taskId, '2');
    expect(plan[1].owner, 'sub_a1');
    expect(plan[1].blockedBy, ['1']);
    // Первый пункт не completed, поэтому блокер `1` остаётся открытым.
    expect(plan[1].openBlockers, ['1']);
    // Субагент `sub_a1` kit не известен (вызовов agent нет) — метка владельца
    // совпадает с его id.
    expect(plan[1].ownerLabel, 'sub_a1');
  });

  test(
    'a completed blocker is not an open one; owner main has no label',
    () async {
      final plan = await planAfter(
        _plan([
          ('Read code', 'completed', _taskMeta({'id': '1', 'owner': 'main'})),
          (
            'Write tests',
            'in_progress',
            _taskMeta({
              'id': '2',
              'blockedBy': ['1'],
            }),
          ),
        ]),
      );

      expect(plan[1].blockedBy, ['1']);
      expect(plan[1].openBlockers, isEmpty);
      expect(plan[0].owner, 'main');
      expect(plan[0].ownerLabel, isNull);
      expect(plan[1].ownerLabel, isNull);
    },
  );

  test('a plan of a third-party agent without _meta keeps the old '
      'projection', () async {
    final plan = await planAfter(
      _plan([('Read', 'completed', null), ('Edit', 'pending', null)]),
    );

    expect(plan.map((e) => e.content), ['Read', 'Edit']);
    expect(plan.every((e) => e.taskId == null), isTrue);
    expect(plan.every((e) => e.owner == null), isTrue);
    expect(plan.every((e) => e.blockedBy.isEmpty), isTrue);
    expect(plan.every((e) => e.openBlockers.isEmpty), isTrue);
    expect(plan.every((e) => e.ownerLabel == null), isTrue);
  });

  test('wrong metadata shapes give empty fields and the update is applied '
      'without an error', () async {
    final plan = await planAfter(
      _plan([
        ('Bad ids', 'pending', _taskMeta({'id': 5, 'blockedBy': '1'})),
        ('Bad task', 'pending', _taskMeta('not-an-object')),
        ('Bad codelab', 'pending', {'codelab': 'x'}),
        (
          'Unknown keys',
          'pending',
          _taskMeta({
            'id': '9',
            'future': {'x': 1},
          }),
        ),
      ]),
    );

    expect(plan, hasLength(4));
    expect(plan[0].taskId, isNull);
    expect(plan[0].blockedBy, isEmpty);
    expect(plan[1].taskId, isNull);
    expect(plan[2].taskId, isNull);
    // Неизвестные ключи игнорируются, известные поля читаются.
    expect(plan[3].taskId, '9');
    expect(agent.diagnostics, isEmpty);
  });

  test('each plan update still replaces the plan as a whole', () async {
    await planAfter(
      _plan([
        ('a', 'pending', _taskMeta({'id': '1'})),
        ('b', 'pending', _taskMeta({'id': '2'})),
      ]),
    );
    final plan = await planAfter(
      _plan([
        ('c', 'pending', _taskMeta({'id': '3'})),
      ]),
    );

    expect(plan.map((e) => e.taskId), ['3']);
  });
}
