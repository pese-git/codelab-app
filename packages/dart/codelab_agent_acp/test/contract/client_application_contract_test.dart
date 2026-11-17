import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show AgentMessageChunk, ContentBlock, PermissionOptionId, TextContent;
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent_acp/codelab_agent_acp.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart'
    hide ContentBlock, SessionId, TextContent;
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../support/server_harness.dart'
    show HostEnv, JournalStore, UnusedGate, scriptedModel, testAgentInfo;

/// Contract test этапа 4 (задача 10.1; dart-agent-and-clients §9.9, задача
/// 4.7): настоящий `AcpClientApplication` против `AcpAgentServer` через
/// продуктовый `InProcessAcpLink` (`codelab_acp_transports`) на
/// scripted-модели — тот же код клиента, что в codelab-app, без процессов и
/// сокетов.
void main() {
  late _Pair pair;
  _Pair? started;

  tearDown(() async {
    await started?.dispose();
    started = null;
  });

  test(
    'prompt response is sent after the last session/update of the turn',
    () async {
      // 10 различимых дельт по 16 символов (§14.7).
      final text = [
        for (var i = 0; i < 10; i++) 'chunk $i'.padRight(16, '.'),
      ].join();
      pair = started = await _Pair.start([
        {
          'reply': [
            {'text': text},
          ],
        },
      ]);
      final session = await pair.newSession();

      final turn = await pair.app.sendPrompt(_prompt(session, 'Hi'));

      // Когда клиент получил ответ, все дельты хода уже применены (ACP-3).
      expect(turn.status, PromptTurnStatus.completed);
      final chunks = pair
          .turnOf(session)
          .updates
          .whereType<AgentMessageChunk>();
      expect(chunks, hasLength(10));
      expect(chunks.map((c) => (c.content as TextContent).text).join(), text);
    },
  );

  test('session/cancel yields stopReason cancelled', () async {
    pair = started = await _Pair.start([
      {
        'reply': [
          {'text': 'Starting'},
        ],
        'waitForCancel': true,
      },
    ]);
    final session = await pair.newSession();

    final turn = pair.app.sendPrompt(_prompt(session, 'Long task'));
    await pair.until(
      () => pair
          .turnOf(session)
          .updates
          .whereType<AgentMessageChunk>()
          .isNotEmpty,
    );
    await pair.app.cancelTurn(CancelTurnCommand(sessionId: session.id));

    expect((await turn).status, PromptTurnStatus.cancelled);
  });

  test('a permission request is answered with the chosen option', () async {
    pair = started = await _Pair.start(
      [
        {
          'reply': [
            {
              'toolCall': {
                'id': 'call_1',
                'name': 'edit',
                'arguments': {
                  'path': 'README.md',
                  'oldText': 'foo',
                  'newText': 'bar',
                },
              },
            },
          ],
        },
        {
          'reply': [
            {'text': 'Done.'},
          ],
        },
      ],
      files: {'README.md': '# foo\n'},
    );
    final session = await pair.newSession();

    final turn = pair.app.sendPrompt(_prompt(session, 'Edit README.md'));
    await pair.until(
      () => pair.turnOf(session).approvals.values.any((a) => !a.isResolved),
    );
    final approval = pair
        .turnOf(session)
        .approvals
        .values
        .singleWhere((a) => !a.isResolved);
    await pair.app.respondToPermission(
      RespondToPermissionCommand.selected(
        sessionId: session.id,
        approvalId: approval.id,
        optionId: const PermissionOptionId('allow_once'),
      ),
    );

    expect((await turn).status, PromptTurnStatus.completed);
    expect(pair.files.files['README.md'], '# bar\n');
  });

  test('session/load reopens the session with its replay', () async {
    pair = started = await _Pair.start([
      {
        'reply': [
          {'text': 'Hello.'},
        ],
      },
    ]);
    final session = await pair.newSession();
    await pair.app.sendPrompt(_prompt(session, 'Hi'));

    final loaded = await pair.app.loadSession(
      LoadSessionCommand(sessionId: session.id, cwd: _cwd),
    );

    expect(loaded.status, SessionLifecycleStatus.active);
    expect(loaded.modes?.currentModeId.value, 'standard');
    expect(
      pair.app.diagnostics.where((d) => d.severity == DiagnosticSeverity.error),
      isEmpty,
    );
  });
}

const _cwd = '/work/demo';

SendPromptCommand _prompt(AcpSession session, String text) => SendPromptCommand(
  sessionId: session.id,
  prompt: [ContentBlock.text(text: text)],
);

/// Клиент и сервер на двух концах пары транспортов в памяти.
final class _Pair {
  _Pair._(this.app, this.server, this.files);

  static Future<_Pair> start(
    List<Map<String, Object?>> steps, {
    Map<String, String> files = const {},
  }) async {
    final clock = FakeClock();
    final logger = RecordingLogger();
    final core = buildAgentCore(
      profile: HostProfile.of('agent-serve').narrowed({
        HostCapability.fileListing: const CapabilityOff(
          'contract test: клиент не на этой машине',
        ),
      }),
      services: AgentCoreServices(
        baseEnv: HostEnv(MemoryExecutionEnv(cwd: '/', clock: clock)),
        gate: const UnusedGate(),
        logger: logger,
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: JournalStore(),
      ),
      config: CoreConfig(defaultModel: scriptedModel),
      streamFunction: ScriptedStreamFunction.fromJson({
        'steps': steps,
      }, clock: clock).call,
    );
    final server = AcpAgentServer(
      core: core,
      config: const AcpServerConfig(agentInfo: testAgentInfo),
      logger: logger,
      clock: clock,
    );
    final link = InProcessAcpLink();
    unawaited(server.serve(link.agent));
    final fileSystem = InMemoryFixtureFileSystem(cwd: _cwd, files: files);
    // connect() закрывает транспорт конструктора и стартует переданный:
    // в конструктор — заглушка, как в приложении до первого подключения.
    final app = AcpClientApplication(
      transport: FakeAcpTransport(),
      textFileReader: fileSystem,
      textFileWriter: fileSystem,
      terminalProcessRunner: FixtureTerminalProcessRunner(const {}),
    );
    await app.connect(link.client);
    return _Pair._(app, server, fileSystem);
  }

  final AcpClientApplication app;
  final AcpAgentServer server;
  final InMemoryFixtureFileSystem files;

  Future<AcpSession> newSession() =>
      app.createSession(const CreateSessionCommand(cwd: _cwd));

  PromptTurn turnOf(AcpSession session) =>
      app.sessionById(session.id)!.turns.last;

  /// Ждёт условия, пропуская события цикла (не дольше 5 с).
  Future<void> until(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('condition not reached in 5 s');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> dispose() async {
    await app.dispose();
    await server.shutdown(grace: Duration.zero);
  }
}
