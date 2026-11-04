// Composition root app и встроенный агент (задача 4.3 change
// `add-embedded-agent-mode`; agent-workbench-ui «Одобрение во встроенном
// режиме»; embedded-agent «Жизненный цикл встроенного агента»; design.md D6,
// «Резолвер клиента» и «Отмена подключения в app» (решение L4), D9).
//
// Агент — настоящий `scriptedEmbeddedAgentOpener` со сценарием модели
// (D8), открыватель подставляется швом `createCodeLabRootScope(
// embeddedOpener:)`. Порядок событий задаётся `Completer`-ами, а не
// таймерами; тесты работают в обычной зоне (`test`), без fake-async.

import 'dart:async';
import 'dart:io';

import 'package:cherrypick/cherrypick.dart' show Scope;
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart'
    show AcpClientApplication;
import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile;
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/embedded_logger.dart';
import 'package:codelab_desktop/app/embedded_transport_resolver.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:codelab_embedded/testing.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../support/test_app_scope.dart';
import '../support/transcript_rows.dart';

const _profile = ConnectionProfile.embedded(
  id: 'embedded',
  label: 'Embedded agent',
  hostProfile: 'embedded-app-desktop',
);

final class _SilentLogger implements Logger {
  @override
  bool isEnabled(LogLevel level) => false;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {}
}

/// Настоящий агент, у которого `dispose` через резолвер ждёт [disposeGate].
///
/// Сам агент останавливается и без резолвера (закрытие клиентского конца),
/// поэтому ворота держат только путь резолвера: именно его ждёт закрытие
/// scope.
final class _TrackedAgent implements EmbeddedAgent {
  _TrackedAgent(this.inner, {required this.disposeGate});

  final EmbeddedAgent inner;
  final Future<void> disposeGate;
  int disposeCalls = 0;

  @override
  bool get secretsInConfig => inner.secretsInConfig;

  @override
  AcpTransport get clientTransport => inner.clientTransport;

  @override
  Future<void> get closed => inner.closed;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await disposeGate;
    await inner.dispose();
  }
}

/// Открыватель с журналом вызовов: каждый вызов сценарного открывателя
/// заворачивается в [_TrackedAgent]; [gates] — необязательные ворота
/// «открыватель ещё работает» для первых вызовов.
final class _Opener {
  _Opener(this._delegate);

  final EmbeddedAgentOpener _delegate;
  final calls = <({String cwd, String hostProfile})>[];
  final agents = <_TrackedAgent>[];

  /// Ворота `dispose` каждого следующего агента (по порядку открытия).
  final disposeGates = <Completer<void>>[];

  /// Ворота возврата открывателя (по порядку вызовов); отсутствие — без
  /// ожидания.
  final openGates = <Completer<void>>[];

