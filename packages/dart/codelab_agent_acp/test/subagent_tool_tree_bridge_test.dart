import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_acp/src/session_bridge.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/client_channel.dart';
import 'support/server_harness.dart' show scriptedModel;

/// Состояние моста по вызовам потомков и реплей дерева (задача 5.1 `[protocol]`
/// change `add-subagents-and-tasks`, итерация 5; agent-acp-server «Шаги
/// потомков деревом»; design.md D21, D47 Т2, Т3, Т4, Т6, D48 п. 1).
///
/// Почему не через сервер: закрытие висящих вызовов при отмене, поздние кадры
/// и порядок реплея зависят от порядка событий ядра, который на настоящем
/// ядре не удержать (ребёнок завершается сам). Фальшивая сессия выпускает
/// события явно, как `session_bridge_echo_test.dart`.
///
/// Тесты «без согласия» охраняют SUB-12 (кадров потомков нет), остальные —
/// цепочки потомков в `_announced`/`terminalShown` и реплей дерева через
/// `replayInto` (читает `replayTree()`); фальшивая сессия здесь отдаёт
/// `replayTree()` сама.
void main() {
  const root = SessionId('sess_fake');

  late _FakeSession session;
  late List<acp.SessionUpdate> sent;
  late ClientChannel channel;

  /// Мост клиента с согласием `subagentToolCalls` (по умолчанию) или без.
  Future<SessionBridge> open({bool consent = true}) async {
    channel = await ClientChannel.open(
      capabilities: acp.ClientCapabilities(
        fs: const acp.FileSystemCapabilities(
          readTextFile: true,
          writeTextFile: true,
        ),
        terminal: true,
        meta: consent
            ? {
                'codelab': {
                  'subagentToolCalls': {'version': 1},
                },
              }
            : null,
      ),
    );
    session = _FakeSession();
    sent = [];
    return SessionBridge(
      owner: Object(),
      usageSink: (_) {},
      sink: (n) => sent.add(n.update),
      link: channel.link,
      clock: channel.clock,
      logger: channel.logger,
    )..attach(session);
  }

  tearDown(() => session.dispose());

  Future<void> pump() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Вызов в обёртке потомка: [subagent] — владелец события, [parent] — сырой
  /// id вызова `agent` в сессии владельца, [path] — предки.
  SubagentActivity act(
    AgentEvent event, {
    String subagent = 'sub_c',
    String parent = 'call_1',
    int depth = 1,
    List<String> path = const [],
  }) => SubagentActivity(
    root,
    subagentId: subagent,
    parentToolCallId: parent,
    path: path,
    depth: depth,
    event: event,
  );

  ToolCallStarted started(
    String id, {
    String tool = 'exec',
    ToolKind kind = ToolKind.execute,
    SubagentCallRef? subagent,
  }) => ToolCallStarted(
    root,
    toolCallId: id,
    tool: tool,
    kind: kind,
    title: tool == 'agent' ? 'Subagent explore: x' : 'Run $tool',
    input: const {'command': 'ls'},
    subagent: subagent,
  );

  ToolCallFinished finished(
    String id, {
    ToolOutcome outcome = ToolOutcome.completed,
  }) => ToolCallFinished(
    root,
    toolCallId: id,
    outcome: outcome,
    content: const [TextContent('done')],
  );

  /// `session/update` кадры в виде `<вид> <toolCallId> <status> [outcome]`.
  List<String> labels() => [
    for (final update in sent)
      if (update.toJson() case {
        'sessionUpdate': final String kind,
        'toolCallId': final String id,
      } when kind.startsWith('tool_call'))
        '$kind $id ${update.toJson()['status']}'
            '${_outcome(update.toJson())}',
  ];

  /// Корень: вызов `agent` `call_1` ребёнка `sub_c`, внутри — `agent`
  /// `call_2` внука `sub_g` и вызовы потомков, как в фикстуре
  /// `acp/prompt-subagent-tool-tree`.
  void startTree() {
    session
      ..emit(
        started(
          'call_1',
          tool: 'agent',
          kind: ToolKind.think,
          subagent: SubagentCallRef(id: 'sub_c', type: 'general'),
        ),
      )
      ..emit(act(started('call_1', tool: 'read', kind: ToolKind.read)))
      ..emit(
        act(
          started(
            'call_2',
            tool: 'agent',
            kind: ToolKind.think,
            subagent: SubagentCallRef(id: 'sub_g', type: 'explore'),
          ),
        ),
      )
      ..emit(
        act(
          started('call_1', tool: 'ls', kind: ToolKind.search),
          subagent: 'sub_g',
          parent: 'call_2',
          depth: 2,
          path: const ['sub_c'],
        ),
      );
  }

  group('with the consent', () {
    // «Вызовы ребёнка и внука», D47 Т2: цепочку внука мост строит из адреса
    // события и префикса ребёнка, строки не разбирает.
    test('child and grandchild calls get chains and parents', () async {
      final bridge = await open();
      expect(bridge, isNotNull);

      startTree();
      await pump();

      expect(labels(), [
        'tool_call call_1 pending',
        'tool_call call_1/call_1 pending',
        'tool_call call_1/call_2 pending',
        'tool_call call_1/call_2/call_1 pending',
      ]);
      Map<String, Object?> codelab(int index) =>
          ((sent[index].toJson()['_meta']! as Map)['codelab']! as Map)
              .cast<String, Object?>();
      expect(codelab(1), {'parentToolCallId': 'call_1'});
      expect(codelab(2)['parentToolCallId'], 'call_1');
      expect(codelab(2)['subagent'], {'id': 'sub_g', 'type': 'explore'});
      expect(codelab(3), {'parentToolCallId': 'call_1/call_2'});
    });

    // D47 Т3: итог внука приходит `SubagentFinished` в обёртке ребёнка;
    // финальное обновление вложенного `agent` несёт `summary` по цепочке.
    test('the final update of a nested agent carries the summary of the '
        'grandchild', () async {
      await open();
      startTree();
      session
        ..emit(
          act(
            SubagentFinished(
              root,
              subagentId: 'sub_g',
              parentToolCallId: 'call_2',
              status: SubagentState.completed,
              usage: const Usage(input: 1600, output: 150),
              toolCalls: 1,
              duration: const Duration(seconds: 48),
              report: 'Tests listed.',
            ),
          ),
        )
        ..emit(act(finished('call_2')));
      await pump();

      final last = sent.last.toJson();
      expect(last['toolCallId'], 'call_1/call_2');
      expect(last['status'], 'completed');
      expect(((last['_meta']! as Map)['codelab']! as Map)['subagent'], {
        'id': 'sub_g',
        'summary': {
          'toolCalls': 1,
          'tokens': {'input': 1600, 'output': 150},
          'durationMs': 48000,
        },
      });
    });

    // «Висящие вызовы при отмене», D21, D47 Т3: вызов `agent` стал
    // терминальным, а exec ребёнка не завершён (ребёнок не успел за
    // `cancel_grace`). До итога `agent` клиент получает `failed` с
    // `outcome: cancelled` для каждого открытого вызова поддерева —
    // рекурсивно, включая вызовы внука.
    test('a terminal agent call closes every open call of its subtree '
        'before its own update', () async {
      await open();
      startTree();
      session
        ..emit(act(started('call_3')))
        ..emit(finished('call_1', outcome: ToolOutcome.cancelled));
      await pump();

      // Четыре открытых вызова поддерева: read ребёнка, agent ребёнка→внука,
      // ls внука и exec `call_3` ребёнка, затем итог самого `agent`.
      final closing = labels().skip(5).toList();
      expect(closing, hasLength(5));
      expect(
        closing.take(4),
        unorderedEquals([
          'tool_call_update call_1/call_1 failed cancelled',
          'tool_call_update call_1/call_2 failed cancelled',
          'tool_call_update call_1/call_2/call_1 failed cancelled',
          'tool_call_update call_1/call_3 failed cancelled',
        ]),
      );
      expect(closing.last, 'tool_call_update call_1 failed cancelled');
    });

    // D52 п. 1: клиент уже получил строку прогресса вложенного `agent`
    // (`ToolCallProgress` ребёнка доходит до него как вызов цепочки), поэтому
    // кадр закрытия вложенного `agent` несёт `content: []`, иначе строка
    // осталась бы в `running`. Кадры прочих вызовов поддерева — без `content`.
    test('closing a nested agent call after its progress line carries '
        'content: []', () async {
      await open();
      startTree();
      session
        ..emit(
          act(
            ToolCallProgress(
              root,
              toolCallId: 'call_2',
              content: const [ToolCallBlock(TextContent('explore · 1 tool'))],
            ),
          ),
        )
        ..emit(finished('call_1', outcome: ToolOutcome.cancelled));
      await pump();

      Map<String, Object?> frame(String id) => sent
          .map((u) => u.toJson())
          .lastWhere((j) => j['toolCallId'] == id && j['status'] == 'failed');
      expect(frame('call_1/call_2'), containsPair('content', isEmpty));
      expect(frame('call_1/call_1'), isNot(contains('content')));
      expect(frame('call_1/call_2/call_1'), isNot(contains('content')));
    });

    // D47 Т3: закрытие срабатывает на `ToolCallFinished` любого `agent`, в
    // том числе вложенного: внук ещё держит `exec`, а вызов `agent` ребёнка
    // уже завершён.
    test('a nested agent finishing closes the calls of its own subtree '
        'only', () async {
      await open();
      startTree();
      session.emit(act(finished('call_2')));
      await pump();

      final after = labels().skip(4).toList();
      expect(after, [
        'tool_call_update call_1/call_2/call_1 failed cancelled',
        'tool_call_update call_1/call_2 completed',
      ]);
      // Вызов `read` ребёнка (не из поддерева внука) не тронут.
      expect(
        labels(),
        isNot(contains('tool_call_update call_1/call_1 failed cancelled')),
      );
    });

    // «Позднее событие закрытого вызова», D47 Т3: после закрытия кадры
    // этой цепочки не отправляются; ядро их уже не переизлучает (D5), это
    // вторая защита.
    test('a late event of a closed call sends nothing', () async {
      await open();
      startTree();
      expect(labels(), contains('tool_call call_1/call_1 pending'));
      session.emit(finished('call_1', outcome: ToolOutcome.cancelled));
      await pump();
      final before = sent.length;

      session
        ..emit(act(finished('call_1')))
        ..emit(
          act(
            ToolCallProgress(
              root,
              toolCallId: 'call_1',
              content: [ToolCallBlock(TextContent('late'))],
            ),
          ),
        )
        ..emit(
          act(
            finished('call_1'),
            subagent: 'sub_g',
            parent: 'call_2',
            depth: 2,
            path: const ['sub_c'],
          ),
        );
      await pump();

      expect(sent.length, before);
    });

    // Дубль `ToolCallStarted` той же цепочки (реплей/повтор) не удваивает
    // кадр и не портит состояние (AGENTS.md §9).
    test('a duplicate start of the same chain sends one tool_call', () async {
      await open();
      session
        ..emit(
          started(
            'call_1',
            tool: 'agent',
            kind: ToolKind.think,
            subagent: SubagentCallRef(id: 'sub_c', type: 'general'),
          ),
        )
        ..emit(act(started('call_1', tool: 'read', kind: ToolKind.read)))
        ..emit(act(started('call_1', tool: 'read', kind: ToolKind.read)));
      await pump();

      expect(
        labels().where((l) => l == 'tool_call call_1/call_1 pending'),
        hasLength(1),
      );
    });

    // D47 Т2: префикс предка неизвестен — событие не отправляется и пишется
    // `acp.subagent.unknown_parent`; так быть не должно, но молчаливой
    // потери (или кадра с неверной цепочкой) допускать нельзя.
    test('an unknown ancestor: no frame and a warning', () async {
      await open();

      session.emit(
        act(
          started('call_1', tool: 'ls', kind: ToolKind.search),
          subagent: 'sub_g',
          parent: 'call_2',
          depth: 2,
          path: const ['sub_unknown'],
        ),
      );
      await pump();

      expect(sent, isEmpty);
      expect(
        channel.logger.eventsOf('acp.subagent.unknown_parent'),
        hasLength(1),
      );
    });

    // D48 п. 1: `in_progress` вызова потомка шлёт тот же хук markInProgress,
    // с цепочкой в `call.id`; ранний — откладывается до проекции `tool_call`.
    test('in_progress of a descendant call comes after its tool_call, even '
        'if the hook was early', () async {
      final bridge = await open();
      session.emit(
        started(
          'call_1',
          tool: 'agent',
          kind: ToolKind.think,
          subagent: SubagentCallRef(id: 'sub_c', type: 'general'),
        ),
      );
      await pump();

      // Хук срабатывает раньше проекции `tool_call` цепочки.
      await bridge.markInProgress(
        ToolCall(id: 'call_1/call_1', name: 'read', arguments: const {}),
        const {},
        _toolContext(channel),
      );
      await pump();
      expect(
        labels(),
        isNot(contains('tool_call_update call_1/call_1 in_progress')),
      );

      session.emit(act(started('call_1', tool: 'read', kind: ToolKind.read)));
      await pump();

      expect(labels().skip(1), [
        'tool_call call_1/call_1 pending',
        'tool_call_update call_1/call_1 in_progress',
      ]);
    });

    // Хук вызова потомка после проекции его `tool_call` — сразу.
    test('in_progress of a descendant call after its tool_call goes at '
        'once', () async {
      final bridge = await open();
      startTree();
      await pump();

      await bridge.markInProgress(
        ToolCall(id: 'call_1/call_1', name: 'read', arguments: const {}),
        const {},
        _toolContext(channel),
      );

      expect(labels().last, 'tool_call_update call_1/call_1 in_progress');
    });
  });

  group('without the consent', () {
    // SUB-12, «Клиент без согласия»: кадров потомков нет — ни `tool_call`,
    // ни `in_progress`, ни закрытия висящих. Охраняет мост от протечки
    // кадров потомков клиенту, не объявившему согласия.
    test('no frame of a descendant is sent, in_progress included', () async {
      final bridge = await open(consent: false);
      startTree();
      session.emit(finished('call_1', outcome: ToolOutcome.cancelled));
      await pump();
      await bridge.markInProgress(
        ToolCall(id: 'call_1/call_1', name: 'read', arguments: const {}),
        const {},
        _toolContext(channel),
      );
      await pump();

      expect(labels(), [
        'tool_call call_1 pending',
        'tool_call_update call_1 failed cancelled',
      ]);
    });

    // D47 Т3: `_announced` по цепочке ведётся независимо от согласия:
    // `AcpPermissionGate` клиента с согласием читает согласие в момент
    // запроса, и оно может смениться при переподключении.
    test('the chain is announced for the gate anyway', () async {
      final bridge = await open(consent: false);

      startTree();

      await expectLater(
        bridge.announced('call_1/call_1').timeout(const Duration(seconds: 1)),
        completes,
      );
      await expectLater(
        bridge
            .announced('call_1/call_2/call_1')
            .timeout(const Duration(seconds: 1)),
        completes,
      );
    });

    // D47 Т4, дефект: терминал потомка закрывает ожидание `terminalShown`
    // независимо от согласия; иначе `exec` потомка, ждущий показа терминала
    // перед `terminal/wait_for_exit`, не завершается.
    test('a terminal shown by a descendant releases terminalShown', () async {
      final bridge = await open(consent: false);
      startTree();
      final shown = bridge.terminalShown('term_1');

      session.emit(
        act(
          ToolCallProgress(
            root,
            toolCallId: 'call_1',
            content: const [ToolCallTerminal('term_1')],
          ),
        ),
      );

      await expectLater(shown.timeout(const Duration(seconds: 1)), completes);
    });
  });

  group('terminal of a descendant with the consent', () {
    test('the terminal block is projected into the chained call and '
        'releases terminalShown', () async {
      final bridge = await open();
      startTree();
      final shown = bridge.terminalShown('term_1');

      session.emit(
        act(
          ToolCallProgress(
            root,
            toolCallId: 'call_1',
            content: const [ToolCallTerminal('term_1')],
          ),
        ),
      );

      await expectLater(shown.timeout(const Duration(seconds: 1)), completes);
      expect(sent.last.toJson(), {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call_1/call_1',
        'status': 'in_progress',
        'content': [
          {'type': 'terminal', 'terminalId': 'term_1'},
        ],
        '_meta': {
          'codelab': {'parentToolCallId': 'call_1'},
        },
      });
    });
  });

  group('replay', () {
    /// События корня: слова пользователя, вызов `agent` и его итог.
    List<AgentEvent> rootEvents() => [
      MessageEnded(
        root,
        message: UserMessage(const [
          TextContent('Check auth'),
        ], timestamp: DateTime.utc(2026)),
      ),
      started(
        'call_1',
        tool: 'agent',
        kind: ToolKind.think,
        subagent: SubagentCallRef(id: 'sub_c', type: 'general'),
      ),
      SubagentFinished(
        root,
        subagentId: 'sub_c',
        parentToolCallId: 'call_1',
        status: SubagentState.completed,
        usage: const Usage(input: 10, output: 5),
        toolCalls: 2,
        report: 'Report.',
      ),
      finished('call_1'),
    ];

    /// События журнала ребёнка после `ToolCallFinished(agent)`: два вызова,
    /// второй — без результата у потомка, пережившего `cancel_grace`.
    List<AgentEvent> childEvents() => [
      act(started('call_1', tool: 'read', kind: ToolKind.read)),
      act(finished('call_1')),
      act(started('call_2', tool: 'read', kind: ToolKind.read)),
      act(finished('call_2', outcome: ToolOutcome.cancelled)),
    ];

    /// Кадры `session/load`, как их отправляет сервер: через `replayInto`.
    Future<List<acp.SessionUpdate>> replayFrames(SessionBridge bridge) async {
      final frames = <acp.SessionUpdate>[];
      await bridge.replayInto(frames.add);
      return frames;
    }

    List<Map<String, Object?>> toolFrames(List<acp.SessionUpdate> frames) => [
      for (final f in frames)
        if (f.toJson() case {'sessionUpdate': 'tool_call'} && final json) json,
    ];

    // «Реплей дерева»: после `tool_call` вызова `agent` — два `tool_call`
    // ребёнка с итоговыми статусами и `parentToolCallId`; не получивший
    // результата — `failed` с `outcome: cancelled` (D47 Т6).
    test('the tree is replayed right after the agent call', () async {
      final bridge = await open();
      session
        ..replayEvents = rootEvents()
        ..replayTreeEvents = [...rootEvents(), ...childEvents()];

      final frames = toolFrames(await replayFrames(bridge));

      expect(frames.map((f) => f['toolCallId']), [
        'call_1',
        'call_1/call_1',
        'call_1/call_2',
      ]);
      expect(frames.map((f) => f['status']), [
        'completed',
        'completed',
        'failed',
      ]);
      Map<String, Object?> codelab(Map<String, Object?> f) =>
          ((f['_meta']! as Map)['codelab']! as Map).cast<String, Object?>();
      expect(codelab(frames[1]), {'parentToolCallId': 'call_1'});
      expect(codelab(frames[2]), {
        'parentToolCallId': 'call_1',
        'outcome': 'cancelled',
      });
      expect(session.replayTreeCalls, 1);
    });

    // SUB-12, «Реплей дерева»: клиент без согласия получает прежний
    // синхронный `replay()`, журналы потомков не читаются (D47 Т6).
    test('a client without the consent gets the plain replay and the tree '
        'is not read', () async {
      final bridge = await open(consent: false);
      session
        ..replayEvents = rootEvents()
        ..replayTreeEvents = [...rootEvents(), ...childEvents()];

      final frames = toolFrames(await replayFrames(bridge));

      expect(frames.map((f) => f['toolCallId']), ['call_1']);
      expect(session.replayTreeCalls, 0);
    });

    // D47 Т6, ACP-3, AGENTS.md §9: кадр живого хода, пришедший, пока читаются
    // журналы потомков (переподключение идущего хода), не опережает кадры
    // реплея. Мост придерживает его, пока `replayInto` читает журналы и отдаёт
    // кадры, и отпускает в его `finally`: порядок и перекрытие реплеев —
    // `session_bridge_replay_test.dart`.
    test(
      'a live frame during the replay waits for the replay frames',
      () async {
        final bridge = await open();
        final gate = Completer<void>();
        session
          ..replayEvents = rootEvents()
          ..replayTreeEvents = [...rootEvents(), ...childEvents()]
          ..replayTreeGate = gate;

        final replay = replayFrames(bridge);
        await pump();
        session.emit(
          MessageDelta(
            root,
            delta: 'live',
            partial: AssistantMessage(
              content: const [],
              model: scriptedModel,
              usage: Usage.zero,
              stopReason: StopReason.stop,
              timestamp: DateTime.utc(2026),
            ),
          ),
        );
        await pump();
        expect(
          sent.whereType<acp.AgentMessageChunk>(),
          isEmpty,
          reason: 'живой кадр не должен опередить кадры реплея',
        );
        gate.complete();
        final frames = await replay;

        expect(toolFrames(frames), isNotEmpty);
        expect(sent.whereType<acp.AgentMessageChunk>(), hasLength(1));
      },
    );
  });
}

