// Агент стартует сам (задачи B2.1, B2.2 change `require-project-folder`;
// spec agent-workbench-ui «Агент стартует сам», «Selecting a not-loaded
// session restores its transcript», «Switching project keeps the agent and
// other sessions running», «Исчезнувшая папка сессии»; design.md D13, D17,
// Q26, Q27).
//
// Тесты идут через граф app (`ShellHarness` над `CodeLabTestBinding`) и
// проверяют наблюдаемое: сколько раз открыт транспорт, какие кадры ушли
// агенту, что видит пользователь. Порядок завершений в гонках задан явно
// ответами агента (`concurrency.md` §69–§70), а не таймерами.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspace, ConnectionProfile;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import 'shell_cubit_characterization/harness.dart';

const _withListAndLoad = AgentCapabilities(
  loadSession: true,
  sessionCapabilities: SessionCapabilities(list: SessionListCapabilities()),
);

FakeAcpTransport _agent(AgentCapabilities capabilities) =>
    FakeAcpTransport()..initializeAgentCapabilities = capabilities;

List<String> _methods(FakeAcpTransport agent) => [
  for (final message in agent.sentMessages)
    if (message case JsonRpcRequest(:final method)) method,
];

void _answerList(
  FakeAcpTransport agent,
  JsonRpcRequest request,
  List<SessionInfo> sessions,
) => agent.emitInbound(
  JsonRpcMessage.response(
    id: request.id,
    result: ListSessionsResponse(sessions: sessions).toJson(),
  ),
);

/// Все запросы `session/new`/`session/load`/`session/list` по мере отправки.
List<JsonRpcRequest> _collect(FakeAcpTransport agent, String method) {
  final requests = <JsonRpcRequest>[];
  final subscription = agent.sent.listen((message) {
    if (message case JsonRpcRequest(method: final sent) when sent == method) {
      requests.add(message);
    }
  });
  addTearDown(subscription.cancel);
  return requests;
}

Iterable<Map<String, Object?>> _entries(ShellHarness h, String event) => h
    .binding
    .scope
    .resolve<LogBuffer>()
    .entries
    .value
    .where((entry) => entry['event'] == event);

final _remote = ConnectionProfile.webSocket(
  id: 'remote',
  label: 'Remote',
  uri: Uri.parse('wss://agent.example.test/acp'),
);

