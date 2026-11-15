import 'dart:async';
import 'dart:math' as math;

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../support/models.dart';
import 'subagent_rig.dart';

/// Слоты и лимиты дерева при вложенности до 3 (agent-subagents «Вложенность и
/// слоты дерева», сценарии «Возвращающийся родитель раньше нового ребёнка»,
/// «Предел слотов дерева», «Слот в смешанной группе», «Вопрос во время
/// ожидания детей», «Перезагрузка max_depth посреди дерева», «Лимит запусков
/// считает внуков»; SUB-5, SUB-23, SUB-24; design.md change
/// `add-subagents-and-tasks`, D3, D45 Т2, Т4, D46 пп. 1–2;
/// `agent-core/17-3-subagents.md` §17.3.4, шаг 2).
///
/// Красные до задачи 4.2: у потомка нет `agent`, менеджера и передачи слота
/// (`_maxChildDepth = 1`), поэтому внуков нет вовсе. Тесты ждут наблюдаемых
/// условий (`pumpUntil`) и двигают `FakeClock`, а не `Future.delayed`.
void main() {
  CoreConfig tree({
    int maxConcurrent = 3,
    int maxPerTurn = 10,
    int maxDepth = 3,
  }) => CoreConfig(
    defaultModel: subagentTestModel,
    subagents: SubagentsConfig(
      maxConcurrent: maxConcurrent,
      maxPerTurn: maxPerTurn,
      maxDepth: maxDepth,
    ),
  );

  /// Ключи запросов к модели по всему дереву в порядке прихода.
  List<String> requestOrder(SubagentRig rig) => [
    for (final c in rig.contexts) firstUserText(c),
  ];

  group(
    'сценарий «Возвращающийся родитель раньше нового ребёнка» (SUB-23)',
    () {
      test(
        'при max_concurrent 1 внук завершился, новый ребёнок уже в очереди — '
        'слот получает родитель внука, новый ребёнок идёт после него',
        () async {
          // alpha и beta — дети корня; alpha запускает gamma, beta — delta.
          // Очередь новых детей к моменту, когда gamma стала работать: delta
          // стоит в ней, потому что её поставил beta уже после gamma.
          final rig = SubagentRig(
            config: tree(maxConcurrent: 1),
            scripts: {
              'go': [
                multiCallStep([
                  ('a1', 'agent', agentArgs('alpha', description: 'Alpha')),
                  ('a2', 'agent', agentArgs('beta', description: 'Beta')),
                ]),
                replyStep('done'),
              ],
              'alpha': [
                oneCallStep(
                  'g1',
                  'agent',
                  agentArgs('gamma', description: 'G'),
                ),
                replyStep('alpha done'),
              ],
              'beta': [
                oneCallStep(
                  'd1',
                  'agent',
                  agentArgs('delta', description: 'D'),
                ),
                replyStep('beta done'),
              ],
              'gamma': [replyStep('gamma done', delayMs: 10)],
              'delta': [replyStep('delta done')],
            },
          );
          await rig.open();

          final turn = rig.run('go');
          await pumpUntil(
            () =>
                rig.requestsOf('gamma').isNotEmpty &&
                rig.logger.eventsOf('subagent.spawn').length == 4,
            reason:
                'gamma must hold the only slot while delta waits in the queue',
          );
          expect(
            rig.requestsOf('delta'),
            isEmpty,
            reason: 'delta ждёт слота за gamma',
          );
          await rig.clock.elapse(const Duration(milliseconds: 10));
          await turn;

          final order = requestOrder(rig);
          expect(
            order.where((k) => k == 'alpha'),
            hasLength(2),
            reason: 'alpha делает второй запрос после возврата слота',
          );
          expect(
            order.lastIndexOf('alpha'),
            lessThan(order.indexOf('delta')),
            reason: 'возвращающийся родитель раньше нового ребёнка',
          );
        },
      );
    },
  );

  group('сценарий «Предел слотов дерева» (глубина 3)', () {
    /// Потомки, держащие слот на сейчас: `running` или `waiting` с
    /// `approval`. По снимкам прогресса; вызывается в устойчивой точке, когда
    /// очередь событий пуста, поэтому порядок кадров внутри одного оборота не
    /// влияет на результат.
    int holders(SubagentRig rig) {
      final finished = {for (final f in allFinished(rig)) f.subagentId};
      final latest = <SubagentId, SubagentSnapshot>{};
      for (final s in allSnapshots(rig)) {
        latest[s.id] = s;
      }
      return latest.values
          .where(
            (s) =>
                !finished.contains(s.id) &&
                (s.state == SubagentState.running ||
                    (s.state == SubagentState.waiting &&
                        s.waitingFor == SubagentWait.approval)),
          )
          .length;
    }

    test('три ребёнка корня, каждый запускает двух внуков, при '
        'max_concurrent 2 слот держат не больше двух потомков, все девять '
        'завершаются', () async {
      final rig = SubagentRig(
        config: tree(maxConcurrent: 2),
        scripts: {
          'go': [
            multiCallStep([
              for (var i = 1; i <= 3; i++)
                ('k$i', 'agent', agentArgs('kid $i', description: 'Kid $i')),
            ]),
            replyStep('done'),
          ],
          for (var i = 1; i <= 3; i++) ...{
            'kid $i': [
              multiCallStep([
                ('x$i', 'agent', agentArgs('leaf $i a', description: 'Leaf a')),
                ('y$i', 'agent', agentArgs('leaf $i b', description: 'Leaf b')),
              ]),
              replyStep('kid $i done'),
            ],
            'leaf $i a': [replyStep('leaf $i a done', delayMs: 10)],
            'leaf $i b': [replyStep('leaf $i b done', delayMs: 10)],
          },
        },
      );
      await rig.open();

      final turn = rig.run('go');
      var finishedTurn = false;
      unawaited(turn.then((_) => finishedTurn = true));
      var peak = 0;
      for (var i = 0; i < 300 && !finishedTurn; i++) {
        await pumpEventQueue(times: 50);
        peak = math.max(peak, holders(rig));
        await rig.clock.elapse(const Duration(milliseconds: 10));
      }
      await turn;

      expect(allStarted(rig), hasLength(9), reason: '3 ребёнка и 6 внуков');
      expect(
        allFinished(rig).map((f) => f.status),
        everyElement(SubagentState.completed),
      );
      expect(peak, inInclusiveRange(1, 2));
    });
  });

  group('лимиты запусков дерева (SUB-5)', () {
    test('сценарий «Лимит запусков считает внуков»: max_per_turn 3, корень '
        'запускает двух детей, первый — двух внуков: второй внук получает '
        'ошибку лимита, остальные работают', () async {
      final rig = SubagentRig(
        config: tree(maxPerTurn: 3),
        scripts: {
          'go': [
            multiCallStep([
              ('a1', 'agent', agentArgs('first', description: 'First')),
              ('a2', 'agent', agentArgs('second', description: 'Second')),
            ]),
            replyStep('done'),
          ],
          'first': [
            multiCallStep([
              ('g1', 'agent', agentArgs('leaf one', description: 'Leaf one')),
              ('g2', 'agent', agentArgs('leaf two', description: 'Leaf two')),
            ]),
            replyStep('first done'),
          ],
          'second': [replyStep('second done')],
          'leaf one': [replyStep('leaf one done')],
          'leaf two': [replyStep('never runs')],
        },
      );
      await rig.open();

      await rig.run('go');

      final first = rig.requestsOf('first').last;
      expect(resultText(first, 'g1'), contains('leaf one done'));
      expect(resultIsError(first, 'g1'), isFalse);
      expect(
        resultText(first, 'g2'),
        startsWith('Subagent limit reached: at most 3 subagents per turn.'),
      );
      expect(resultIsError(first, 'g2'), isTrue);
      expect(rig.requestsOf('leaf two'), isEmpty);
      expect(
        resultText(rig.requestsOf('go').last, 'a2'),
        contains('second done'),
      );
    });

    test('ход ребёнка не сбрасывает счётчик max_per_turn (D45 Т2): при '
        'лимите 2 корень запустил ребёнка, ребёнок — двух внуков, второй '
        'внук получает ошибку лимита', () async {
      final rig = SubagentRig(
        config: tree(maxPerTurn: 2),
        scripts: {
          'go': [
            oneCallStep('a1', 'agent', agentArgs('kid', description: 'Kid')),
            replyStep('done'),
          ],
          'kid': [
            multiCallStep([
              ('g1', 'agent', agentArgs('leaf one', description: 'Leaf one')),
              ('g2', 'agent', agentArgs('leaf two', description: 'Leaf two')),
            ]),
            replyStep('kid done'),
          ],
          'leaf one': [replyStep('leaf one done')],
          'leaf two': [replyStep('never runs')],
        },
      );
      await rig.open();

      await rig.run('go');

      final kid = rig.requestsOf('kid').last;
      expect(resultText(kid, 'g1'), contains('leaf one done'));
      expect(
        resultText(kid, 'g2'),
        startsWith('Subagent limit reached: at most 2 subagents per turn.'),
        reason: 'начало хода ребёнка счётчик дерева не обнуляет',
      );
      expect(rig.requestsOf('leaf two'), isEmpty);
    });
  });

  test('потомок, отменённый в очереди возвращающихся, слот не отдаёт '
      '(D45 Т4): ход корня отменён, пока alpha ждёт слота для возврата — '
      'alpha отпускала слот ровно один раз, слотов не больше max_concurrent '
      'на всех шагах', () async {
    // alpha запускает gamma и отдаёт слот; слот берёт xholder и держит его до
    // отмены, gamma стоит в очереди. Отмена корня снимает и gamma, и
    // возврат alpha: чужой слот alpha вернуть не может.
    final rig = SubagentRig(
      config: tree(maxConcurrent: 1),
      scripts: {
        'go': [
          multiCallStep([
            ('a1', 'agent', agentArgs('alpha', description: 'Alpha')),
            ('a2', 'agent', agentArgs('xholder', description: 'Holder')),
          ]),
          replyStep('never requested'),
        ],
        'alpha': [
          oneCallStep('g1', 'agent', agentArgs('gamma', description: 'G')),
          replyStep('never requested'),
        ],
        'xholder': [
          {
            'waitForCancel': true,
            'reply': [
              {'text': 'holding'},
            ],
          },
        ],
        'gamma': [replyStep('never requested')],
      },
    );
    await rig.open();

    final turn = rig.run('go');
    await pumpUntil(
      () => rig.requestsOf('xholder').isNotEmpty,
      reason: 'xholder must take the slot alpha returned',
    );
    final alpha = rig.eventsOf<SubagentStarted>().first.subagentId;
    await pumpUntil(
      () => latestSnapshot(rig, alpha)?.waitingFor == SubagentWait.subagents,
      reason: 'alpha must wait for its child',
    );
    await rig.session.cancel();
    final result = await turn;

    expect(result.reason, TurnEndReason.cancelled);
    final releases = rig.logger.eventsOf('subagent.slot.release');
    final byOwner = <Object?, int>{};
    for (final r in releases) {
      byOwner.update(r.fields['subagent_id'], (n) => n + 1, ifAbsent: () => 1);
    }
    final holder = rig.eventsOf<SubagentStarted>().last.subagentId;
    expect(byOwner[alpha], 1, reason: 'alpha вернула слот при ожидании');
    expect(byOwner[holder], 1);
    expect(byOwner.length, 2, reason: 'gamma слота не держала');
    expect(
      releases.map((r) => r.fields['free_slots'] as int),
      everyElement(lessThanOrEqualTo(1)),
    );
    expect(releases.last.fields['free_slots'], 1);
  });

  group('возврат слота ждущим родителем (D46, п. 1)', () {
    test('сценарий «Слот в смешанной группе»: при max_concurrent 1 ребёнок '
        'в одном ответе вызывает agent и read — он в waiting/subagents, внук '
        'получает слот, read исполняется без слота; ToolCallFinished '
        'вызова agent — после subagent.slot.resume', () async {
      final env = MemoryExecutionEnv(cwd: '/proj');
      await env.writeText('/proj/a.txt', 'alpha\n');
      final rig = SubagentRig(
        baseEnv: env,
        config: tree(maxConcurrent: 1),
        scripts: {
          'go': [
            oneCallStep('a1', 'agent', agentArgs('alpha', description: 'A')),
            replyStep('done'),
          ],
          'alpha': [
            multiCallStep([
              ('g1', 'agent', agentArgs('gamma', description: 'G')),
              ('r1', 'read', {'path': 'a.txt'}),
            ]),
            replyStep('alpha done'),
          ],
          'gamma': [replyStep('gamma done', delayMs: 10)],
        },
      );
      await rig.open();
      int? resumesAtFinish;
      rig.session.events.listen((e) {
        if (e is SubagentActivity &&
            e.event is ToolCallFinished &&
            (e.event as ToolCallFinished).toolCallId == 'g1') {
          resumesAtFinish = rig.logger.eventsOf('subagent.slot.resume').length;
        }
      });

      final turn = rig.run('go');
      await pumpUntil(
        () =>
            rig.requestsOf('gamma').isNotEmpty &&
            treeEvents(
              rig,
            ).whereType<ToolCallFinished>().any((f) => f.toolCallId == 'r1'),
        reason: 'gamma takes the slot and the read runs without one',
      );

      final alpha = rig.eventsOf<SubagentStarted>().single.subagentId;
      final waiting = latestSnapshot(rig, alpha)!;
      expect(waiting.state, SubagentState.waiting);
      expect(waiting.waitingFor, SubagentWait.subagents);
      expect(
        rig.logger.eventsOf('subagent.slot.resume'),
        isEmpty,
        reason: 'alpha ещё ждёт внука и слота не взяла',
      );

      await rig.clock.elapse(const Duration(milliseconds: 10));
      await turn;

      final resume = rig.logger.eventsOf('subagent.slot.resume').single;
      expect(resume.fields['subagent_id'], alpha);
      expect(resume.fields['free_slots'], isA<int>());
      expect(
        resumesAtFinish,
        1,
        reason: 'результат agent — после повторного взятия слота',
      );
    });

    test(
      'сценарий «Вопрос во время ожидания детей»: ребёнок ждёт внука '
      'блокирующим agent, параллельный write ждёт решения — waiting/'
      'approval; после ответа, пока внук работает, — waiting/subagents',
      () async {
        final gate = _HoldingGate();
        final rig = SubagentRig(
          gate: gate,
          config: tree(maxConcurrent: 1),
          scripts: {
            'go': [
              oneCallStep('a1', 'agent', agentArgs('alpha', description: 'A')),
              replyStep('done'),
            ],
            'alpha': [
              multiCallStep([
                ('g1', 'agent', agentArgs('gamma', description: 'G')),
                ('w1', 'write', {'path': 'f.txt', 'content': 'x'}),
              ]),
              replyStep('alpha done'),
            ],
            'gamma': [replyStep('gamma done', delayMs: 10)],
          },
        );
        await rig.open();

        final turn = rig.run('go');
        await pumpUntil(
          () => gate.requests.isNotEmpty && rig.requestsOf('gamma').isNotEmpty,
          reason: 'alpha asks the user while gamma works',
        );
        final alpha = rig.eventsOf<SubagentStarted>().single.subagentId;
        await pumpUntil(
          () => latestSnapshot(rig, alpha)?.waitingFor == SubagentWait.approval,
          reason: 'approval must win over subagents in waitingFor',
        );
        expect(latestSnapshot(rig, alpha)!.state, SubagentState.waiting);

        final before = allSnapshots(rig).length;
        gate.answer(0, PermissionDecision.allowOnce);
        await pumpUntil(
          () => allSnapshots(rig)
              .skip(before)
              .any(
                (s) =>
                    s.id == alpha &&
                    s.state == SubagentState.waiting &&
                    s.waitingFor == SubagentWait.subagents,
              ),
          reason: 'after the answer alpha still waits for gamma',
        );
        expect(allFinished(rig), isEmpty, reason: 'gamma ещё работает');

        await rig.clock.elapse(const Duration(milliseconds: 10));
        await turn;
        expect(
          allFinished(rig).map((f) => f.status),
          everyElement(SubagentState.completed),
        );
      },
    );
  });

  group('сценарий «Перезагрузка max_depth посреди дерева» (D46, п. 2)', () {
    test('корневая сессия создана при max_depth 3, перезагрузка ставит 1: '
        'набор ребёнка содержит agent, описание обещает ещё один уровень; '
        'новая корневая сессия — без вложенности', () async {
      final source = LayeredConfigSource();
      final rig = SubagentRig(
        source: source,
        scripts: {
          'go': [
            oneCallStep('a1', 'agent', agentArgs('kid', description: 'Kid')),
            replyStep('done'),
          ],
          'kid': [replyStep('kid done')],
          'fresh': [replyStep('ok')],
        },
      );
      await rig.open();
      source.user['subagents'] = {'max_depth': 1};
      await rig.core.runtime.reloadConfig();

      await rig.run('go');

      final kid = rig.requestsOf('kid').single;
      expect(toolNamesOf(kid), contains('agent'));
      expect(
        schemaOf(kid, 'agent').description,
        contains(
          'A subagent may start its own subagents, up to 1 more level(s) '
          'below it.',
        ),
      );
      final fresh = await rig.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await fresh.prompt([TextContent('fresh')]);
      expect(
        schemaOf(rig.requestsOf('fresh').single, 'agent').description,
        contains('Subagents you start cannot start other subagents.'),
        reason: 'max_depth 1 действует на новые корневые сессии',
      );
    });
  });
}

/// Gate, который держит каждый запрос до явного ответа теста.
final class _HoldingGate implements PermissionGate {
  final requests = <PermissionRequest>[];
  final _answers = <Completer<PermissionDecision>>[];

  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) {
    requests.add(req);
    final completer = Completer<PermissionDecision>();
    _answers.add(completer);
    return completer.future;
  }

  void answer(int index, PermissionDecision decision) =>
      _answers[index].complete(decision);
}
