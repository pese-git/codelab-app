import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../permissions/fake_gate.dart';
import '../tools/fake_shell.dart';
import 'subagent_rig.dart';

/// Запрос разрешения потомка идёт в gate корневой сессии (agent-permissions
/// «Разрешения потомка через gate корневой сессии»: «Два ребёнка спрашивают
/// одновременно», «Запрет всегда нельзя обойти через ребёнка»; design.md
/// change `add-subagents-and-tasks`, D8, D42 Т1, Т3, Т4, Т8; PERM-4, PERM-7,
/// SUB-3; `agent-core/17-3-subagents.md` §17.3.3, «Разрешения потомка через
/// gate корневой сессии»; задача 3.1).
///
/// Красные до задачи 3.2: у ребёнка нет gate (D38), любой его вопрос — отказ
/// `no approval interface is available`, а gate корня не вызывается. Зелёный
/// сразу только характеризующий тест «Запрет всегда нельзя обойти через
/// ребёнка» (D42 Т1: хранилище решений корня у ребёнка уже общее).
///
/// Время — `FakeClock` рига; синхронизация — `pumpUntil` по наблюдаемым
/// событиям, а не `Future.delayed`.
void main() {
  /// Корень вызывает [children] детей; каждый ребёнок пишет свой файл.
  ///
  /// Скрипты ребёнка выбираются по тексту `prompt`, поэтому у детей разные
  /// `prompt` (`SubagentRig`).
  SubagentRig writers(PermissionGate gate, {int children = 1}) => SubagentRig(
    gate: gate,
    scripts: {
      'go': [
        multiCallStep([
          for (var i = 1; i <= children; i++)
            ('c$i', 'agent', agentArgs('job $i', description: 'Write $i')),
        ]),
        replyStep('done'),
      ],
      for (var i = 1; i <= children; i++)
        'job $i': [
          oneCallStep('w1', 'write', {'path': 'f$i.txt', 'content': 'x'}),
          replyStep('written $i'),
        ],
    },
  );

  group('одиночный ребёнок', () {
    test('запрос приходит в gate корня с цепочкой toolCallId и префиксом '
        'title, остальное — как у ребёнка (D8, PERM-4, PERM-6)', () async {
      final gate = FakeGate();
      final rig = writers(gate);
      await rig.open();

      await rig.run('go');

      final request = gate.requests.single;
      expect(request.toolCallId, 'c1/w1');
      expect(request.title, startsWith('[general: Write 1] Write '));
      expect(request.title, endsWith('f1.txt'));
      expect(request.tool, 'write');
      expect(request.rawInput['path'], 'f1.txt');
      expect(request.allowAlwaysOffered, isTrue);
    });

    test(
      'PermissionRequest.subagent несёт id, тип, описание, глубину, путь '
      'и вызов agent корня (D42 Т4); у запроса самого корня — null',
      () async {
        final gate = FakeGate();
        final rig = SubagentRig(
          gate: gate,
          scripts: {
            'go': [
              multiCallStep([
                ('w0', 'write', {'path': 'root.txt', 'content': 'r'}),
                ('c1', 'agent', agentArgs('job 1', description: 'Write 1')),
              ]),
              replyStep('done'),
            ],
            'job 1': [
              oneCallStep('w1', 'write', {'path': 'f1.txt', 'content': 'x'}),
              replyStep('written'),
            ],
          },
        );
        await rig.open();

        await rig.run('go');

        final byId = {for (final r in gate.requests) r.toolCallId: r};
        expect(byId.keys, unorderedEquals(['w0', 'c1/w1']));
        expect(byId['w0']!.subagent, isNull);
        final info = byId['c1/w1']!.subagent!;
        expect(info.id, rig.eventsOf<SubagentStarted>().single.subagentId);
        expect(info.type, 'general');
        expect(info.description, 'Write 1');
        expect(info.depth, 1);
        expect(info.path, isEmpty);
        expect(info.parentToolCallId, 'c1');
      },
    );

    test('ребёнок в waiting с waitingFor approval, пока вопрос ждёт ответа, '
        'и снова running после ответа (SubagentWait.approval)', () async {
      final gate = _HoldingGate();
      final rig = writers(gate);
      await rig.open();

      final turn = rig.run('go');
      await pumpUntil(
        () => gate.requests.isNotEmpty,
        reason: 'the question never reached the root gate',
      );
      await pumpUntil(
        () => _snapshots(rig).any((s) => s.state == SubagentState.waiting),
        reason: 'the child never reported waiting',
      );

      final waiting = _snapshots(
        rig,
      ).lastWhere((s) => s.state == SubagentState.waiting);
      expect(waiting.waitingFor, SubagentWait.approval);
      final before = _snapshots(rig).length;

      gate.answer(0, PermissionDecision.allowOnce);
      await pumpUntil(
        () => _snapshots(
          rig,
        ).skip(before).any((s) => s.state == SubagentState.running),
        reason: 'the child never went back to running',
      );
      await turn;

      expect(
        rig.eventsOf<SubagentFinished>().single.status,
        SubagentState.completed,
        reason: 'после ответа ребёнок дошёл до отчёта',
      );
    });

    test(
      'лог subagent.permission.queued: subagent_id, цепочка '
      'tool_call_id, queue_length; без текстов запроса (D18, D42 Т8)',
      () async {
        final rig = writers(FakeGate());
        await rig.open();

        await rig.run('go');

        final queued = rig.logger.eventsOf('subagent.permission.queued').single;
        expect(
          queued.fields['subagent_id'],
          rig.eventsOf<SubagentStarted>().single.subagentId,
        );
        expect(queued.fields['tool_call_id'], 'c1/w1');
        expect(queued.fields['queue_length'], isA<int>());
      },
    );
  });

  test(
    'два параллельных вопроса одного ребёнка: waiting держится до ответа '
    'на последний, running — только при нуле открытых (ревью итерации 3)',
    () async {
      final gate = _HoldingGate();
      final rig = SubagentRig(
        gate: gate,
        scripts: {
          'go': [
            oneCallStep('c1', 'agent', agentArgs('job 1', description: 'Two')),
            replyStep('done'),
          ],
          'job 1': [
            multiCallStep([
              ('w1', 'write', {'path': 'a.txt', 'content': 'x'}),
              ('w2', 'write', {'path': 'b.txt', 'content': 'x'}),
            ]),
            replyStep('written'),
          ],
        },
      );
      await rig.open();

      final turn = rig.run('go');
      await pumpUntil(
        () => gate.requests.isNotEmpty,
        reason: 'the first question never reached the root gate',
      );
      await pumpUntil(
        () => _snapshots(rig).any((s) => s.state == SubagentState.waiting),
        reason: 'the child never reported waiting',
      );
      final before = _snapshots(rig).length;

      gate.answer(0, PermissionDecision.allowOnce);
      await pumpUntil(
        () => gate.requests.length == 2,
        reason: 'the second question must follow the first answer',
      );

      expect(
        _snapshots(rig).skip(before).map((s) => s.state),
        isNot(contains(SubagentState.running)),
        reason: 'второй вопрос ещё открыт: ребёнок остаётся в waiting',
      );
      gate.answer(1, PermissionDecision.allowOnce);
      await turn;
      expect(
        rig.eventsOf<SubagentFinished>().single.status,
        SubagentState.completed,
      );
    },
  );

  group('два ребёнка (сценарий «Два ребёнка спрашивают одновременно»)', () {
    test('второй запрос уходит в gate только после ответа на первый; '
        'toolCallId — c1/w1 и c2/w1 (FIFO дерева)', () async {
      final gate = _HoldingGate();
      final rig = writers(gate, children: 2);
      await rig.open();

      final turn = rig.run('go');
      await pumpUntil(
        () => gate.requests.isNotEmpty,
        reason: 'no question reached the root gate',
      );
      // Оба ребёнка уже спросили, но к пользователю уходит один запрос:
      // ждём, пока оба окажутся в waiting, и проверяем, что очередь держит
      // второй.
      await pumpUntil(
        () =>
            _snapshots(rig)
                .where((s) => s.state == SubagentState.waiting)
                .map((s) => s.id)
                .toSet()
                .length ==
            2,
        reason: 'both children should be waiting for approval',
      );
      expect(gate.requests, hasLength(1), reason: 'FIFO: один запрос за раз');

      gate.answer(0, PermissionDecision.allowOnce);
      await pumpUntil(
        () => gate.requests.length == 2,
        reason: 'the second question must follow the first answer',
      );
      gate.answer(1, PermissionDecision.allowOnce);
      await turn;

      expect(gate.requests.map((r) => r.toolCallId), [
        anyOf('c1/w1', 'c2/w1'),
        anyOf('c1/w1', 'c2/w1'),
      ]);
      expect(gate.requests.map((r) => r.toolCallId).toSet(), {
        'c1/w1',
        'c2/w1',
      }, reason: 'ids различны и уникальны в сессии корня (PERM-4)');
      expect(
        {for (final r in gate.requests) r.toolCallId: r.title},
        {
          'c1/w1': startsWith('[general: Write 1] '),
          'c2/w1': startsWith('[general: Write 2] '),
        },
      );
    });

    test('запрос самого корня очередь детей не ждёт', () async {
      final gate = _HoldingGate();
      final rig = SubagentRig(
        gate: gate,
        scripts: {
          'go': [
            multiCallStep([
              ('c1', 'agent', agentArgs('job 1', description: 'Write 1')),
              ('w0', 'write', {'path': 'root.txt', 'content': 'r'}),
            ]),
            replyStep('done'),
          ],
          'job 1': [
            oneCallStep('w1', 'write', {'path': 'f1.txt', 'content': 'x'}),
            replyStep('written'),
          ],
        },
      );
      await rig.open();

      final turn = rig.run('go');
      await pumpUntil(
        () => gate.requests.length == 2,
        reason: 'root and child questions are both outstanding',
      );

      expect(
        gate.requests.map((r) => r.toolCallId),
        unorderedEquals(['w0', 'c1/w1']),
      );
      gate.answer(0, PermissionDecision.allowOnce);
      gate.answer(1, PermissionDecision.allowOnce);
      await turn;
    });
  });

  group('отмена ребёнка снимает его запрос (PERM-7)', () {
    test('запрос в очереди FIFO не доходит до gate; отправленный получает '
        'отменённый токен; оба ребёнка — cancelled', () async {
      final gate = _HoldingGate();
      final rig = writers(gate, children: 2);
      await rig.open();

      final turn = rig.run('go');
      await pumpUntil(
        () => gate.requests.isNotEmpty,
        reason: 'no question reached the root gate',
      );
      await pumpUntil(
        () =>
            _snapshots(rig)
                .where((s) => s.state == SubagentState.waiting)
                .map((s) => s.id)
                .toSet()
                .length ==
            2,
        reason: 'both children should be waiting for approval',
      );
      await rig.session.cancel();
      final result = await turn;

      expect(result.reason, TurnEndReason.cancelled);
      expect(
        gate.requests,
        hasLength(1),
        reason: 'запрос из очереди снят без кадра',
      );
      expect(gate.tokens.single.isCancelled, isTrue);
      expect(
        {
          for (final f in rig.eventsOf<SubagentFinished>())
            f.parentToolCallId: f.status,
        },
        {'c1': SubagentState.cancelled, 'c2': SubagentState.cancelled},
      );
    });

    test('единственный запрос после отправки: токен gate отменён, ход '
        'завершается cancelled', () async {
      final gate = _HoldingGate();
      final rig = writers(gate);
      await rig.open();

      final turn = rig.run('go');
      await pumpUntil(
        () => gate.requests.isNotEmpty,
        reason: 'the question never reached the root gate',
      );
      await rig.session.cancel();
      final result = await turn;

      expect(result.reason, TurnEndReason.cancelled);
      expect(gate.tokens.single.isCancelled, isTrue);
      expect(
        rig.eventsOf<SubagentFinished>().single.status,
        SubagentState.cancelled,
      );
    });
  });

  test('характеризующий, зелёный сразу: сценарий «Запрет всегда нельзя '
      'обойти через ребёнка» — rejectAlways корня действует на ребёнка без '
      'запроса к gate (D42 Т1)', () async {
    final shell = FakeShellEnv(MemoryExecutionEnv(cwd: '/proj'), answering(''));
    final gate = FakeGate(
      (req) => req.toolCallId == 'x0'
          ? PermissionDecision.rejectAlways
          : PermissionDecision.allowOnce,
    );
    final rig = SubagentRig(
      baseEnv: shell,
      narrow: const {},
      gate: gate,
      scripts: {
        'go': [
          oneCallStep('x0', 'exec', {'command': 'rm -rf build'}),
          oneCallStep('c1', 'agent', agentArgs('clean up')),
          replyStep('done'),
        ],
        'clean up': [
          oneCallStep('x1', 'exec', {'command': 'rm -rf build'}),
          replyStep('stopped'),
        ],
      },
    );
    await rig.open();

    await rig.run('go');

    final child = rig.requestsOf('clean up').last;
    expect(resultIsError(child, 'x1'), isTrue);
    expect(
      resultText(child, 'x1'),
      contains('previously rejected by the user'),
    );
    expect([for (final r in gate.requests) r.toolCallId], ['x0']);
    expect(shell.commands, isEmpty);
  });
}

/// Снимки `SubagentProgress` корневой сессии в порядке прихода.
List<SubagentSnapshot> _snapshots(SubagentRig rig) => [
  for (final e in rig.eventsOf<SubagentProgress>()) e.snapshot,
];

/// Gate, который держит каждый запрос до явного ответа теста.
///
/// Почему не `FakeGate` с `FakeClock`: тесту нужно разделить «запрос ушёл» и
/// «ответ дан», чтобы наблюдать очередь FIFO, `waiting` и отмену. Токены
/// запросов сохраняются для проверки PERM-7.
final class _HoldingGate implements PermissionGate {
  final requests = <PermissionRequest>[];
  final tokens = <CancelToken>[];
  final _answers = <Completer<PermissionDecision>>[];

  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) {
    requests.add(req);
    tokens.add(cancel);
    final completer = Completer<PermissionDecision>();
    _answers.add(completer);
    return completer.future;
  }

  /// Отвечает на запрос с номером [index] в порядке прихода.
  void answer(int index, PermissionDecision decision) =>
      _answers[index].complete(decision);
}