void main() {
  setUp(setUpCharacterization);

  group('triggers of D13', () {
    test('selecting a project starts the agent without a session and asks '
        'for the project list', () async {
      final h = ShellHarness(agent: _agent(_withListAndLoad));
      await h.projectReady();
      final list = h.nextSent(sessionListMethod);

      await h.cubit.selectProject('/work/a');
      final request = await list as JsonRpcRequest;
      _answerList(h.agent, request, const []);
      await h.settle();

      expect(ListSessionsRequest.fromJson(request.params).cwd, '/work/a');
      expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.connected);
      expect(_methods(h.agent), isNot(contains(sessionNewMethod)));
      expect(h.stdioStarts, 1);
    });

    test('the project of the last run starts the agent only by the launch '
        'trigger', () async {
      final h = ShellHarness(agent: _agent(_withListAndLoad));
      await h.projectReady();
      await pumpEventQueue();

      expect(h.stdioStarts, 0);
      expect(
        h.cubit.state.connectionStatus,
        CodeLabConnectionStatus.disconnected,
      );

      final list = h.nextSent(sessionListMethod);
      final launched = h.cubit.startOnLaunch();
      _answerList(h.agent, await list as JsonRpcRequest, const []);
      await launched;

      expect(h.stdioStarts, 1);
      expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.connected);
      expect(
        h.binding.scope.resolve<ClientWorkspace>().current.agentDirectory,
        h.project,
      );
    });

    test('New session starts the agent in the project, then creates the '
        'session with the project cwd', () async {
      final h = ShellHarness();
      await h.projectReady();

      final request = await h.createSession('s1');

      expect(h.stdioStarts, 1);
      expect(NewSessionRequest.fromJson(request.params).cwd, h.project);
      expect(h.cubit.state.activeSessionId, 's1');
    });

    test('a WebSocket agent serves two folders over one connection', () async {
      var opened = 0;
      final agent = _agent(const AgentCapabilities(loadSession: true));
      final h = ShellHarness(
        agent: agent,
        webSocketTransportFactory: (_) {
          opened++;
          return agent;
        },
      );
      await h.projectReady();
      await h.cubit.useProfile(_remote);

      await h.cubit.selectProject('/work/a');
      await pumpEventQueue();
      await h.cubit.selectProject('/work/b');
      await pumpEventQueue();

      expect(opened, 1);
      expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.connected);
    });

    test('a session of another folder opens without restarting the agent '
        'and without interrupting a running turn', () async {
      final h = ShellHarness(
        agent: _agent(const AgentCapabilities(loadSession: true)),
      );
      await h.connect();
      await h.createSession('s-a');
      final turn = await h.startTurn('work');

      await h.cubit.selectProject('/work/other');
      await h.settle();
      expect(h.stdioStarts, 1);
      expect(_methods(h.agent), isNot(contains(sessionCancelMethod)));

      h.endTurn(turn.request);
      await turn.done;
      expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.connected);
    });
  });

  group('failure of the start', () {
    test('every trigger starts again after a failure, and nothing starts '
        'again without a user action', () async {
      var opened = 0;
      final h = ShellHarness(
        stdioTransportFactory: (_) {
          opened++;
          return ThrowingStartTransport(StateError('no agent'));
        },
      );
      await h.projectReady();

      await h.cubit.startOnLaunch();
      expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.failed);
      expect(opened, 1);

      // Действий пользователя нет: сколько бы очередей событий ни прошло,
      // новых попыток нет (таймеров повтора в Cubit нет, D13).
      await pumpEventQueue(times: 200);
      expect(opened, 1);

      await h.cubit.selectProject('/work/a');
      await pumpEventQueue();
      expect(opened, 2);
      await h.cubit.createSession();
      expect(opened, 3);
      await h.cubit.retryStart();
      expect(opened, 4);
    });

    test(
      'the same failure three times is one diagnostic record, the '
      'counter shows Failed again (2), another text is a new record',
      () async {
        var opened = 0;
        final h = ShellHarness(
          stdioTransportFactory: (_) {
            opened++;
            return ThrowingStartTransport(StateError('no agent'));
          },
        );
        await h.projectReady();

        for (var i = 0; i < 3; i++) {
          await h.cubit.retryStart();
        }

        final failures = h.logEvents.where(
          (event) => event.startsWith('Failed to start stdio ACP agent'),
        );
        expect(opened, 3);
        expect(failures, hasLength(1));
        expect(h.cubit.state.connectionRepeat, 2);
        expect(
          [for (final e in _entries(h, 'connection.start_failed')) e['repeat']],
          [0, 1, 2],
        );

        // Другой корень процесса — другая запись, даже при том же тексте.
        await h.cubit.selectProject('/work/other');
        await pumpEventQueue();
        expect(
          h.logEvents.where(
            (event) => event.startsWith('Failed to start stdio ACP agent'),
          ),
          hasLength(2),
        );
        expect(h.cubit.state.connectionRepeat, 0);
      },
    );
  });

  group('the folder of a session', () {
    test('a vanished folder: session/load is not sent and the text names '
        'the folder', () async {
      final h = ShellHarness(
        agent: _agent(_withListAndLoad),
        directoryExists: (path) async => path != '/work/gone',
      );
      await h.projectReady();
      final list = h.nextSent(sessionListMethod);
      final started = h.cubit.startOnLaunch();
      _answerList(h.agent, await list as JsonRpcRequest, const [
        SessionInfo(sessionId: SessionId('s-gone'), cwd: '/work/gone'),
      ]);
      await started;
      await h.settle();

      h.cubit.selectSession('s-gone');
      await pumpEventQueue();

      expect(_methods(h.agent), isNot(contains(sessionLoadMethod)));
      expect(
        h.logEvents,
        contains(
          'Project folder not found: /work/gone. '
          'Choose an existing folder with Open folder….',
        ),
      );
    });

    test('a detached session of an agent without loadSession is shown for '
        'reading: no session/load, no diagnostics (Q26)', () async {
      final first = _agent(const AgentCapabilities(loadSession: true));
      final second = _agent(const AgentCapabilities());
      final transports = [first, second];
      var starts = 0;
      final h = ShellHarness(
        agent: first,
        stdioTransportFactory: (_) => transports[starts++],
      );
      await h.connect();
      await h.createSession('s-a');
      await h.cubit.restartAgent();
      await h.settle();
      expect(
        h.cubit.state.sessions.single.status,
        CodeLabSessionStatus.detached,
      );
      final before = h.logEvents.length;

      h.cubit.selectSession('s-a');
      await pumpEventQueue();

      expect(_methods(second), isNot(contains(sessionLoadMethod)));
      expect(h.cubit.state.activeSessionId, 's-a');
      expect(
        h.logEvents.skip(before).where((e) => e.startsWith('Failed')),
        isEmpty,
      );
    });

    test('the agent is down, /work/app is the project, a not-loaded session '
        'with cwd "/" is opened after Open: the process root is the '
        'project, session/load keeps cwd "/" (Q27)', () async {
      final first = _agent(_withListAndLoad);
      final second = _agent(_withListAndLoad);
      final transports = [first, second];
      final roots = <String?>[];
      var starts = 0;
      final h = ShellHarness(
        agent: first,
        stdioTransportFactory: (config) {
          roots.add(config.cwd);
          return transports[starts++];
        },
      );
      await h.projectReady();
      final list = h.nextSent(sessionListMethod);
      await h.cubit.selectProject('/work/app');
      _answerList(h.agent, await list as JsonRpcRequest, const [
        SessionInfo(sessionId: SessionId('s-root'), cwd: '/'),
      ]);
      await h.settle();
      first.fail(
        const AcpTransportException(
          code: AcpTransportErrorCode.disconnected,
          message: 'exited',
        ),
      );
      await h.settle();
      expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.lost);

      h.cubit.selectSession('s-root');
      await h.settle();
      expect(h.cubit.state.pendingRootSession, isNotNull);
      expect(roots, hasLength(1), reason: 'no start before the answer');

      final load = _collect(second, sessionLoadMethod);
      final list2 = _collect(second, sessionListMethod);
      h.cubit.confirmRootSession();
      await pumpEventQueue();
      for (final request in list2) {
        _answerList(second, request, const [
          SessionInfo(sessionId: SessionId('s-root'), cwd: '/'),
        ]);
      }
      await pumpEventQueue();

      expect(roots.last, '/work/app');
      expect(LoadSessionRequest.fromJson(load.single.params).cwd, '/');
    });
  });

  group('races of D17', () {
    test('a project and two New session during the start: one open, the '
        'focus is the last intent, the first session is listed but not '
        'active in the kit', () async {
      final agent = _agent(const AgentCapabilities())
        ..autoRespondToInitialize = false;
      final h = ShellHarness(agent: agent);
      await h.projectReady();
      final news = _collect(agent, sessionNewMethod);
      final initialize = h.nextSent(initializeMethod);

      unawaited(h.cubit.selectProject('/work/a'));
      final first = h.cubit.createSession();
      final second = h.cubit.createSession();
      final init = await initialize as JsonRpcRequest;
      agent.emitInbound(
        JsonRpcMessage.response(
          id: init.id,
          result: InitializeResponse(
            protocolVersion: const ProtocolVersion(1),
            agentCapabilities: const AgentCapabilities(),
          ).toJson(),
        ),
      );
      await pumpEventQueue();
      expect(h.stdioStarts, 1);
      expect(news, hasLength(2));
      for (final (index, request) in news.indexed) {
        agent.emitInbound(
          JsonRpcMessage.response(
            id: request.id,
            result: {'sessionId': 's${index + 1}'},
          ),
        );
      }
      await Future.wait([first, second]);
      await h.settle();

      expect(h.cubit.state.activeSessionId, 's2');
      expect(
        h.binding.scope.resolve<ClientWorkspace>().current.activeSessionId,
        const SessionId('s2'),
      );
      expect(h.cubit.state.sessions.map((row) => row.id), contains('s1'));
    });

    test('s1 then s2 while s1 loads: the focus is s2, no error, the event '
        'session.focus_superseded', () async {
      final h = ShellHarness(agent: _agent(_withListAndLoad));
      await h.projectReady();
      final list = h.nextSent(sessionListMethod);
      final started = h.cubit.startOnLaunch();
      _answerList(h.agent, await list as JsonRpcRequest, const [
        SessionInfo(sessionId: SessionId('s1'), cwd: '/work/a'),
        SessionInfo(sessionId: SessionId('s2'), cwd: '/work/a'),
      ]);
      await started;
      await h.settle();
      final loads = _collect(h.agent, sessionLoadMethod);

      h.cubit.selectSession('s1');
      await pumpEventQueue();
      h.cubit.selectSession('s2');
      await pumpEventQueue();
      expect(loads, hasLength(2));
      for (final request in loads) {
        h.agent.emitInbound(
          JsonRpcMessage.response(
            id: request.id,
            result: const <String, Object?>{},
          ),
        );
      }
      await pumpEventQueue();

      expect(h.cubit.state.activeSessionId, 's2');
      expect(_entries(h, 'session.focus_superseded'), isNotEmpty);
      expect(h.logEvents.where((e) => e.startsWith('Failed')), isEmpty);
    });

    test('Restart agent during session/new: the late answer of the old '
        'connection does not move the focus', () async {
      final first = _agent(const AgentCapabilities());
      final second = _agent(const AgentCapabilities());
      final transports = [first, second];
      var starts = 0;
      final h = ShellHarness(
        agent: first,
        stdioTransportFactory: (_) {
          final next = transports[starts++];
          return starts == 1 ? LingeringTransport(next) : next;
        },
      );
      await h.connect();
      final news = _collect(first, sessionNewMethod);

      final creating = h.cubit.createSession();
      await pumpEventQueue();
      expect(news, hasLength(1));
      await h.cubit.restartAgent();
      first.emitInbound(
        JsonRpcMessage.response(
          id: news.single.id,
          result: {'sessionId': 'old'},
        ),
      );
      await creating;
      await h.settle();

      expect(h.cubit.state.activeSessionId, isNull);
    });
  });
}