  Future<EmbeddedAgent> call({
    required String cwd,
    required String hostProfile,
  }) async {
    final index = calls.length;
    calls.add((cwd: cwd, hostProfile: hostProfile));
    final agent = await _delegate(cwd: cwd, hostProfile: hostProfile);
    if (index < openGates.length) {
      await openGates[index].future;
    }
    final tracked = _TrackedAgent(
      agent,
      disposeGate: index < disposeGates.length
          ? disposeGates[index].future
          : Future<void>.value(),
    );
    agents.add(tracked);
    return tracked;
  }
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not reached in 15 s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Отдаёт управление циклу событий, чтобы готовые продолжения выполнились.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

Map<String, Object?> _text(String text) => {
  'reply': [
    {'text': text},
  ],
};

Map<String, Object?> _write(String id, String path) => {
  'reply': [
    {
      'toolCall': {
        'id': id,
        'name': 'write',
        'arguments': {'path': path, 'content': 'x'},
      },
    },
  ],
};

void main() {
  late Directory temp;
  late Directory project;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    temp = Directory.systemTemp.createTempSync('codelab_app_embedded_');
    project = Directory('${temp.path}/project')..createSync();
    addTearDown(() => temp.deleteSync(recursive: true));
  });

  _Opener scripted(List<Map<String, Object?>> steps) => _Opener(
    scriptedEmbeddedAgentOpener(
      llm: {'steps': steps},
      codelabHome: '${temp.path}/home',
      permissionMode: 'standard',
      logger: _SilentLogger(),
    ),
  );

  Scope scopeWith(
    _Opener opener, {
    FakeAcpTransport? transport,
    Duration? closeTimeout,
  }) {
    final scope = createCodeLabRootScope(
      transportFactory: transport == null
          ? FakeAcpTransport.new
          : () => transport,
      embeddedCloseTimeout: closeTimeout,
      embeddedOpener: opener.call,
      directoryExists: (_) async => true,
      logDirectoryPath: temp.path,
    );
    addTearDown(closeCodeLabRootScopeInTest);
    return scope;
  }

  Future<CodeLabShellCubit> connected(Scope scope) async {
    // Без сохранённого выбора профиль по умолчанию — встроенный агент (D5).
    final shell = scope.resolve<CodeLabShellCubit>();
    await shell.selectProject(project.path);
    await shell.connect();
    expect(shell.state.connectionStatus, CodeLabConnectionStatus.connected);
    return shell;
  }

  test(
    'connects without a child process and completes a turn: the opener '
    'gets the project folder and the embedded-app-desktop host profile',
    () async {
      final opener = scripted([_text('hello from the embedded agent')]);
      final shell = await connected(scopeWith(opener));

      await shell.createSession();
      await shell.submitPrompt('hi');
      await _until(
        () => shell.state.transcriptRows.any(
          (row) => row.kind == 'agent' && row.text.contains('hello from'),
        ),
      );

      expect(opener.calls, [
        (cwd: project.path, hostProfile: 'embedded-app-desktop'),
      ]);
      expect(shell.state.profileLabel, 'Embedded agent');
    },
  );

  test('a rejected approval leaves the file unchanged and the call row '
      'shows the rejection', () async {
    final opener = scripted([_write('call_w', 'new.txt'), _text('understood')]);
    final shell = await connected(scopeWith(opener));
    await shell.createSession();
    final turn = shell.submitPrompt('write new.txt');

    CodeLabTranscriptApprovalPending? pending() => shell.state.transcriptRows
        .map((row) => row.approval)
        .whereType<CodeLabTranscriptApprovalPending>()
        .firstOrNull;
    await _until(() => pending() != null);
    final card = pending()!;
    final reject = card.options.singleWhere(
      (option) => option.kind == CodeLabApprovalOptionKind.rejectOnce,
    );
    card.onOptionSelected(reject.id);
    await turn;
    await _until(() => !shell.state.isPromptSubmitting);

    expect(File('${project.path}/new.txt').existsSync(), isFalse);
    final resolved = shell.state.transcriptRows
        .map((row) => row.approval)
        .whereType<CodeLabTranscriptApprovalResolved>()
        .single;
    expect(resolved.outcome, CodeLabApprovalOutcome.rejected);
  });

  test('closing the root scope waits for dispose of the embedded agent '
      '(journal is written before the process goes on)', () async {
    final opener = scripted([_text('ok')]);
    final gate = Completer<void>();
    opener.disposeGates.add(gate);
    await connected(scopeWith(opener));

    var closed = false;
    final closing = closeCodeLabRootScope().whenComplete(() => closed = true);
    await _until(() => opener.agents.single.disposeCalls > 0);
    await _settle();

    expect(closed, isFalse, reason: 'dispose of the agent is still running');
    gate.complete();
    await closing;
    expect(closed, isTrue);
  });

  test('a second open waits for dispose of the previous agent before it '
      'calls the opener (D6: two agents never write one journal)', () async {
    final opener = scripted([_text('a')]);
    final gate = Completer<void>();
    opener.disposeGates.add(gate);
    final resolver = scopeWith(opener).resolve<EmbeddedTransportResolver>();

    await resolver.open(_profile, projectDirectory: project.path);
    final second = resolver.open(_profile, projectDirectory: project.path);
    await _until(() => opener.agents.single.disposeCalls == 1);
    await _settle();

    expect(opener.calls, hasLength(1), reason: 'dispose of the first pending');
    gate.complete();
    await second;
    expect(opener.calls, hasLength(2));
  });

  test('Connect again while the agent is opening: the stale agent gets '
      'dispose() at once and only the newer one stays (new open cancels, '
      'AGENTS.md §12)', () async {
    final opener = scripted([_text('a')]);
    final openGate = Completer<void>();
    opener.openGates.add(openGate);
    final resolver = scopeWith(opener).resolve<EmbeddedTransportResolver>();

    final stale = resolver.open(_profile, projectDirectory: project.path);
    final staleResult = expectLater(
      stale,
      throwsA(isA<EmbeddedOpenCancelledException>()),
    );
    await _until(() => opener.calls.length == 1);
    final fresh = resolver.open(_profile, projectDirectory: project.path);
    await _settle();
    expect(opener.calls, hasLength(1), reason: 'opens are serialized');

    openGate.complete();
    await staleResult;
    expect(opener.agents.first.disposeCalls, 1);
    final transport = await fresh;

    expect(opener.calls, hasLength(2));
    expect(transport, same(opener.agents.last.clientTransport));
    expect(opener.agents.last.disposeCalls, 0);
  });

  test('closing the root scope while the agent is opening: the agent that '
      'returns later gets dispose() and never becomes current', () async {
    final opener = scripted([_text('a')]);
    final openGate = Completer<void>();
    opener.openGates.add(openGate);
    final resolver = scopeWith(opener).resolve<EmbeddedTransportResolver>();

    final stale = resolver.open(_profile, projectDirectory: project.path);
    final staleResult = expectLater(
      stale,
      throwsA(isA<EmbeddedOpenCancelledException>()),
    );
    await _until(() => opener.calls.length == 1);
    final closing = closeCodeLabRootScope();
    await _settle();
    expect(opener.agents, isEmpty, reason: 'the opener has not returned yet');

    openGate.complete();
    await closing;
    await staleResult;

    expect(opener.agents.single.disposeCalls, 1);
  });

  test('a hung dispose of the embedded agent does not hold the scope: after '
      'the timeout the warning is logged and the transport and the '
      'application are released (D6, «Выход»)', () async {
    final opener = scripted([_text('ok')]);
    final gate = Completer<void>();
    opener.disposeGates.add(gate);
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final transport = FakeAcpTransport();
    final scope = scopeWith(
      opener,
      transport: transport,
      closeTimeout: const Duration(milliseconds: 100),
    );
    await connected(scope);
    final buffer = scope.resolve<LogBuffer>();
    final application = scope.resolve<AcpClientApplication>();

    await closeCodeLabRootScope().timeout(const Duration(seconds: 10));

    final timeouts = buffer.entries.value.where(
      (e) => e['event'] == 'embedded.close_timeout',
    );
    expect(timeouts, hasLength(1));
    expect(timeouts.single['level'].toString().toLowerCase(), contains('warn'));
    expect(transport.state, AcpTransportState.closed);
    await application.sessionChanges.isEmpty.timeout(
      const Duration(seconds: 5),
    );
  });

  test('Connect twice while the first agent is opening: no failed state in '
      'between, connected at the end, one live agent, the stale one gets '
      'dispose() (AGENTS.md §9, §12)', () async {
    final opener = scripted([_text('a')]);
    final openGate = Completer<void>();
    opener.openGates.add(openGate);
    final scope = scopeWith(opener);
    List<String> scopeLogEvents() => [
      for (final e in scope.resolve<LogBuffer>().entries.value) '${e['event']}',
    ];
    final shell = scope.resolve<CodeLabShellCubit>();
    await shell.selectProject(project.path);
    final statuses = <CodeLabConnectionStatus>[];
    final subscription = shell.stream.listen(
      (state) => statuses.add(state.connectionStatus),
    );
    addTearDown(subscription.cancel);

    final first = shell.connect();
    await _until(() => opener.calls.length == 1);
    final second = shell.connect();
    openGate.complete();
    await first;
    await second;
    await _settle();

    expect(shell.state.connectionStatus, CodeLabConnectionStatus.connected);
    expect(statuses, isNot(contains(CodeLabConnectionStatus.failed)));
    expect(shell.state.connectionMessage, isNull);
    // Диагностика успеха ровно одна — от второй попытки.
    final started = scopeLogEvents().where(
      (event) => event.startsWith('Embedded ACP agent started'),
    );
    expect(started, hasLength(1));
    expect(opener.agents, hasLength(2));
    expect(opener.agents.first.disposeCalls, 1);
    expect(opener.agents.last.disposeCalls, 0);
  });

  test('the agent log goes to the application logger without secret values '
      'and with the class of an error only', () async {
    final scope = scopeWith(scripted([]));
    final buffer = scope.resolve<LogBuffer>();
    const secret = 'sk-test-secret-value-123456';

    CodeLabEmbeddedLogger().log(
      LogLevel.info,
      'secrets.lookup',
      fields: {'name': 'codelab/p', 'source': 'env', 'found': true},
    );
    CodeLabEmbeddedLogger().log(
      LogLevel.error,
      'embedded.agent.failed',
      fields: {'api_key': secret, 'authorization': 'Bearer $secret'},
      error: StateError('provider said: $secret'),
    );

    final entries = buffer.entries.value;
    final lookup = entries.singleWhere((e) => e['event'] == 'secrets.lookup');
    expect(lookup['name'], 'codelab/p');
    expect(lookup['found'], true);
    final failure = entries.singleWhere(
      (e) => e['event'] == 'embedded.agent.failed',
    );
    expect(failure['error_class'], 'StateError');
    expect('$entries', isNot(contains(secret)));
  });
}
