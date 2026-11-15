import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../session/journal_lines.dart';
import '../support/models.dart';
import 'subagent_rig.dart';

/// Журнал субагента глубины 1 (agent-subagents «Журнал субагента и
/// прерывание», сценарий «Раскладка внука» в части глубины 1; agent-sessions
/// «Формат журнала JSONL», «Запись журнала из событий», «Дочерние журналы не
/// в списке сессий»; SUB-9, SUB-10; design.md change
/// `add-subagents-and-tasks`, D7, D36 Т4; `agent-core/17-3-subagents.md`
/// §17.3.6).
///
/// Красные до задач 2.4 и 2.7: нет `SessionStore.createChild`, поля заголовка
/// `parent` и записей `subagent`. Журналы читаются из `MemorySessionStore`
/// текстом: хранилище отдаёт его по id и для дочерних журналов.
void main() {
  List<Map<String, Object?>> lines(String text) => [
    for (final line in const LineSplitter().convert(text))
      jsonDecode(line) as Map<String, Object?>,
  ];

  /// Корень с одним ребёнком `explore` (режим типа — plan).
  Future<SubagentRig> oneChild() async {
    final rig = SubagentRig(
      scripts: {
        'go': [
          oneCallStep(
            'c1',
            'agent',
            agentArgs(
              'find the parser',
              description: 'Find parser',
              type: 'explore',
            ),
          ),
          replyStep('thanks'),
        ],
        'find the parser': [
          oneCallStep('r1', 'read', {'path': 'a.txt'}),
          replyStep('The parser is in lib/parser.dart'),
        ],
      },
    );
    await rig.open();
    await rig.run('go');
    return rig;
  }

  test('заголовок журнала ребёнка: поле parent с прямым родителем, корнем, '
      'вызовом, id, типом и глубиной 1', () async {
    final rig = await oneChild();

    final started = rig.eventsOf<SubagentStarted>().single;
    final child = lines(rig.store.textOf(started.childSessionId)!);

    expect(child.first['type'], 'session');
    expect(child.first['id'], started.childSessionId.value);
    expect(child.first['parent'], {
      'sessionId': rig.session.id.value,
      'rootSessionId': rig.session.id.value,
      'toolCallId': 'c1',
      'subagentId': started.subagentId,
      'agent': 'explore',
      'depth': 1,
    });
    expect(started.journalPath, isNotEmpty);
  });

  test(
    'первые записи журнала ребёнка: model_change, mode_change с '
    'эффективным режимом на запуске, затем user-сообщение с prompt',
    () async {
      final rig = await oneChild();

      final started = rig.eventsOf<SubagentStarted>().single;
      final child = lines(rig.store.textOf(started.childSessionId)!);

      expect(
        [for (final r in child.skip(1).take(3)) r['type']],
        ['model_change', 'mode_change', 'message'],
      );
      expect(child[2]['modeId'], 'plan', reason: 'тип explore работает в plan');
      final message = child[3]['message']! as Map<String, Object?>;
      expect(message['role'], 'user');
      expect(jsonEncode(message['content']), contains('find the parser'));
    },
  );

  test('записи subagent журнала родителя: running при получении слота и '
      'итоговая durable до результата вызова (SUB-10)', () async {
    final rig = await oneChild();

    final started = rig.eventsOf<SubagentStarted>().single;
    final root = lines(rig.rootJournal);
    final records = [
      for (final (i, r) in root.indexed)
        if (r['type'] == 'subagent') (i, r),
    ];
    expect(records, hasLength(2));
    final (runningAt, running) = records.first;
    final (finalAt, done) = records.last;
    expect(running['status'], 'running');
    expect(running['subagentId'], started.subagentId);
    expect(running['toolCallId'], 'c1');
    expect(running['agent'], 'explore');
    expect(running['description'], 'Find parser');
    expect(running['childSessionId'], started.childSessionId.value);
    expect(running['journal'], started.journalPath);
    expect(done['status'], 'completed');
    expect(done['report'], 'The parser is in lib/parser.dart');
    expect(done['toolCalls'], 1);
    expect(done['durationMs'], isA<int>());
    expect(done['usage'], isA<Map<String, Object?>>());
    // Записи — после сообщения с вызовом agent и до его результата.
    int messageIndex(String role, {String? toolCallId}) => root.indexWhere(
      (r) =>
          r['type'] == 'message' &&
          (r['message']! as Map)['role'] == role &&
          (toolCallId == null ||
              (r['message']! as Map)['toolCallId'] == toolCallId),
    );
    expect(runningAt, greaterThan(messageIndex('assistant')));
    expect(finalAt, lessThan(messageIndex('toolResult', toolCallId: 'c1')));
  });

  test('сценарий «Дочерние журналы не в списке сессий»: два ребёнка — '
      'listSessions возвращает одну сессию, open по id ребёнка — '
      'SessionNotFound', () async {
    final rig = SubagentRig(
      scripts: {
        'go': [
          multiCallStep([
            ('c1', 'agent', agentArgs('child one', description: 'One')),
            ('c2', 'agent', agentArgs('child two', description: 'Two')),
          ]),
          replyStep('thanks'),
        ],
        'child one': [replyStep('one')],
        'child two': [replyStep('two')],
      },
    );
    await rig.open();
    await rig.run('go');

    final page = await rig.core.runtime.listSessions();
    final children = [
      for (final s in rig.eventsOf<SubagentStarted>()) s.childSessionId,
    ];

    expect(children, hasLength(2));
    expect(page.items.map((s) => s.id), [rig.session.id]);
    for (final id in children) {
      await expectLater(rig.store.open(id), throwsA(isA<SessionNotFound>()));
      await expectLater(
        rig.core.runtime.loadSession(id, const SessionHostPorts()),
        throwsA(isA<SessionNotFound>()),
        reason: 'D7: session/load с id ребёнка — «не найдена» (-32002)',
      );
    }
  });

  test('события ребёнка не пишутся в журнал родителя: SubagentProgress и '
      'SubagentActivity не оставляют записей (agent-sessions, таблица '
      'событий)', () async {
    final rig = await oneChild();

    final types = [for (final r in lines(rig.rootJournal)) r['type']];

    expect(types.where((t) => t == 'subagent'), hasLength(2));
    // Текст ответа ребёнка живёт в записи subagent и в результате вызова,
    // но отдельным сообщением родителя не является.
    final assistants = [
      for (final r in lines(rig.rootJournal))
        if (r['type'] == 'message' &&
            (r['message']! as Map)['role'] == 'assistant')
          r,
    ];
    expect(assistants, hasLength(2), reason: 'вызов agent и ответ "thanks"');
  });

  // Лечение журнала с итогом `max_tokens` (D41 п. 6; S-13; §17.3.6,
  // «Прерывание»). Красный до задачи 2.20: `parseFailure` не знает
  // `max_tokens` и читает его как `error`, поэтому вылеченный результат
  // получил бы тело «Subagent failed: …» и `reason="error"`, а не то, что
  // увидела бы модель в живом ходе. Журнал собран построчно: сбой процесса
  // между итоговой записью и результатом вызова в тесте невоспроизводим.
  test('итоговая запись failure: max_tokens после open даёт тот же результат, '
      'что и живой ход', () async {
    const rootId = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');
    final crashed = journal([
      header(cwd: '/proj', id: rootId.value),
      modelChange('m1', null),
      user('u1', 'm1', text: 'run it'),
      answer(
        'a1',
        'u1',
        calls: [
          ('c1', 'agent', {'description': 'Review it', 'prompt': 'task a'}),
        ],
      ),
      jsonEncode({
        'type': 'subagent',
        'id': 's1',
        'parentId': 'a1',
        'timestamp': at,
        'subagentId': 'sub_aaaaaaaa',
        'toolCallId': 'c1',
        'agent': 'review',
        'description': 'Review it',
        'status': 'failed',
        'failure': 'max_tokens',
        'report': '',
        'toolCalls': 2,
        'durationMs': 1500,
      }),
    ]);
    final store = MemorySessionStore()..putText(rootId, crashed);
    final rig = SubagentRig(
      store: store,
      scripts: {
        'run it': [replyStep('Continuing.')],
      },
    );

    await rig.load(rootId);
    await rig.run('continue');

    final request = rig.requestsOf('run it').single;
    final text = resultText(request, 'c1');
    expect(text, contains('status="failed"'));
    expect(text, contains('reason="max_tokens"'));
    expect(
      text,
      contains(
        'Subagent stopped: it hit the output token limit before writing a '
        'report.',
      ),
    );
    expect(resultIsError(request, 'c1'), isTrue);
    expect(rig.requests.keys, ['run it'], reason: 'ребёнок не перезапущен');
  });

  // Задача 3.6 (design.md, D43 п. 5; §17.3.6 «Атрибут `truncated` при
  // лечении»; agent-subagents «Усечённый отчёт после сбоя»). Журнал собран
  // построчно: сбой между итоговой записью и результатом вызова в тесте
  // невоспроизводим. Красные до кода: поле `truncated` записью не читается, и
  // вылеченная обёртка теряет атрибут, который есть у живого хода.
  Future<String> healedWrapper({required Map<String, Object?> extra}) async {
    const rootId = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0D');
    final crashed = journal([
      header(cwd: '/proj', id: rootId.value),
      modelChange('m1', null),
      user('u1', 'm1', text: 'run it'),
      answer(
        'a1',
        'u1',
        calls: [
          ('c1', 'agent', {'description': 'Review it', 'prompt': 'task a'}),
        ],
      ),
      jsonEncode({
        'type': 'subagent',
        'id': 's1',
        'parentId': 'a1',
        'timestamp': at,
        'subagentId': 'sub_aaaaaaaa',
        'toolCallId': 'c1',
        'agent': 'review',
        'description': 'Review it',
        'status': 'completed',
        'report':
            'line 0\n[report truncated: 10 of 99 bytes shown; the full '
            'report is in the subagent journal]',
        'toolCalls': 2,
        'durationMs': 1500,
        ...extra,
      }),
    ]);
    final store = MemorySessionStore()..putText(rootId, crashed);
    final rig = SubagentRig(
      store: store,
      scripts: {
        'run it': [replyStep('Continuing.')],
      },
    );

    await rig.load(rootId);
    await rig.run('continue');

    return resultText(rig.requestsOf('run it').single, 'c1');
  }

  test('усечённый отчёт после сбоя: запись с truncated: true даёт обёртку '
      'с truncated="true", как живой ход', () async {
    final text = await healedWrapper(extra: {'truncated': true});

    expect(text, contains('status="completed"'));
    expect(text, contains('truncated="true"'));
  });

  test('запись без поля truncated (старый журнал) читается как не '
      'усечённая: обёртка без атрибута', () async {
    final text = await healedWrapper(extra: const {});

    expect(text, contains('status="completed"'));
    expect(text, isNot(contains('truncated=')));
  });

  test('живой ход: итоговая запись усечённого report_max_bytes отчёта '
      'несёт truncated: true, неусечённого — без поля', () async {
    Future<Map<String, Object?>> finalRecord(String reply) async {
      final rig = SubagentRig(
        config: CoreConfig(
          defaultModel: subagentTestModel,
          subagents: const SubagentsConfig(reportMaxBytes: 1024),
        ),
        scripts: {
          'go': [
            oneCallStep('c1', 'agent', agentArgs('write the report')),
            replyStep('done'),
          ],
          'write the report': [replyStep(reply)],
        },
      );
      await rig.open();
      await rig.run('go');
      return lines(rig.rootJournal).lastWhere((r) => r['type'] == 'subagent');
    }

    final cut = await finalRecord(
      [for (var i = 0; i < 400; i++) 'line $i of the report'].join('\n'),
    );
    final whole = await finalRecord('short report');

    expect(cut['truncated'], isTrue);
    expect(whole.containsKey('truncated'), isFalse);
  });

  // Итерация 4, задача 4.1 (agent-subagents «Журнал субагента и прерывание»,
  // сценарии «Раскладка внука», «Рекурсивное лечение», «Журнал потомка не
  // открывается»; SUB-9, S-13; design.md change `add-subagents-and-tasks`,
  // D7, D45 Т1, Т7, D46 п. 5; `agent-core/17-3-subagents.md` §17.3.6).
  group('журналы потомков глубины 2 и больше', () {
    const rootId = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');
    const kidId = SessionId('01JB8Q3A1D2E3F4G5H6J7K8M9A');
    const grandId = SessionId('01JB8Q3A1D2E3F4G5H6J7K8M9B');
    const kidSubagent = 'sub_aaaaaaaa';
    const grandSubagent = 'sub_bbbbbbbb';

    SessionHeader headerOf(
      SessionId id,
      SessionId parent,
      String callId,
      String subagentId,
      int depth,
    ) => SessionHeader(
      id: id,
      cwd: '/proj',
      created: DateTime.utc(2026, 10, 21, 8),
      agent: const AgentInfo(name: 'codelab-agent', version: '0.1.0'),
      parent: SessionParent(
        sessionId: parent,
        rootSessionId: rootId,
        toolCallId: callId,
        subagentId: subagentId,
        agent: 'general',
        depth: depth,
      ),
    );

    String runningRecord(
      String id,
      String? parent, {
      required String subagentId,
      required String callId,
      required SessionId childId,
      required String journal,
    }) => jsonEncode({
      'type': 'subagent',
      'id': id,
      'parentId': parent,
      'timestamp': at,
      'subagentId': subagentId,
      'toolCallId': callId,
      'agent': 'general',
      'description': 'Job $subagentId',
      'childSessionId': childId.value,
      'journal': journal,
      'status': 'running',
    });

    Future<void> putLines(
      MemorySessionStore store,
      SessionId id,
      List<String> records,
    ) async {
      for (final line in records) {
        await store.append(
          id,
          SessionRecord.fromJson(jsonDecode(line) as Map<String, Object?>),
        );
      }
    }

    List<Map<String, Object?>> results(String text) => [
      for (final r in lines(text))
        if (r['type'] == 'message' &&
            (r['message']! as Map)['role'] == 'toolResult')
          r,
    ];

    /// Журнал после сбоя: ребёнок ждёт внука, внук исполняет `read`.
    Future<MemorySessionStore> crashedTree({
      required bool withGrandchild,
    }) async {
      final store = MemorySessionStore();
      final kidPath = await store.createChild(
        headerOf(kidId, rootId, 'c1', kidSubagent, 1),
      );
      if (withGrandchild) {
        final grandPath = await store.createChild(
          headerOf(grandId, kidId, 'g1', grandSubagent, 2),
        );
        await putLines(store, kidId, [
          user('ku1', null, text: 'kid'),
          answer(
            'ka1',
            'ku1',
            calls: [
              ('g1', 'agent', {'description': 'Grand job', 'prompt': 'grand'}),
            ],
          ),
          runningRecord(
            'ks1',
            'ka1',
            subagentId: grandSubagent,
            callId: 'g1',
            childId: grandId,
            journal: grandPath,
          ),
        ]);
        await putLines(store, grandId, [
          user('gu1', null, text: 'grand'),
          answer(
            'ga1',
            'gu1',
            calls: [
              ('r1', 'read', {'path': 'a.txt'}),
            ],
          ),
        ]);
      } else {
        await putLines(store, kidId, [
          user('ku1', null, text: 'kid'),
          answer(
            'ka1',
            'ku1',
            calls: [
              ('r0', 'read', {'path': 'a.txt'}),
            ],
          ),
        ]);
      }
      store.putText(
        rootId,
        journal([
          header(cwd: '/proj', id: rootId.value),
          modelChange('m1', null),
          user('u1', 'm1', text: 'run it'),
          answer(
            'a1',
            'u1',
            calls: [
              ('c1', 'agent', {'description': 'Kid job', 'prompt': 'kid'}),
            ],
          ),
          runningRecord(
            's1',
            'a1',
            subagentId: kidSubagent,
            callId: 'c1',
            childId: kidId,
            journal: kidPath,
          ),
        ]),
      );
      return store;
    }

    test('характеризующий, зелёный сразу: раскладка журнала внука плоская '
        '(D45 Т1) — адрес в subagents/ корня, глубина пути не удлиняет, '
        'open и list дочерних журналов не видят', () async {
      final store = MemorySessionStore();

      final kid = await store.createChild(
        headerOf(kidId, rootId, 'c1', kidSubagent, 1),
      );
      final grand = await store.createChild(
        headerOf(grandId, kidId, 'g1', grandSubagent, 2),
      );

      expect(kid, 'subagents/${rootId.value}/${kidId.value}.jsonl');
      expect(grand, 'subagents/${rootId.value}/${grandId.value}.jsonl');
      expect((await store.list()).items, isEmpty);
      await expectLater(store.open(grandId), throwsA(isA<SessionNotFound>()));
    });

    test('сценарий «Раскладка внука»: журнал внука — parent.sessionId '
        'ребёнка и depth 2, запись subagent внука — в журнале ребёнка, а не '
        'корня', () async {
      final rig = SubagentRig(
        scripts: {
          'go': [
            oneCallStep('c1', 'agent', agentArgs('kid job')),
            replyStep('done'),
          ],
          'kid job': [
            oneCallStep('g1', 'agent', agentArgs('grand job')),
            replyStep('kid done'),
          ],
          'grand job': [replyStep('grand done')],
        },
      );
      await rig.open();

      await rig.run('go');

      final kid = rig.eventsOf<SubagentStarted>().single;
      expect(allStarted(rig), hasLength(2), reason: 'ребёнок и внук');
      final grand = allStarted(rig).last;
      final header = lines(rig.store.textOf(grand.childSessionId)!).first;
      expect(header['parent'], {
        'sessionId': kid.childSessionId.value,
        'rootSessionId': rig.session.id.value,
        'toolCallId': 'g1',
        'subagentId': grand.subagentId,
        'agent': 'general',
        'depth': 2,
      });
      expect(
        grand.journalPath,
        startsWith('subagents/${rig.session.id.value}/'),
        reason: 'журнал внука лежит в subagents/ корня, плоско',
      );
      List<Object?> statuses(String text) => [
        for (final r in lines(text))
          if (r['type'] == 'subagent' && r['subagentId'] == grand.subagentId)
            r['status'],
      ];
      expect(statuses(rig.store.textOf(kid.childSessionId)!), [
        'running',
        'completed',
      ]);
      expect(statuses(rig.rootJournal), isEmpty);
    });

    test('сценарий «Рекурсивное лечение»: убит ребёнок, ждущий внука, '
        'внук исполняет read — после open результаты interrupted в журналах '
        'корня, ребёнка и внука, запись внука failed/interrupted; никто не '
        'перезапущен', () async {
      final store = await crashedTree(withGrandchild: true);
      final rig = SubagentRig(store: store, scripts: const {});

      await rig.load(rootId);

      final root = store.textOf(rootId)!;
      expect(results(root).single['outcome'], 'interrupted');
      final kid = store.textOf(kidId)!;
      expect(
        [
          for (final r in results(kid))
            ((r['message']! as Map)['toolCallId'], r['outcome']),
        ],
        [('g1', 'interrupted')],
      );
      final healed = lines(kid).where((r) => r['type'] == 'subagent').last;
      expect(healed['subagentId'], grandSubagent);
      expect(healed['status'], 'failed');
      expect(healed['failure'], 'interrupted');
      expect(
        [
          for (final r in results(store.textOf(grandId)!))
            ((r['message']! as Map)['toolCallId'], r['outcome']),
        ],
        [('r1', 'interrupted')],
      );
      expect(rig.requests, isEmpty, reason: 'ни один потомок не запущен');
    });

    test('рекурсивное лечение затрагивает и журнал ребёнка глубины 1: его '
        'прерванный вызов получает interrupted (D45 Т7)', () async {
      final store = await crashedTree(withGrandchild: false);
      final rig = SubagentRig(store: store, scripts: const {});

      await rig.load(rootId);

      expect(
        [
          for (final r in results(store.textOf(kidId)!))
            ((r['message']! as Map)['toolCallId'], r['outcome']),
        ],
        [('r0', 'interrupted')],
      );
      final healed = lines(
        store.textOf(rootId)!,
      ).where((r) => r['type'] == 'subagent').last;
      expect(healed['status'], 'failed');
      expect(healed['failure'], 'interrupted');
    });

    test('повторное открытие вылеченного дерева ничего не дописывает: '
        'лечение идемпотентно', () async {
      final store = await crashedTree(withGrandchild: true);
      await SubagentRig(store: store, scripts: const {}).load(rootId);
      expect(
        results(store.textOf(grandId)!),
        isNotEmpty,
        reason: 'первое открытие вылечило журнал внука',
      );
      final texts = {
        for (final id in [rootId, kidId, grandId]) id: store.textOf(id),
      };

      await SubagentRig(store: store, scripts: const {}).load(rootId);

      for (final id in [rootId, kidId, grandId]) {
        expect(store.textOf(id), texts[id], reason: id.value);
      }
    });

    test('сценарий «Журнал потомка не открывается»: журнал ребёнка в статусе '
        'running удалён — корень открывается, вызов agent interrupted, лог '
        'subagent.heal_failed с subagent_id без пути (D46, п. 5)', () async {
      final store = MemorySessionStore()
        ..putText(
          rootId,
          journal([
            header(cwd: '/proj', id: rootId.value),
            modelChange('m1', null),
            user('u1', 'm1', text: 'run it'),
            answer(
              'a1',
              'u1',
              calls: [
                ('c1', 'agent', {'description': 'Kid job', 'prompt': 'kid'}),
              ],
            ),
            runningRecord(
              's1',
              'a1',
              subagentId: kidSubagent,
              callId: 'c1',
              childId: kidId,
              journal: 'subagents/${rootId.value}/${kidId.value}.jsonl',
            ),
          ]),
        );
      final rig = SubagentRig(store: store, scripts: const {});

      await rig.load(rootId);

      final root = store.textOf(rootId)!;
      expect(results(root).single['outcome'], 'interrupted');
      final healed = lines(root).where((r) => r['type'] == 'subagent').last;
      expect(healed['status'], 'failed');
      expect(healed['failure'], 'interrupted');
      final failed = rig.logger.eventsOf('subagent.heal_failed').single;
      expect(failed.fields['subagent_id'], kidSubagent);
      expect(failed.fields['session_id'], rootId.value);
      expect(failed.fields['error_class'], isA<String>());
      expect(
        failed.fields.values.join(' '),
        isNot(contains('.jsonl')),
        reason: 'в логе нет пути журнала',
      );
    });
  });
}
