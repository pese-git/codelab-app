// Подтверждение открытия сессии в корне диска (задача A1.12 change
// `require-project-folder`; spec agent-workbench-ui «Подтверждение открытия
// сессии в корне диска»; design.md D24).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import 'shell_cubit_characterization/harness.dart';

const _withListAndLoad = AgentCapabilities(
  loadSession: true,
  sessionCapabilities: SessionCapabilities(list: SessionListCapabilities()),
);

void main() {
  setUp(setUpCharacterization);

  Future<ShellHarness> listing(
    Map<String, String> cwdById, {
    FakeAcpTransport? afterReconnect,
  }) async {
    final first = FakeAcpTransport()
      ..initializeAgentCapabilities = _withListAndLoad;
    var opened = 0;
    final h = ShellHarness(
      agent: first,
      stdioTransportFactory: afterReconnect == null
          ? null
          : (_) => opened++ == 0 ? first : afterReconnect,
    );
    final list = h.nextSent(sessionListMethod);
    final connecting = h.connect();
    final request = await list as JsonRpcRequest;
    h.agent.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: ListSessionsResponse(
          sessions: [
            for (final entry in cwdById.entries)
              SessionInfo(
                sessionId: SessionId(entry.key),
                cwd: entry.value,
                title: entry.key,
              ),
          ],
        ).toJson(),
      ),
    );
    await connecting;
    return h;
  }

  List<String> loads(ShellHarness h) => [
    for (final message in h.agent.sentMessages)
      if (message case JsonRpcRequest(
        :final method,
        :final params,
      ) when method == sessionLoadMethod)
        LoadSessionRequest.fromJson(params).cwd,
  ];

  List<Map<String, Object?>> rootEvents(ShellHarness h) => [
    for (final entry in h.binding.scope.resolve<LogBuffer>().entries.value)
      if (entry['event'] == 'session.root_open')
        Map<String, Object?>.from(entry),
  ];

  /// Сессия [id] получает ответ агента на `session/load`.
  Future<void> answerLoad(ShellHarness h, Future<JsonRpcMessage> sent) async {
    final request = await sent as JsonRpcRequest;
    h.agent.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const <String, Object?>{},
      ),
    );
    await h.settle();
  }

  test('selecting a notLoaded session in the disk root asks first: nothing '
      'is sent and the focus stays', () async {
    final h = await listing({'s-root': '/'});

    h.cubit.selectSession('s-root');
    await h.settle();

    expect(h.cubit.state.pendingRootSession, (sessionId: 's-root', cwd: '/'));
    expect(loads(h), isEmpty);
    expect(h.cubit.state.activeSessionId, isNull);
  });

  test('Open loads the session with cwd / and focuses it', () async {
    final h = await listing({'s-root': '/'});
    h.cubit.selectSession('s-root');
    await h.settle();

    final load = h.nextSent(sessionLoadMethod);
    h.cubit.confirmRootSession();
    await answerLoad(h, load);

    expect(loads(h), ['/']);
    expect(h.cubit.state.pendingRootSession, isNull);
    expect(h.cubit.state.activeSessionId, 's-root');
    final events = rootEvents(h);
    expect(events.single['decision'], 'open');
    expect(events.single['session_id'], 's-root');
    expect(events.single.values.join(), isNot(contains('/work')));
  });

  test('Cancel changes nothing and sends nothing', () async {
    final h = await listing({'s-root': '/'});
    h.cubit.selectSession('s-root');
    await h.settle();

    h.cubit.cancelRootSession();
    await h.settle();

    expect(h.cubit.state.pendingRootSession, isNull);
    expect(loads(h), isEmpty);
    expect(h.cubit.state.activeSessionId, isNull);
    expect(
      h.cubit.state.sessions.single.status,
      CodeLabSessionStatus.notLoaded,
    );
    expect(rootEvents(h).single['decision'], 'cancel');
    expect(rootEvents(h).single['session_id'], 's-root');
  });

  test('choosing another session during the dialog closes it as Cancel and '
      'opens that session without asking', () async {
    final h = await listing({'s-root': '/', 's-app': '/work/app'});
    h.cubit.selectSession('s-root');
    await h.settle();

    final load = h.nextSent(sessionLoadMethod);
    h.cubit.selectSession('s-app');
    await answerLoad(h, load);

    expect(h.cubit.state.pendingRootSession, isNull);
    expect(loads(h), ['/work/app']);
    expect(h.cubit.state.activeSessionId, 's-app');
    expect(rootEvents(h).single['decision'], 'cancel');
  });

  test('a repeated click on the same session is ignored', () async {
    final h = await listing({'s-root': '/'});

    h.cubit.selectSession('s-root');
    h.cubit.selectSession('s-root');
    await h.settle();

    expect(h.cubit.state.pendingRootSession, (sessionId: 's-root', cwd: '/'));
    expect(rootEvents(h), isEmpty);
    expect(loads(h), isEmpty);
  });

  test('unnormalized roots ask too; a project folder does not', () async {
    final h = await listing({
      's-dots': '/tmp/..',
      's-slashes': '//',
      's-app': '/work/app',
    });

    h.cubit.selectSession('s-dots');
    await h.settle();
    expect(h.cubit.state.pendingRootSession, (sessionId: 's-dots', cwd: '/'));

    h.cubit.cancelRootSession();
    h.cubit.selectSession('s-slashes');
    await h.settle();
    expect(h.cubit.state.pendingRootSession?.sessionId, 's-slashes');

    h.cubit.cancelRootSession();
    final load = h.nextSent(sessionLoadMethod);
    h.cubit.selectSession('s-app');
    await answerLoad(h, load);
    expect(h.cubit.state.pendingRootSession, isNull);
    expect(loads(h), ['/work/app']);
  });

  test('a late load of an earlier session does not close the question '
      '(D17, D24)', () async {
    final h = await listing({'s-root': '/', 's-app': '/work/app'});
    final load = h.nextSent(sessionLoadMethod);
    h.cubit.selectSession('s-app');
    final request = await load as JsonRpcRequest;

    h.cubit.selectSession('s-root');
    await h.settle();
    expect(h.cubit.state.pendingRootSession?.sessionId, 's-root');

    // Порядок задан тестом: ответ на загрузку s-app приходит после вопроса.
    h.agent.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const <String, Object?>{},
      ),
    );
    await h.settle();
    await h.settle();

    expect(h.cubit.state.pendingRootSession?.sessionId, 's-root');
    expect(rootEvents(h), isEmpty);
  });

  test('the question is cancelled when the row disappears; no open event '
      'without a load', () async {
    final second = FakeAcpTransport()
      ..initializeAgentCapabilities = _withListAndLoad;
    final h = await listing({'s-root': '/'}, afterReconnect: second);
    h.cubit.selectSession('s-root');
    await h.settle();
    expect(h.cubit.state.pendingRootSession, isNotNull);

    final list = second.sent.firstWhere(
      (m) => m is JsonRpcRequest && m.method == sessionListMethod,
    );
    final reconnecting = h.cubit.reconnect();
    final request = await list as JsonRpcRequest;
    second.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const ListSessionsResponse(sessions: []).toJson(),
      ),
    );
    await reconnecting;
    await h.settle();

    expect(h.cubit.state.pendingRootSession, isNull);
    expect(loads(h), isEmpty);
    final events = rootEvents(h);
    expect(events.single['decision'], 'cancel');
    expect(events.single['session_id'], 's-root');
  });
}
