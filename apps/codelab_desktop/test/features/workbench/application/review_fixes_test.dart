// Исправления по двойному ревью и мутантам итерации B change
// `require-project-folder` (design.md D13, D17, D22, Q25, Q27).
//
// Каждый тест убивает конкретный дефект или мутант; отдельный файл, чтобы
// связь «дефект — тест» читалась сразу.

import 'dart:async';
import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart'
    show ApprovalRequestId;
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspace, ConnectionProfile, ProfileStore, SessionStatusView;
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import 'package:codelab_desktop/core/platform/shared_preferences_workspace_snapshot_store.dart'
    show kWorkspaceSnapshotPrefsKey;
import '../../../support/in_memory_profile_store.dart';
import '../../../support/test_app_scope.dart';
import 'shell_cubit_characterization/harness.dart';

const _caps = AgentCapabilities(
  loadSession: true,
  sessionCapabilities: SessionCapabilities(list: SessionListCapabilities()),
);

List<JsonRpcRequest> _collect(FakeAcpTransport agent, String method) {
  final out = <JsonRpcRequest>[];
  final sub = agent.sent.listen((m) {
    if (m case JsonRpcRequest(method: final x) when x == method) out.add(m);
  });
  addTearDown(sub.cancel);
  return out;
}

void _answerList(FakeAcpTransport agent, JsonRpcRequest request) =>
    agent.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const ListSessionsResponse(sessions: []).toJson(),
      ),
    );

Iterable<Map<String, Object?>> _entries(ShellHarness h, String event) => h
    .binding
    .scope
    .resolve<LogBuffer>()
    .entries
    .value
    .where((e) => e['event'] == event);

