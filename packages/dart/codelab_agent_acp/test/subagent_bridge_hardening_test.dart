import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_acp/src/session_bridge.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/client_channel.dart';
import 'support/fake_bridge_session.dart';

/// Устойчивость моста к вызовам потомков после ревью итерации 5 change
/// `add-subagents-and-tasks`: терминалы потомка, поздние кадры после конца
/// хода, ожидание объявления цепочки, журнал закрытия поддерева
/// (design.md D21, D47 Т3, Т4; AGENTS.md §9, §16).
void main() {
  const root = SessionId('sess_fake');

  late FakeBridgeSession session;
  late List<acp.SessionUpdate> sent;
  late ClientChannel channel;

  Future<SessionBridge> open() async {
    channel = await ClientChannel.open(
      capabilities: const acp.ClientCapabilities(
        terminal: true,
        meta: {
          'codelab': {
            'subagentToolCalls': {'version': 1},
          },
        },
      ),
    );
    session = FakeBridgeSession();
    sent = [];
    return SessionBridge(
      owner: Object(),
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
    title: 'Run $tool',
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

  ToolCallProgress terminalOf(String id, String terminal) => ToolCallProgress(
    root,
    toolCallId: id,
    content: [ToolCallTerminal(terminal)],
  );

  TurnEnded turnEnded() =>
      TurnEnded(root, reason: TurnEndReason.completed, usage: Usage.zero);

  void startAgent() => session.emit(
    started(
      'call_1',
      tool: 'agent',
      kind: ToolKind.think,
      subagent: SubagentCallRef(id: 'sub_c', type: 'general'),
    ),
  );

  void startChild() {
    startAgent();
    session.emit(act(started('call_1', tool: 'read', kind: ToolKind.read)));
  }

  /// Ожидание `terminalShown` обязано завершиться: либо успехом, либо
  /// `CancelledException` — но не зависнуть.
  Future<void> settles(Future<void> future) => future
      .then<void>((_) {}, onError: (Object _) {})
      .timeout(const Duration(seconds: 1));

  group('terminal of a descendant whose frame is dropped', () {
    // D47 Т4, остаток дефекта: кадр терминала потомка отсекается, а `exec`
    // потомка уже ждёт `terminalShown` — ожидание не должно зависеть от того,
    // дошёл ли кадр до клиента.
    test('a closed agent call still releases terminalShown', () async {
      final bridge = await open();
      startChild();
      final shown = bridge.terminalShown('term_1');
      session.emit(finished('call_1', outcome: ToolOutcome.cancelled));
      await pump();
      final before = sent.length;

      session.emit(act(terminalOf('call_1', 'term_1')));
      await pump();

      await expectLater(settles(shown), completes);
      var released = false;
      unawaited(shown.then((_) => released = true, onError: (_) {}));
      await pump();
      expect(released, isTrue, reason: 'ожидание завершено, а не оборвано');
      expect(sent.length, before, reason: 'кадр закрытой цепочки не уходит');
    });

    test('a closed own chain still releases terminalShown', () async {
      final bridge = await open();
      startChild();
      session.emit(act(finished('call_1')));
      await pump();
      final shown = bridge.terminalShown('term_1');

      session.emit(act(terminalOf('call_1', 'term_1')));
      await pump();

      var released = false;
      unawaited(shown.then((_) => released = true, onError: (_) {}));
      await pump();
      expect(released, isTrue);
    });

    test('an unknown ancestor still releases terminalShown', () async {
      final bridge = await open();
      final shown = bridge.terminalShown('term_1');

      session.emit(
        act(
          terminalOf('call_1', 'term_1'),
          subagent: 'sub_g',
          parent: 'call_2',
          depth: 2,
          path: const ['sub_unknown'],
        ),
      );
      await pump();

      var released = false;
      unawaited(shown.then((_) => released = true, onError: (_) {}));
      await pump();
      expect(released, isTrue);
      expect(sent, isEmpty);
    });

    test('the end of the turn ends the wait for a terminal', () async {
      final bridge = await open();
      startChild();
      final outcome = expectLater(
        bridge.terminalShown('term_never').timeout(const Duration(seconds: 1)),
        throwsA(isA<CancelledException>()),
      );

      session.emit(turnEnded());
      await pump();

      await outcome;
    });
  });

  group('late frames after the end of the turn', () {
    test('a late event of a descendant sends nothing', () async {
      await open();
      startChild();
      await pump();
      session.emit(turnEnded());
      await pump();
      final before = sent.length;

      session
        ..emit(act(started('call_2', tool: 'read', kind: ToolKind.read)))
        ..emit(
          act(
            ToolCallProgress(
              root,
              toolCallId: 'call_1',
              content: [ToolCallBlock(TextContent('late'))],
            ),
          ),
        )
        ..emit(act(finished('call_1')));
      await pump();

      expect(sent.length, before);
    });

    test('a late event of a closed agent call sends nothing', () async {
      await open();
      startChild();
      session
        ..emit(finished('call_1'))
        ..emit(turnEnded());
      await pump();
      final before = sent.length;

      session.emit(act(started('call_9', tool: 'read', kind: ToolKind.read)));
      await pump();

      expect(sent.length, before);
    });

    // `prompt` снимает признак конца хода: новый ход принимает потомков.
    test('the next turn accepts descendants again', () async {
      final bridge = await open();
      await bridge.prompt(const [TextContent('one')]);
      session.emit(act(started('call_1', tool: 'read', kind: ToolKind.read)));
      await pump();
      expect(sent, isEmpty, reason: 'между ходами потомков нет');

      final gate = session.promptGate = Completer<void>();
      final second = bridge.prompt(const [TextContent('two')]);
      await pump();
      startChild();
      await pump();
      expect(sent, isNotEmpty);
      gate.complete();
      await second;
    });

    // Мутация: без `_closed.clear()` в `prompt` закрытая в первом ходе цепочка
    // `call_1` отсекала бы потомков повторного вызова с тем же id во втором.
    test('the next turn accepts descendants of a reused agent call id', () async {
      final bridge = await open();
      final firstGate = session.promptGate = Completer<void>();
      final first = bridge.prompt(const [TextContent('one')]);
      await pump();
      startChild();
      session
        ..emit(finished('call_1'))
        ..emit(turnEnded());
      await pump();
      firstGate.complete();
      await first;
      sent.clear();

      final gate = session.promptGate = Completer<void>();
      final second = bridge.prompt(const [TextContent('two')]);
      await pump();
      startAgent();
      await pump();
      sent.clear(); // кадр самого вызова `agent` не доказывает проекцию потомка
      session.emit(act(started('call_1', tool: 'read', kind: ToolKind.read)));
      await pump();
      expect(sent, isNotEmpty, reason: 'потомок нового вызова call_1');
      gate.complete();
      await second;
    });
  });

  group('announce and closed chain', () {
    // Мутация: без `_awaitingAnnounce.remove(chain)?.complete()` в ветке
    // `ToolCallStarted` ожидающий gate не освобождался бы проекцией цепочки.
    test('a gate waiting for the chain is released by its tool_call', () async {
      final bridge = await open();
      startAgent();
      await pump();
      final waiting = bridge.announced('call_1/call_1');
      var done = false;
      unawaited(waiting.then((_) => done = true));
      await pump();
      expect(done, isFalse, reason: 'цепочка ещё не объявлена');

      session.emit(act(started('call_1', tool: 'read', kind: ToolKind.read)));
      await pump();

      expect(done, isTrue);
    });

    // Мутация: без отсева `_closed.contains(chain)` в ветке прогресса поздний
    // `tool_call_update` уже закрытой цепочки уходил бы клиенту.
    test('a late progress of a closed own chain is not sent', () async {
      await open();
      startChild();
      session.emit(act(finished('call_1')));
      await pump();
      final before = sent.length;

      session.emit(
        act(
          ToolCallProgress(
            root,
            toolCallId: 'call_1',
            content: [ToolCallBlock(TextContent('late'))],
          ),
        ),
      );
      await pump();

      expect(sent.length, before);
    });
  });

  group('logs', () {
    test('closing a subtree is logged without chains', () async {
      await open();
      startChild();
      session
        ..emit(act(started('call_3')))
        ..emit(finished('call_1', outcome: ToolOutcome.cancelled));
      await pump();

      final records = channel.logger.eventsOf('acp.subagent.subtree_closed');
      expect(records, hasLength(1));
      expect(records.single.fields, {
        'session_id': 'sess_fake',
        'tool_call_id': 'call_1',
        'closed_calls': 2,
      });
    });

    test('nothing is logged when no call was left open', () async {
      await open();
      startChild();
      session.emit(act(finished('call_1')));
      session.emit(finished('call_1'));
      await pump();

      expect(channel.logger.eventsOf('acp.subagent.subtree_closed'), isEmpty);
    });

    test('unknown_parent carries the parent tool call id', () async {
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

      expect(
        channel.logger.eventsOf('acp.subagent.unknown_parent').single.fields,
        {
          'session_id': 'sess_fake',
          'subagent_id': 'sub_g',
          'parent_tool_call_id': 'call_2',
        },
      );
    });
  });
}