/// Контекст для `markInProgress`: мост его не читает, но тип обязателен.
ToolContext _toolContext(ClientChannel channel) => ToolContext(
  env: MemoryExecutionEnv(cwd: '/work/demo'),
  cancel: CancelToken.none,
  onUpdate: (_) {},
  toolCallId: 'x',
  services: ToolServices(clock: channel.clock, logger: channel.logger),
);

String _outcome(Map<String, Object?> json) {
  final codelab = (json['_meta'] as Map?)?['codelab'] as Map?;
  final outcome = codelab?['outcome'];
  return outcome == null ? '' : ' $outcome';
}

/// Сессия, у которой тест решает, какие события выйдут и что отдаст реплей.
final class _FakeSession implements AgentSession {
  final _events = StreamController<AgentEvent>.broadcast(sync: true);

  /// События `replay()` — корень без журналов потомков.
  List<AgentEvent> replayEvents = const [];

  /// События `replayTree()` — корень и потомки (D47 Т6).
  List<AgentEvent> replayTreeEvents = const [];

  /// Если задан, `replayTree()` ждёт его завершения: журналы потомков
  /// читаются долго.
  Completer<void>? replayTreeGate;
  var replayTreeCalls = 0;

  void emit(AgentEvent event) => _events.add(event);

  Future<void> dispose() => _events.close();

  @override
  SessionId get id => const SessionId('sess_fake');

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  ModelRef get model => scriptedModel;

  @override
  ModelCatalog get models => FixedModelCatalog([scriptedModel]);

  @override
  ModeId get mode => ModeId.standard;

  @override
  ReasoningEffort get effort => ReasoningEffort.medium;

  @override
  List<AgentDefinition> get agents => const [];

  @override
  List<SlashCommand> get commands => const [];

  @override
  Iterable<AgentEvent> replay() => replayEvents;

  @override
  Future<List<AgentEvent>> replayTree() async {
    replayTreeCalls++;
    await replayTreeGate?.future;
    return replayTreeEvents;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
