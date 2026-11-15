import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../session/journal_lines.dart';
import 'subagent_rig.dart';

/// `AgentSession.replayTree()`: реплей дерева субагентов (agent-acp-server
/// «Реплей дерева»; agent-subagents, §5.6, §8.3, §17.3.3; design.md change
/// `add-subagents-and-tasks`, D47 Т5, Т6, задача 5.1).
///
/// Почему отдельный метод: `replay()` синхронный и прежний (D1) — им
/// пользуется реплей клиенту без согласия `subagentToolCalls`; `replayTree()`
/// добавляет `SubagentActivity` потомков, прочитанные из их журналов через
/// `SessionStore.openChildReadOnly`.
///
/// Охраняют, что `replayTree()` отдаёт `SubagentActivity` потомков из их
/// журналов (D47 Т5, Т6), а `replay()` остаётся прежним.
void main() {
  const rootId = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');
  const kidId = SessionId('01JB8Q3A1D2E3F4G5H6J7K8M9A');
  const kidSubagent = 'sub_aaaaaaaa';

  /// Живое дерево: корень → ребёнок (`read`, внук) → внук (`ls`).
  Future<SubagentRig> liveTree() async {
    final rig = SubagentRig(
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('kid job')),
          replyStep('done'),
        ],
        'kid job': [
          oneCallStep('r1', 'read', {'path': 'a.txt'}),
          oneCallStep('g1', 'agent', agentArgs('grand job')),
          replyStep('kid done'),
        ],
        'grand job': [
          oneCallStep('x1', 'ls', {'path': '.'}),
          replyStep('grand done'),
        ],
      },
    );
    await rig.open();
    await rig.run('go');
    return rig;
  }

  /// Сигнатура вызова потомка: адрес и исход, без объектов событий.
  String signature(SubagentActivity a) => switch (a.event) {
    ToolCallStarted(:final toolCallId) =>
      'started ${a.parentToolCallId} ${a.path.join(',')} ${a.depth} '
          '$toolCallId',
    ToolCallFinished(:final toolCallId) =>
      'finished ${a.parentToolCallId} ${a.path.join(',')} ${a.depth} '
          '$toolCallId',
    _ => 'other',
  };

  group('дерево из живого хода', () {
    test('SubagentActivity ребёнка и внука идут сразу после '
        'ToolCallFinished(agent) с адресом, как вживую', () async {
      final rig = await liveTree();
      final kid = rig.eventsOf<SubagentStarted>().single.subagentId;
      final grand = allStarted(rig).last.subagentId;

      final events = await rig.session.replayTree();

      final finishedAt = events.indexWhere(
        (e) => e is ToolCallFinished && e.toolCallId == 'c1',
      );
      expect(finishedAt, isNonNegative);
      expect(
        events[finishedAt + 1],
        isA<SubagentActivity>(),
        reason: 'потомки сразу после результата вызова agent',
      );
      final activities = events.whereType<SubagentActivity>().toList();
      final firstAt = events.indexWhere((e) => e is SubagentActivity);
      final lastAt = events.lastIndexWhere((e) => e is SubagentActivity);
      expect(lastAt - firstAt + 1, activities.length, reason: 'одним блоком');
      expect(
        activities.every((a) => a.event is! SubagentActivity),
        isTrue,
        reason: 'обёртка плоская (D6)',
      );

      final kids = activities.where((a) => a.depth == 1).toList();
      final grands = activities.where((a) => a.depth == 2).toList();
      expect(kids, isNotEmpty);
      expect(grands, isNotEmpty);
      expect(kids.every((a) => a.subagentId == kid), isTrue);
      expect(kids.every((a) => a.parentToolCallId == 'c1'), isTrue);
      expect(kids.every((a) => a.path.isEmpty), isTrue);
      expect(grands.every((a) => a.subagentId == grand), isTrue);
      expect(grands.every((a) => a.parentToolCallId == 'g1'), isTrue);
      expect(grands.every((a) => a.path.single == kid), isTrue);
      expect(
        [
          for (final a in kids)
            if (a.event case ToolCallStarted(:final toolCallId)) toolCallId,
        ],
        ['r1', 'g1'],
      );
      expect(
        [
          for (final a in grands)
            if (a.event case ToolCallStarted(:final toolCallId)) toolCallId,
        ],
        ['x1'],
      );
      // События внука — после результата вызова `g1` ребёнка.
      final kidGrandFinished = events.indexWhere(
        (e) =>
            e is SubagentActivity &&
            e.depth == 1 &&
            e.event is ToolCallFinished &&
            (e.event as ToolCallFinished).toolCallId == 'g1',
      );
      expect(kidGrandFinished, lessThan(events.indexOf(grands.first)));
    });

    test('вызовы потомков те же, что приходили вживую: адрес и id совпадают '
        '(как у SubagentActivity хода)', () async {
      final rig = await liveTree();
      final live = [
        for (final a in rig.eventsOf<SubagentActivity>()) signature(a),
      ].where((s) => s != 'other').toList()..sort();

      final replayed = [
        for (final a
            in (await rig.session.replayTree()).whereType<SubagentActivity>())
          signature(a),
      ].where((s) => s != 'other').toList()..sort();

      expect(replayed, live);
    });

    test('replay() не меняется: потомков в нём нет, а replayTree без '
        'SubagentActivity совпадает с ним', () async {
      final rig = await liveTree();

      final plain = rig.session.replay().toList();
      final tree = await rig.session.replayTree();

      expect(plain.whereType<SubagentActivity>(), isEmpty);
      expect(
        [
          for (final e in tree)
            if (e is! SubagentActivity) e.runtimeType,
        ],
        [for (final e in plain) e.runtimeType],
      );
    });

    test('реплей читает журналы без записи: тексты корня, ребёнка и внука '
        'не меняются', () async {
      final rig = await liveTree();
      final ids = [
        rig.session.id,
        for (final s in allStarted(rig)) s.childSessionId,
      ];
      final before = {for (final id in ids) id: rig.store.textOf(id)};

      await rig.session.replayTree();

      for (final id in ids) {
        expect(rig.store.textOf(id), before[id], reason: id.value);
      }
    });
  });

  group('журнал из хранилища', () {
    SessionHeader childHeader(SessionId id, String call, String subagent) =>
        SessionHeader(
          id: id,
          cwd: '/proj',
          created: DateTime.utc(2026, 10, 21, 8),
          agent: const AgentInfo(name: 'codelab-agent', version: '0.1.0'),
          parent: SessionParent(
            sessionId: rootId,
            rootSessionId: rootId,
            toolCallId: call,
            subagentId: subagent,
            agent: 'general',
            depth: 1,
          ),
        );

    String subagentRecord(
      String id,
      String? parent, {
      required String call,
      required String subagent,
      required String status,
      String? journal,
      SessionId? childId,
    }) => jsonEncode({
      'type': 'subagent',
      'id': id,
      'parentId': parent,
      'timestamp': at,
      'subagentId': subagent,
      'toolCallId': call,
      'agent': 'general',
      'description': 'Job $subagent',
      'childSessionId': ?childId?.value,
      'journal': ?journal,
      'status': status,
      if (status == 'completed') ...{
        'report': 'ok',
        'usage': {'input': 1, 'output': 1},
        'toolCalls': 1,
        'durationMs': 10,
      },
    });

    Future<void> put(
      MemorySessionStore store,
      SessionId id,
      List<String> lines,
    ) async {
      for (final line in lines) {
        await store.append(
          id,
          SessionRecord.fromJson(jsonDecode(line) as Map<String, Object?>),
        );
      }
    }

    /// Корень с вызовами `agent` [calls] (`id → запись subagent`); результат
    /// каждого вызова — `outcome`.
    void putRoot(
      MemorySessionStore store,
      List<({String call, String record})> calls,
    ) {
      final tail = <String>[];
      for (final (i, c) in calls.indexed) {
        tail
          ..add(c.record)
          ..add(toolResult('r$i', 's$i', callId: c.call, tool: 'agent'));
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
              for (final c in calls)
                (c.call, 'agent', {'description': 'Job', 'prompt': 'kid'}),
            ],
          ),
          ...tail,
        ]),
      );
    }

    test('запись subagent без journal (потомок отменён в очереди) потомков '
        'не даёт и лога сбоя не пишет', () async {
      final store = MemorySessionStore();
      putRoot(store, [
        (
          call: 'c1',
          record: subagentRecord(
            's0',
            'a1',
            call: 'c1',
            subagent: kidSubagent,
            status: 'cancelled',
          ),
        ),
      ]);
      final rig = SubagentRig(store: store, scripts: const {});
      await rig.load(rootId);

      final events = await rig.session.replayTree();

      expect(events.whereType<SubagentActivity>(), isEmpty);
      expect(events.whereType<ToolCallFinished>().map((e) => e.toolCallId), [
        'c1',
      ]);
      expect(rig.logger.eventsOf('subagent.replay_failed'), isEmpty);
    });

    test('вызов без результата в журнале потомка, пережившего cancel_grace, '
        'проигрывается cancelled (D47 Т6)', () async {
      final store = MemorySessionStore();
      final address = await store.createChild(
        childHeader(kidId, 'c1', kidSubagent),
      );
      await put(store, kidId, [
        user('ku1', null, text: 'kid'),
        answer(
          'ka1',
          'ku1',
          calls: [
            ('r1', 'read', {'path': 'a.txt'}),
          ],
        ),
      ]);
      putRoot(store, [
        (
          call: 'c1',
          record: subagentRecord(
            's0',
            'a1',
            call: 'c1',
            subagent: kidSubagent,
            status: 'cancelled',
            journal: address,
            childId: kidId,
          ),
        ),
      ]);
      final rig = SubagentRig(store: store, scripts: const {});
      await rig.load(rootId);

      final events = await rig.session.replayTree();

      final inner = [
        for (final a in events.whereType<SubagentActivity>()) a.event,
      ];
      final started = inner.whereType<ToolCallStarted>().single;
      final finished = inner.whereType<ToolCallFinished>().single;
      expect(started.toolCallId, 'r1');
      expect(finished.toolCallId, 'r1');
      expect(finished.outcome, ToolOutcome.cancelled);
      expect(inner.indexOf(started), lessThan(inner.indexOf(finished)));
    });

    test('сценарий «Журнал потомка не открывается»: лог subagent.replay_failed '
        'с безопасными полями, реплей идёт, вызов с рабочим журналом '
        'сохраняет потомков', () async {
      final store = MemorySessionStore();
      final okAddress = await store.createChild(
        childHeader(kidId, 'c2', 'sub_bbbbbbbb'),
      );
      await put(store, kidId, [
        user('ku1', null, text: 'kid'),
        answer(
          'ka1',
          'ku1',
          calls: [
            ('r1', 'read', {'path': 'a.txt'}),
          ],
        ),
        toolResult('kr1', 'ka1', callId: 'r1'),
      ]);
      putRoot(store, [
        (
          call: 'c1',
          record: subagentRecord(
            's0',
            'a1',
            call: 'c1',
            subagent: kidSubagent,
            status: 'completed',
            journal: 'subagents/${rootId.value}/MISSING.jsonl',
            childId: const SessionId('01JB8Q3A1D2E3F4G5H6J7K8M9Z'),
          ),
        ),
        (
          call: 'c2',
          record: subagentRecord(
            's1',
            'r0',
            call: 'c2',
            subagent: 'sub_bbbbbbbb',
            status: 'completed',
            journal: okAddress,
            childId: kidId,
          ),
        ),
      ]);
      final rig = SubagentRig(store: store, scripts: const {});
      await rig.load(rootId);

      final events = await rig.session.replayTree();

      expect(
        events.whereType<ToolCallFinished>().map((e) => e.toolCallId),
        containsAll(['c1', 'c2']),
        reason: 'session/load не падает, корневые события на месте',
      );
      final activities = events.whereType<SubagentActivity>().toList();
      expect(activities, isNotEmpty);
      expect(
        activities.every((a) => a.parentToolCallId == 'c2'),
        isTrue,
        reason: 'потомков сломанного вызова c1 нет, вызова c2 — есть',
      );
      final failed = rig.logger.eventsOf('subagent.replay_failed').single;
      expect(failed.fields['subagent_id'], kidSubagent);
      expect(failed.fields['session_id'], rootId.value);
      expect(failed.fields['error_class'], isA<String>());
      expect(failed.error, isNull, reason: 'в тексте ошибки может быть путь');
      expect(
        failed.fields.values.join(' '),
        isNot(contains('.jsonl')),
        reason: 'в логе нет пути журнала',
      );
    });

    test('цикл в ссылках на журналы (ребёнок ссылается на свой журнал): '
        'обход завершается, журнал читается один раз', () async {
      final store = MemorySessionStore();
      final address = await store.createChild(
        childHeader(kidId, 'c1', kidSubagent),
      );
      await put(store, kidId, [
        user('ku1', null, text: 'kid'),
        answer(
          'ka1',
          'ku1',
          calls: [
            ('g1', 'agent', {'description': 'Loop', 'prompt': 'x'}),
          ],
        ),
        subagentRecord(
          'ks1',
          'ka1',
          call: 'g1',
          subagent: 'sub_cccccccc',
          status: 'completed',
          journal: address,
          childId: kidId,
        ),
        toolResult('kr1', 'ks1', callId: 'g1', tool: 'agent'),
      ]);
      putRoot(store, [
        (
          call: 'c1',
          record: subagentRecord(
            's0',
            'a1',
            call: 'c1',
            subagent: kidSubagent,
            status: 'completed',
            journal: address,
            childId: kidId,
          ),
        ),
      ]);
      final rig = SubagentRig(store: store, scripts: const {});
      await rig.load(rootId);

      final events = await rig.session.replayTree();

      final activities = events.whereType<SubagentActivity>().toList();
      expect(activities, isNotEmpty);
      expect(
        activities.every((a) => a.depth == 1),
        isTrue,
        reason: 'повторный заход в уже прочитанный журнал пропущен',
      );
    });
  });
}
