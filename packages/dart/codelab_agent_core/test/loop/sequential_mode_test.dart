import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:codelab_agent_core/src/tools/tasks/task_tools.dart';
import 'package:test/test.dart';

import '../tools/fake_tools.dart';
import 'loop_harness.dart';

/// Барьер внутри пакета: `sequential`-вызов делит пакет на параллельные
/// группы, а не делает последовательным весь пакет (agent-loop «Пакет
/// инструментов», пять сценариев; LOOP-4; design.md change
/// `add-subagents-and-tasks`, D39; `agent-core/05-agent-loop.md` §5.5).
///
/// Прежний сценарий «один `sequential`-вызов делает последовательным весь
/// пакет» удалён: он противоречит решению Q18. Механизм групп проверяется на
/// тестовых `sequential`-двойниках: реальные `task_*` на ветке D39-alt
/// барьера не образуют (§17.16a.4).
///
/// Синхронизация — без `Future.delayed`: «работа» вызова — столько-то
/// оборотов очереди событий (`pumpEventQueue`), поэтому порядок завершения
/// параллельных вызовов детерминирован числом оборотов.
void main() {
  List<String> toolEvents(LoopHarness h) => [
    for (final t in h.trace)
      if (t.startsWith('ToolCall')) t,
  ];

  List<String> resultOrder(List<Message> added) => [
    for (final m in added.whereType<ToolResultMessage>()) m.toolCallId,
  ];

  /// Инструмент с журналом исполнения; [turns] — длительность в оборотах.
  FakeTool traced(
    String name,
    List<String> log, {
    ToolExecutionMode? mode,
    String? sequentialWhen,
    Map<String, int> turns = const {},
  }) => FakeTool(
    name,
    executionMode: mode,
    sequentialWhen: sequentialWhen,
    onExecute: (a, ctx) async {
      log.add('start ${ctx.toolCallId}');
      await pumpEventQueue(times: turns[ctx.toolCallId] ?? 1);
      log.add('end ${ctx.toolCallId}');
      return ToolExecutionResult([TextContent('${ctx.toolCallId} ok')]);
    },
  );

  test('сценарий «Барьер делит пакет на группы»: [read, task_update, agent, '
      'agent] — {read}, {task_update}, {agent, agent}', () async {
    final log = <String>[];
    final h = await LoopHarness.create(
      tools: [
        traced('read', log),
        traced('task_update', log, mode: ToolExecutionMode.sequential),
        // Второй agent короче первого: завершается раньше, но стартует позже.
        traced('agent', log, turns: {'a1': 6, 'a2': 1}),
      ],
      llm: script([
        callStep([
          ('r', 'read', const {}),
          ('t', 'task_update', const {}),
          ('a1', 'agent', const {}),
          ('a2', 'agent', const {}),
        ]),
        textStep('ok'),
      ]),
    );

    final added = await h.run([user('go')]);

    // Барьер начинается после завершения всего, что перед ним; обе агента
    // работают одновременно: старт второго раньше конца первого.
    expect(log, [
      'start r',
      'end r',
      'start t',
      'end t',
      'start a1',
      'start a2',
      'end a2',
      'end a1',
    ]);
    expect(toolEvents(h), [
      'ToolCallStarted(r)',
      'ToolCallFinished(r completed)',
      'ToolCallStarted(t)',
      'ToolCallFinished(t completed)',
      'ToolCallStarted(a1)',
      'ToolCallStarted(a2)',
      'ToolCallFinished(a2 completed)',
      'ToolCallFinished(a1 completed)',
    ]);
    // Результаты в транскрипте — в порядке ответа, не групп (LOOP-3).
    expect(resultOrder(added), ['r', 't', 'a1', 'a2']);
  });

  test('сценарий «Два барьера подряд»: [barrier, barrier, read, ls] '
      '— барьеры по одному в порядке ответа, затем read и ls вместе', () async {
    final log = <String>[];
    // Барьер — тестовый `sequential`-двойник: реальные `task_*` барьеров не
    // образуют (стратегия «parallel + очередь ключа», D39-alt), а сам
    // механизм групп цикла проверяется здесь.
    final h = await LoopHarness.create(
      tools: [
        traced('barrier', log, mode: ToolExecutionMode.sequential),
        traced('read', log, turns: {'r': 4}),
        traced('ls', log, turns: {'l': 1}),
      ],
      llm: script([
        callStep([
          ('c1', 'barrier', const {}),
          ('c2', 'barrier', const {}),
          ('r', 'read', const {}),
          ('l', 'ls', const {}),
        ]),
        textStep('ok'),
      ]),
    );

    await h.run([user('go')]);

    expect(toolEvents(h), [
      'ToolCallStarted(c1)',
      'ToolCallFinished(c1 completed)',
      'ToolCallStarted(c2)',
      'ToolCallFinished(c2 completed)',
      'ToolCallStarted(r)',
      'ToolCallStarted(l)',
      'ToolCallFinished(l completed)',
      'ToolCallFinished(r completed)',
    ]);
    // read и ls — одна параллельная группа: старты подряд, до первого конца.
    expect(log, [
      'start c1',
      'end c1',
      'start c2',
      'end c2',
      'start r',
      'start l',
      'end l',
      'end r',
    ]);
  });

  test(
    'сценарий «Отмена посреди группы»: [agent, agent, task_update, read] '
    '— группа {agent, agent} отменена токеном, остальные не стартуют',
    () async {
      final source = CancelTokenSource();
      var started = 0;
      final h = await LoopHarness.create(
        tools: [
          FakeTool(
            'agent',
            onExecute: (a, ctx) async {
              // Оба вызова группы успевают стартовать до отмены: каждый
              // «работает» несколько оборотов, затем отмена приходит во время
              // работы группы. Ожидания отмены нет намеренно: красный тест
              // падает утверждением, а не таймаутом.
              started++;
              await pumpEventQueue(times: 3);
              source.cancel();
              throw CancelledException(ctx.cancel.reason);
            },
          ),
          FakeTool('task_update', executionMode: ToolExecutionMode.sequential),
          FakeTool('read'),
        ],
        llm: script([
          callStep([
            ('a1', 'agent', const {}),
            ('a2', 'agent', const {}),
            ('t', 'task_update', const {}),
            ('r', 'read', const {}),
          ]),
        ]),
      );

      final added = await h.run([user('go')], cancel: source.token);

      final results = {
        for (final m in added.whereType<ToolResultMessage>())
          m.toolCallId: (m.content.single as TextContent).text,
      };
      expect(results, {
        'a1': 'Tool call was cancelled',
        'a2': 'Tool call was cancelled',
        't': 'Tool call was cancelled before it started',
        'r': 'Tool call was cancelled before it started',
      });
      expect(resultOrder(added), ['a1', 'a2', 't', 'r']);
      expect(started, 2, reason: 'оба agent стартовали одной группой');
      // Вызовы не начатых групп получают Started и Finished(cancelled).
      expect(toolEvents(h).toSet(), {
        'ToolCallStarted(a1)',
        'ToolCallStarted(a2)',
        'ToolCallFinished(a1 cancelled)',
        'ToolCallFinished(a2 cancelled)',
        'ToolCallStarted(t)',
        'ToolCallFinished(t cancelled)',
        'ToolCallStarted(r)',
        'ToolCallFinished(r cancelled)',
      });
      expect(h.trace.last, 'TurnEnded(cancelled)');
    },
  );

  group('сценарий «Режим по аргументам»', () {
    Future<List<String>> runBatch(
      List<Map<String, Object?>> args, {
      int longTurns = 3,
    }) async {
      final log = <String>[];
      final h = await LoopHarness.create(
        tools: [
          traced('step', log, sequentialWhen: 'lock', turns: {'c0': longTurns}),
        ],
        llm: script([
          callStep([for (final (i, a) in args.indexed) ('c$i', 'step', a)]),
          textStep('ok'),
        ]),
      );
      await h.run([user('go')]);
      return log;
    }

    test('без аргумента оба вызова — одна параллельная группа', () async {
      expect(await runBatch([const {}, const {}]), [
        'start c0',
        'start c1',
        'end c1',
        'end c0',
      ]);
    });

    test('с аргументом вызов — барьер: группа до него завершается, '
        'после него начинается следующая', () async {
      expect(
        await runBatch([
          const {},
          const {},
          const {'lock': true},
        ]),
        ['start c0', 'start c1', 'end c1', 'end c0', 'start c2', 'end c2'],
      );
    });

    test('барьер в начале пакета: он идёт один, затем группа', () async {
      expect(
        await runBatch([
          const {'lock': true},
          const {},
          const {},
        ], longTurns: 1),
        ['start c0', 'end c0', 'start c1', 'start c2', 'end c1', 'end c2'],
      );
    });
  });

  test('сценарий «Пакет без барьеров»: все Started по порядку ответа, затем '
      'вызовы одновременно — одна группа', () async {
    final log = <String>[];
    final h = await LoopHarness.create(
      tools: [
        traced('step', log, turns: {'c0': 5, 'c1': 3, 'c2': 1}),
      ],
      llm: script([
        callStep([
          ('c0', 'step', const {}),
          ('c1', 'step', const {}),
          ('c2', 'step', const {}),
        ]),
        textStep('ok'),
      ]),
    );

    final added = await h.run([user('go')]);

    expect(toolEvents(h), [
      'ToolCallStarted(c0)',
      'ToolCallStarted(c1)',
      'ToolCallStarted(c2)',
      'ToolCallFinished(c2 completed)',
      'ToolCallFinished(c1 completed)',
      'ToolCallFinished(c0 completed)',
    ]);
    expect(log.take(3), ['start c0', 'start c1', 'start c2']);
    expect(resultOrder(added), ['c0', 'c1', 'c2']);
  });

  test('отмена в пакете из одних барьеров: оставшиеся не стартуют '
      '(проверка отмены перед каждой группой, LOOP-4)', () async {
    final source = CancelTokenSource();
    final h = await LoopHarness.create(
      tools: [
        FakeTool(
          'step',
          executionMode: ToolExecutionMode.sequential,
          onExecute: (a, ctx) {
            source.cancel();
            return const ToolExecutionResult([TextContent('first')]);
          },
        ),
      ],
      llm: script([
        callStep([
          ('a', 'step', const {}),
          ('b', 'step', const {}),
          ('c', 'step', const {}),
        ]),
      ]),
    );

    final added = await h.run([user('go')], cancel: source.token);

    final results = {
      for (final m in added.whereType<ToolResultMessage>())
        m.toolCallId: (m.content.single as TextContent).text,
    };
    expect(results, {
      'a': 'first',
      'b': 'Tool call was cancelled before it started',
      'c': 'Tool call was cancelled before it started',
    });
    expect(toolEvents(h), [
      'ToolCallStarted(a)',
      'ToolCallFinished(a completed)',
      'ToolCallStarted(b)',
      'ToolCallFinished(b cancelled)',
      'ToolCallStarted(c)',
      'ToolCallFinished(c cancelled)',
    ]);
    expect(h.trace.last, 'TurnEnded(cancelled)');
  });

  // Реальные инструменты, не двойники: `task_*` барьеров не образуют
  // (`executionMode` не `sequential`, `lockKey` = `tasks`; D39-alt), поэтому
  // пакет — одна параллельная группа, а порядок операций списка держит
  // очередь ключа (D35, TSK-1).
  test(
    'реальные task_* и read: [task_create, read, task_create] — одна '
    'параллельная группа, task_create в порядке ответа (D35, D39-alt)',
    () async {
      final h = await LoopHarness.create(
        tools: [TaskCreateTool(), ReadTool()],
        llm: script([
          callStep([
            ('c1', 'task_create', {'subject': 'first'}),
            ('c2', 'read', {'path': 'a.txt'}),
            ('c3', 'task_create', {'subject': 'second'}),
          ]),
          textStep('ok'),
        ]),
      );
      await h.env.writeText('/proj/a.txt', 'A\n');

      final added = await h.run([user('go')]);

      final events = toolEvents(h);
      // Барьера нет: все три Started идут до первого Finished.
      expect(events.take(3), [
        'ToolCallStarted(c1)',
        'ToolCallStarted(c2)',
        'ToolCallStarted(c3)',
      ]);
      // Очередь ключа: c1 завершается раньше c3, id — по порядку ответа.
      expect(
        events.indexOf('ToolCallFinished(c1 completed)'),
        lessThan(events.indexOf('ToolCallFinished(c3 completed)')),
      );
      final created = [
        for (final m in added.whereType<ToolResultMessage>())
          if (m.toolName == 'task_create')
            (m.content.single as TextContent).text,
      ];
      expect(created[0], startsWith('Created task #1'));
      expect(created[1], startsWith('Created task #2'));
    },
  );
}