void main() {
  setUp(setUpCharacterization);

  test('M3 (Q25): Restart agent during the start has no dialog even when a '
      'session of the window is in a turn', () async {
    final first = FakeAcpTransport();
    final second = FakeAcpTransport()..autoRespondToInitialize = false;
    final transports = [first, second];
    var starts = 0;
    final h = ShellHarness(
      agent: first,
      stdioTransportFactory: (_) => transports[starts++],
    );
    await h.connect();
    await h.createSession('s1');
    unawaited((await h.startTurn('work')).done.catchError((Object _) {}));
    await h.cubit.restartAgent();
    // Новый агент не отвечает на initialize: окно остаётся в «reconnecting».
    unawaited(h.cubit.confirmRestart());
    await pumpEventQueue();
    expect(
      h.cubit.state.connectionStatus,
      CodeLabConnectionStatus.reconnecting,
    );
    final summaries = h.binding.scope
        .resolve<ClientWorkspace>()
        .current
        .sessions;
    expect(
      summaries.any((s) => s.status == SessionStatusView.running),
      isTrue,
      reason: 'the precondition: a turn is still counted while restarting',
    );

    unawaited(h.cubit.restartAgent());
    await pumpEventQueue();

    expect(h.cubit.state.pendingRestart, isNull);
  });

  test('M7 (Q27): the focused session with cwd "/" is not the restart root '
      'when a project is selected', () async {
    final roots = <String?>[];
    final first = FakeAcpTransport()..initializeAgentCapabilities = _caps;
    final second = FakeAcpTransport()..initializeAgentCapabilities = _caps;
    final transports = [first, second];
    var starts = 0;
    final h = ShellHarness(
      agent: first,
      stdioTransportFactory: (c) {
        roots.add(c.cwd);
        return transports[starts++];
      },
    );
    await h.projectReady();
    final list = h.nextSent(sessionListMethod);
    final launch = h.cubit.startOnLaunch();
    final lr = await list as JsonRpcRequest;
    first.emitInbound(
      JsonRpcMessage.response(
        id: lr.id,
        result: const ListSessionsResponse(
          sessions: [SessionInfo(sessionId: SessionId('s-root'), cwd: '/')],
        ).toJson(),
      ),
    );
    await launch;
    final load = _collect(first, sessionLoadMethod);
    h.cubit.selectSession('s-root');
    await pumpEventQueue();
    h.cubit.confirmRootSession();
    await pumpEventQueue();
    first.emitInbound(
      JsonRpcMessage.response(
        id: load.single.id,
        result: const <String, Object?>{},
      ),
    );
    await pumpEventQueue();
    expect(h.cubit.state.activeSessionId, 's-root');

    await h.cubit.selectProject('/work/p');
    await pumpEventQueue();
    unawaited(h.cubit.restartAgent());
    await pumpEventQueue();

    expect(roots.last, '/work/p');
  });

  test('M5 (D17): a stale New session asks the kit for newSession without '
      'activation: the late answer of the stale intent does not take the '
      'kit focus', () async {
    final agent = FakeAcpTransport();
    final h = ShellHarness(agent: agent);
    await h.connect();
    final news = _collect(agent, sessionNewMethod);
    final a = h.cubit.createSession();
    final b = h.cubit.createSession();
    await pumpEventQueue();
    expect(news, hasLength(2));
    // Последнее намерение отвечает первым, устаревшее — позже.
    agent.emitInbound(
      JsonRpcMessage.response(id: news[1].id, result: {'sessionId': 's2'}),
    );
    await pumpEventQueue();
    agent.emitInbound(
      JsonRpcMessage.response(id: news[0].id, result: {'sessionId': 's1'}),
    );
    await Future.wait([a, b]);

    expect(
      h.binding.scope.resolve<ClientWorkspace>().current.activeSessionId,
      const SessionId('s2'),
    );
    expect(h.cubit.state.activeSessionId, 's2');
  });

  test('M8 (D17): New session, then another session is selected before the '
      'session/new answer: the focus stays, the new session is listed, the '
      'event is written', () async {
    final agent = FakeAcpTransport();
    final h = ShellHarness(agent: agent);
    await h.connect();
    await h.createSession('sA');
    final news = _collect(agent, sessionNewMethod);

    final creating = h.cubit.createSession();
    await pumpEventQueue();
    h.cubit.selectSession('sA');
    agent.emitInbound(
      JsonRpcMessage.response(id: news.single.id, result: {'sessionId': 'sB'}),
    );
    await creating;
    await h.settle();

    expect(h.cubit.state.activeSessionId, 'sA');
    expect(h.cubit.state.sessions.map((s) => s.id), containsAll(['sA', 'sB']));
    expect(_entries(h, 'session.focus_superseded'), isNotEmpty);
  });

  test('Q24 / spec: Restart agent without a root writes connect_rejected '
      'with the profile id and no path', () async {
    final binding = CodeLabTestBinding();
    final cubit = binding.scope.resolve<CodeLabShellCubit>();
    await binding.scope.resolve<CodeLabShellParts>().settings.projectRestored;

    await cubit.restartAgent();

    final events = binding.scope.resolve<LogBuffer>().entries.value.where(
      (e) => e['event'] == 'connection.connect_rejected',
    );
    expect(events, hasLength(1));
    expect(events.single['reason'], 'no_project');
    expect(events.single['profile_id'], isNotNull);
    expect(events.single.values.join(), isNot(contains('/work')));
  });

  test('WebSocket (MAJOR 2): a session in a folder missing locally is '
      'loaded through session/load', () async {
    final agent = FakeAcpTransport()..initializeAgentCapabilities = _caps;
    final remote = ConnectionProfile.webSocket(
      id: 'remote',
      label: 'Remote',
      uri: Uri.parse('wss://agent.example.test/acp'),
    );
    final h = ShellHarness(
      agent: agent,
      webSocketTransportFactory: (_) => agent,
      directoryExists: (p) async => p != '/remote/only',
    );
    await h.projectReady();
    await h.cubit.useProfile(remote);
    final list = h.nextSent(sessionListMethod);
    final launch = h.cubit.startOnLaunch();
    final lr = await list as JsonRpcRequest;
    agent.emitInbound(
      JsonRpcMessage.response(
        id: lr.id,
        result: const ListSessionsResponse(
          sessions: [
            SessionInfo(sessionId: SessionId('s-r'), cwd: '/remote/only'),
          ],
        ).toJson(),
      ),
    );
    await launch;
    final load = _collect(agent, sessionLoadMethod);

    h.cubit.selectSession('s-r');
    await pumpEventQueue();

    expect(load, hasLength(1));
  });

  test('Retry of a lost connection starts again with the previous root and '
      'reloads the open sessions (D13)', () async {
    final roots = <String?>[];
    final first = FakeAcpTransport()
      ..initializeAgentCapabilities = const AgentCapabilities(
        loadSession: true,
      );
    final second = FakeAcpTransport()
      ..initializeAgentCapabilities = const AgentCapabilities(
        loadSession: true,
      );
    final transports = [first, second];
    var starts = 0;
    final h = ShellHarness(
      agent: first,
      stdioTransportFactory: (c) {
        roots.add(c.cwd);
        return transports[starts++];
      },
    );
    await h.connect();
    await h.createSession('s1');
    final loads = _collect(second, sessionLoadMethod);
    first.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'exited',
      ),
    );
    await h.settle();
    expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.lost);

    unawaited(h.cubit.retryStart());
    await pumpEventQueue();

    expect(roots, [h.project, h.project]);
    expect(loads, hasLength(1));
    expect(LoadSessionRequest.fromJson(loads.single.params).cwd, h.project);
  });

  test('D22 with a session waiting for permission: the approval is dropped, '
      'a late decision for the old request id sends nothing to the new '
      'connection', () async {
    final first = FakeAcpTransport();
    final second = FakeAcpTransport();
    final transports = [first, second];
    var starts = 0;
    final h = ShellHarness(
      agent: first,
      stdioTransportFactory: (_) => transports[starts++],
    );
    await h.connect();
    await h.createSession('s1');
    unawaited((await h.startTurn('work')).done.catchError((Object _) {}));
    h.requestPermission(
      id: 701,
      sessionId: 's1',
      toolCallId: 't1',
      title: 'Run echo',
    );
    await h.settle();
    expect(h.pendingApprovalTexts(), isNotEmpty);

    await h.cubit.restartAgent();
    expect(h.cubit.state.pendingRestart, isNotNull);
    await h.cubit.confirmRestart();
    await h.settle();
    final before = second.sentMessages.length;

    await h.cubit.respondToApproval(
      approvalId: const ApprovalRequestId('permission-701'),
      sessionId: const SessionId('s1'),
      optionId: 'allow-once',
    );
    await h.settle();

    // Одобрение снято: kit переводит ждущие запросы в `cancelled` при замене
    // транспорта (D22); запрос старого соединения не ждёт ответа нигде.
    expect(h.pendingApprovalTexts(), isEmpty);
    expect(h.cubit.sessionIdsWithPendingApproval, isEmpty);
    expect(
      second.sentMessages.skip(before).whereType<JsonRpcResponse>(),
      isEmpty,
    );
  });

  test('startOnLaunch: Q is selected during the restore and its start is '
      'rejected: the agent is not started in P (D19)', () async {
    var starts = 0;
    final h = ShellHarness(
      directoryExists: (p) async => p != '/work/q',
      stdioTransportFactory: (_) {
        starts++;
        return FakeAcpTransport();
      },
    );

    unawaited(h.cubit.selectProject('/work/q'));
    await h.cubit.startOnLaunch();
    await pumpEventQueue();

    expect(starts, 0);
    expect(h.cubit.state.selectedProjectPath, '/work/q');
  });

  // M10: ветка Q26 (`_agentCannotLoad && detached`) показывает сессию только
  // для последнего намерения фокуса (D17).
  test('M10 (Q26/D17): a stale intent on a detached session of an agent '
      'without loadSession does not take the focus after the start', () async {
    final first = FakeAcpTransport()
      ..initializeAgentCapabilities = const AgentCapabilities(
        loadSession: true,
      );
    final second = FakeAcpTransport();
    final third = FakeAcpTransport();
    final transports = [first, second, third];
    var starts = 0;
    Completer<bool>? gate;
    final h = ShellHarness(
      agent: first,
      stdioTransportFactory: (_) => transports[starts++],
      directoryExists: (p) => p == '/work/harness-project'
          ? (gate?.future ?? Future.value(true))
          : Future.value(true),
    );
    await h.connect();
    await h.createSession('s1');
    await h.cubit.selectProject('/work/other');
    await h.createSession('s2');
    first.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'exited',
      ),
    );
    await h.settle();
    // Второй агент не умеет `session/load`: обе сессии становятся detached.
    unawaited(h.cubit.retryStart());
    await pumpEventQueue();
    second.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'exited',
      ),
    );
    await h.settle();
    expect(
      h.cubit.state.sessions.map((r) => r.status),
      everyElement(CodeLabSessionStatus.detached),
    );
    gate = Completer<bool>();

    // Старое намерение (s1) долго проверяет папку, новое (s2) стартует агента.
    h.cubit.selectSession('s1');
    await pumpEventQueue();
    h.cubit.selectSession('s2');
    await pumpEventQueue();
    gate.complete(true);
    await pumpEventQueue();

    expect(h.cubit.state.activeSessionId, 's2');
  });

  // M15: ветка «старт уже перезагрузил открытую сессию» (D16) показывает её
  // только для последнего намерения фокуса (D17).
  test('M15 (D16/D17): a stale intent on a session that the start reloads '
      'itself does not take the focus', () async {
    final caps = const AgentCapabilities(loadSession: true);
    final first = FakeAcpTransport()..initializeAgentCapabilities = caps;
    final second = FakeAcpTransport();
    final third = FakeAcpTransport()..initializeAgentCapabilities = caps;
    final transports = [first, second, third];
    var starts = 0;
    Completer<bool>? gate;
    final h = ShellHarness(
      agent: first,
      stdioTransportFactory: (_) => transports[starts++],
      directoryExists: (p) => p == '/work/harness-project'
          ? (gate?.future ?? Future.value(true))
          : Future.value(true),
    );
    await h.connect();
    await h.createSession('s1');
    await h.cubit.selectProject('/work/other');
    await h.createSession('s2');
    void lose(FakeAcpTransport t) => t.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'exited',
      ),
    );
    lose(first);
    await h.settle();
    // Агент без `session/load`: обе сессии detached; затем он тоже падает.
    unawaited(h.cubit.retryStart());
    await pumpEventQueue();
    lose(second);
    await h.settle();
    gate = Completer<bool>();
    final reloads = _collect(third, sessionLoadMethod);

    h.cubit.selectSession('s1');
    await pumpEventQueue();
    h.cubit.selectSession('s2');
    await pumpEventQueue();
    // Третий агент умеет `session/load`: старт сам перезагружает обе сессии.
    final answered = <Object>{};
    for (var i = 0; i < 10; i++) {
      for (final r in List.of(reloads)) {
        if (answered.add(r.id)) {
          third.emitInbound(
            JsonRpcMessage.response(
              id: r.id,
              result: const <String, Object?>{},
            ),
          );
        }
      }
      await pumpEventQueue();
    }
    expect(answered, hasLength(2));
    expect(
      h.cubit.state.sessions.map((r) => r.status),
      isNot(contains(CodeLabSessionStatus.detached)),
    );
    gate.complete(true);
    await pumpEventQueue();

    expect(h.cubit.state.activeSessionId, 's2');
  });

  // M11: проверка проекта после ожидания профиля по умолчанию.
  test(
    'M11 (D19): P is restored, the default profile is still loading, Q '
    'is selected: the launch trigger does not start the agent in P',
    () async {
      final gate = Completer<void>();
      var starts = 0;
      final binding = CodeLabTestBinding(
        project: '/work/p',
        profileStore: _GatedStore(gate.future),
        stdioTransportFactory: (_) {
          starts++;
          return FakeAcpTransport();
        },
      );
      final cubit = binding.scope.resolve<CodeLabShellCubit>();
      final parts = binding.scope.resolve<CodeLabShellParts>();
      await parts.settings.projectRestored;
      // Старт при выборе проекта отключён: проверяется именно триггер запуска.
      parts.settings.bindProjectStart(null);

      final launch = cubit.startOnLaunch();
      await pumpEventQueue();
      await cubit.selectProject('/work/q');
      gate.complete();
      await launch;
      await pumpEventQueue();

      expect(starts, 0);
      expect(cubit.state.selectedProjectPath, '/work/q');
    },
  );

  // LOW ревью: зависшее чтение профиля по умолчанию не должно вешать `_run`.
  test('a hanging default-profile store does not hang the start: it ends '
      'by the timeout and the next trigger works', () async {
    final binding = CodeLabTestBinding(
      project: '/work/p',
      profileStore: _GatedStore(Completer<void>().future),
    );
    final cubit = binding.scope.resolve<CodeLabShellCubit>();
    await binding.scope.resolve<CodeLabShellParts>().settings.projectRestored;

    await cubit.startOnLaunch().timeout(const Duration(seconds: 10));
    expect(
      cubit.state.connectionStatus,
      isNot(CodeLabConnectionStatus.connecting),
    );
    await cubit.retryStart().timeout(const Duration(seconds: 10));
  });

  // M12: «Restart agent» во время восстановления ждёт проект.
  test(
    'M12 (spec «Ожидание восстановления»): Restart agent during the '
    'restore waits for it and restarts in P without connect_rejected',
    () async {
      final gate = Completer<bool>();
      var first = true;
      final started = <String?>[];
      final binding = CodeLabTestBinding(
        preferences: {
          kWorkspaceSnapshotPrefsKey: jsonEncode({
            'version': 1,
            'windows': {
              'main': {'projectDirectory': '/work/app', 'openSessions': []},
            },
          }),
        },
        directoryExists: (p) {
          if (first) {
            first = false;
            return gate.future;
          }
          return Future.value(true);
        },
        stdioTransportFactory: (c) {
          started.add(c.cwd);
          return FakeAcpTransport();
        },
      );
      final cubit = binding.scope.resolve<CodeLabShellCubit>();
      await pumpEventQueue();

      final restarting = cubit.restartAgent();
      await pumpEventQueue();
      expect(started, isEmpty);
      gate.complete(true);
      await restarting;
      await pumpEventQueue();

      expect(started, ['/work/app']);
      expect(
        binding.scope.resolve<LogBuffer>().entries.value.where(
          (e) => e['event'] == 'connection.connect_rejected',
        ),
        isEmpty,
      );
    },
  );

  // D24 для detached с cwd «/»: вопрос, без подтверждения session/load нет.
  test('D24: focus on a detached session with cwd "/" asks first and sends '
      'session/load only after Open', () async {
    final first = FakeAcpTransport()..initializeAgentCapabilities = _caps;
    final second = FakeAcpTransport()..initializeAgentCapabilities = _caps;
    final transports = [first, second];
    var starts = 0;
    final h = ShellHarness(
      agent: first,
      stdioTransportFactory: (_) => transports[starts++],
    );
    await h.projectReady();
    final list = h.nextSent(sessionListMethod);
    final launch = h.cubit.startOnLaunch();
    final lr = await list as JsonRpcRequest;
    first.emitInbound(
      JsonRpcMessage.response(
        id: lr.id,
        result: const ListSessionsResponse(
          sessions: [SessionInfo(sessionId: SessionId('s-root'), cwd: '/')],
        ).toJson(),
      ),
    );
    await launch;
    final firstLoads = _collect(first, sessionLoadMethod);
    h.cubit.selectSession('s-root');
    await pumpEventQueue();
    h.cubit.confirmRootSession();
    await pumpEventQueue();
    first.emitInbound(
      JsonRpcMessage.response(
        id: firstLoads.single.id,
        result: const <String, Object?>{},
      ),
    );
    await pumpEventQueue();
    first.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'exited',
      ),
    );
    await h.settle();
    final reload = _collect(second, sessionLoadMethod);
    unawaited(h.cubit.retryStart());
    await pumpEventQueue();
    // Агент не смог восстановить сессию после переподключения: она detached.
    second.emitInbound(
      JsonRpcMessage.response(
        id: reload.single.id,
        error: const JsonRpcError(code: -32002, message: 'Resource not found'),
      ),
    );
    await pumpEventQueue();
    // Список проекта запрашивается после перезагрузки сессий; без ответа на
    // него старт агента не завершён и окно остаётся в `connecting`.
    for (final m in second.sentMessages) {
      if (m is JsonRpcRequest && m.method == sessionListMethod) {
        _answerList(second, m);
      }
    }
    await pumpEventQueue();
    expect(h.cubit.state.sessions.single.status, CodeLabSessionStatus.detached);
    List<JsonRpcRequest> loadsOf() => [
      for (final m in second.sentMessages)
        if (m is JsonRpcRequest && m.method == sessionLoadMethod) m,
    ];
    final reloads = loadsOf().length;

    h.cubit.selectSession('s-root');
    await pumpEventQueue();

    expect(h.cubit.state.pendingRootSession, isNotNull);
    expect(
      loadsOf().length,
      reloads,
      reason: 'no session/load before the answer',
    );

    h.cubit.confirmRootSession();
    await pumpEventQueue(times: 100);
    // Агент умеет `loadSession`, пользователь подтвердил «Open»: уходит
    // сам кадр `session/load` с `cwd` `/`.
    expect(loadsOf().length, reloads + 1);
    expect(LoadSessionRequest.fromJson(loadsOf().last.params).cwd, '/');
    // Ответ снимает ожидание, иначе teardown scope оборвал бы запрос.
    second.emitInbound(
      JsonRpcMessage.response(
        id: loadsOf().last.id,
        result: const <String, Object?>{},
      ),
    );
    await pumpEventQueue();
    expect(h.cubit.state.activeSessionId, 's-root');
  });
}

final class _GatedStore implements ProfileStore {
  _GatedStore(this._gate);

  final Future<void> _gate;
  final _inner = InMemoryProfileStore([testStdioProfile]);

  @override
  Future<List<ConnectionProfile>> load() async {
    await _gate;
    return _inner.load();
  }

  @override
  Future<void> save(ConnectionProfile profile) => _inner.save(profile);

  @override
  Future<bool> remove(String id) => _inner.remove(id);
}
