import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:test/test.dart';

/// Client conformance of `AcpClientApplication` on the golden ACP fixture
/// corpus (`14-golden-fixtures.md` §14.10; stage 0, task 0.8).
///
/// The fixture fixes the frames; this test performs the user actions that
/// produce `c2a` frames and checks the resulting session state.
void main() {
  for (final fixture in loadFixtureCorpus()) {
    test(fixture.id, () async {
      late _User user;
      final result = await runClientFixture<AcpClientApplication>(fixture, (
        env,
      ) {
        user = _User(env);
        return user.app;
      }, onBeforeExpect: (step) => user.act(step));
      if (result.skipped) {
        markTestSkipped(result.skipReason!);
        return;
      }
      addTearDown(user.app.dispose);

      final check = _stateChecks[fixture.id];
      expect(check, isNotNull, reason: 'add a state check for ${fixture.id}');
      check!(user, result);
    });
  }
}

/// Drives the client the way a user does in the UI.
final class _User {
  _User(this.env)
    : app = AcpClientApplication(
        transport: FakeAcpTransport(),
        textFileReader: env.fileSystem,
        textFileWriter: env.fileSystem,
        terminalProcessRunner: env.terminal,
      );

  final ClientFixtureEnvironment env;
  final AcpClientApplication app;

  /// Outcomes of `session/set_config_option` calls, in order: the error or
  /// `null` on success.
  final configResults = <Object?>[];

  /// Ошибки `session/prompt`: ход, сорвавшийся у агента, клиент получает
  /// JSON-RPC ошибкой (agent-core §13.8) — это исход сценария, а не сбой
  /// действия пользователя.
  final promptErrors = <Object>[];

  void act(ClientFixtureStep<AcpClientApplication> step) {
    final expected = step.expected;
    switch (expected['method']) {
      case 'initialize':
        step.track(app.connect(env.transport));
      case 'session/new':
        step.track(app.createSession(CreateSessionCommand(cwd: env.cwd)));
      case 'session/prompt':
        final params = expected['params']! as Map<String, Object?>;
        step.track(
          app
              .sendPrompt(
                SendPromptCommand(
                  sessionId: _session.id,
                  prompt: [
                    for (final block in params['prompt']! as List<Object?>)
                      ContentBlock.text(
                        text:
                            (block! as Map<String, Object?>)['text']! as String,
                      ),
                  ],
                ),
              )
              .then<void>((_) {}, onError: promptErrors.add),
        );
      case 'session/load':
        // id берётся из кадра: загружаемой сессии у клиента может ещё не быть
        // (acp/session-load-interrupted-turn начинается без session/new).
        final params = expected['params']! as Map<String, Object?>;
        step.track(
          app.loadSession(
            LoadSessionCommand(
              sessionId: SessionId(params['sessionId']! as String),
              cwd: env.cwd,
            ),
          ),
        );
      case 'session/cancel':
        step.track(app.cancelTurn(CancelTurnCommand(sessionId: _session.id)));
      case 'session/set_config_option':
        final params = expected['params']! as Map<String, Object?>;
        step.track(
          app
              .setSessionConfigOption(
                SetSessionConfigOptionCommand(
                  sessionId: _session.id,
                  configId: SessionConfigId(params['configId']! as String),
                  value: SessionConfigValueId(params['value']! as String),
                ),
              )
              .then<void>(
                (_) => configResults.add(null),
                onError: (Object error) => configResults.add(error),
              ),
        );
      case null when _isPermissionAnswer(expected):
        final outcome =
            ((expected['result']! as Map)['outcome']! as Map<String, Object?>);
        final approval = _session.activeTurn!.approvals.values.singleWhere(
          (a) => !a.isResolved,
        );
        step.track(
          app.respondToPermission(
            outcome['outcome'] == 'selected'
                ? RespondToPermissionCommand.selected(
                    sessionId: _session.id,
                    approvalId: approval.id,
                    optionId: PermissionOptionId(
                      outcome['optionId']! as String,
                    ),
                  )
                : RespondToPermissionCommand.cancelled(
                    sessionId: _session.id,
                    approvalId: approval.id,
                  ),
          ),
        );
    }
  }

  AcpSession get _session => app.sessions.single;

  bool _isPermissionAnswer(Map<String, Object?> frame) => switch (frame) {
    {'result': {'outcome': {'outcome': _}}} => true,
    _ => false,
  };
}

typedef _StateCheck =
    void Function(_User user, ClientFixtureResult<AcpClientApplication> result);

PromptTurn _lastTurn(_User user) => user.app.sessions.single.turns.last;

ToolCallRecord _toolCall(_User user, String id) =>
    _lastTurn(user).toolCalls[ToolCallId(id)]!;

final _stateChecks = <String, _StateCheck>{
  'acp/initialize-capabilities': (user, _) {
    final ready = user.app.connectionState as ClientConnectionReady;
    expect(ready.protocolVersion, const ProtocolVersion(1));
    expect(ready.capabilities.loadSession, isTrue);
    expect(user.app.sessions, isEmpty);
  },
  'acp/session-new-modes-config': (user, _) {
    final session = user.app.sessions.single;
    expect(session.modes?.currentModeId, const SessionModeId('standard'));
    expect(session.modes?.availableModes, hasLength(5));
    expect(session.configOptions?.map((o) => o.id.value), ['mode', 'model']);
  },
  'acp/prompt-text-end-turn': (user, _) {
    expect(_lastTurn(user).status, PromptTurnStatus.completed);
  },
  'acp/prompt-cancel-mid-tool': (user, result) {
    expect(_lastTurn(user).status, PromptTurnStatus.cancelled);
    expect(_toolCall(user, 'call_1').status, ToolCallStatus.failed);
    expect(result.environment!.terminal.started.single.command, '/bin/sh');
  },
  'acp/prompt-tool-permission-allow': (user, _) {
    final turn = _lastTurn(user);
    expect(turn.status, PromptTurnStatus.completed);
    expect(_toolCall(user, 'call_1').status, ToolCallStatus.completed);
    expect(turn.approvals.values.single.status, ApprovalStatus.selected);
  },
  'acp/prompt-tool-permission-reject-continues': (user, _) {
    final turn = _lastTurn(user);
    expect(turn.status, PromptTurnStatus.completed);
    expect(_toolCall(user, 'call_1').status, ToolCallStatus.failed);
    expect(turn.approvals.values.single.status, ApprovalStatus.selected);
  },
  'acp/tool-status-lifecycle': (user, _) {
    expect(_lastTurn(user).status, PromptTurnStatus.completed);
    expect(_toolCall(user, 'call_1').status, ToolCallStatus.completed);
  },
  'acp/tool-read-range': (user, _) {
    expect(_lastTurn(user).status, PromptTurnStatus.completed);
    expect(_toolCall(user, 'call_1').locations.single.line, 10);
  },
  'acp/tool-exec-terminal-embed': (user, result) {
    expect(_lastTurn(user).status, PromptTurnStatus.completed);
    expect(_toolCall(user, 'call_1').status, ToolCallStatus.completed);
    expect(result.environment!.terminal.started.single.args, ['-c', 'echo hi']);
  },
  'acp/prompt-update-plan': (user, _) {
    final turn = _lastTurn(user);
    expect(turn.status, PromptTurnStatus.completed);
    final plans = turn.updates.whereType<PlanUpdate>().toList();
    expect(plans, hasLength(2));
    expect(plans.last.entries.map((e) => e.status), [
      PlanEntryStatus.completed,
      PlanEntryStatus.pending,
      PlanEntryStatus.pending,
    ]);
  },
  'acp/set-config-option-model': (user, _) {
    final model = user.app.sessions.single.configOptions!.singleWhere(
      (o) => o.id.value == 'model',
    );
    expect(model.currentValue.value, 'scripted/m2');
    expect(user.configResults, [isNull, isNotNull]);
  },
  // Корпус этапа 4 (design.md change `add-dart-agent-acp-server`, D8).
  'acp/prompt-streaming-text': (user, _) {
    expect(_lastTurn(user).status, PromptTurnStatus.completed);
  },
  'acp/prompt-thought-chunk': (user, _) {
    final turn = _lastTurn(user);
    expect(turn.status, PromptTurnStatus.completed);
    expect(turn.updates.whereType<AgentThoughtChunk>(), isNotEmpty);
  },
  'acp/prompt-max-turn-requests': (user, _) {
    expect(_lastTurn(user).status, PromptTurnStatus.maxed);
  },
  'acp/prompt-turn-budget-exceeded': (user, _) {
    expect(_lastTurn(user).status, PromptTurnStatus.maxed);
  },
  'acp/prompt-failed-provider-auth': (user, _) {
    expect(_lastTurn(user).status, PromptTurnStatus.failed);
    expect(user.promptErrors, hasLength(1));
  },
  'acp/prompt-provider-error': (user, _) {
    expect(_lastTurn(user).status, PromptTurnStatus.failed);
    expect(user.promptErrors, hasLength(1));
  },
  'acp/prompt-network-drop': (user, _) {
    expect(_lastTurn(user).status, PromptTurnStatus.failed);
    expect(user.promptErrors, hasLength(1));
  },
  'acp/prompt-cancel-mid-stream': (user, _) {
    expect(_lastTurn(user).status, PromptTurnStatus.cancelled);
  },
  'acp/prompt-parallel-tool-calls': (user, _) {
    expect(_lastTurn(user).status, PromptTurnStatus.completed);
    expect(_toolCall(user, 'call_1').status, ToolCallStatus.completed);
    expect(_toolCall(user, 'call_2').status, ToolCallStatus.completed);
  },
  'acp/prompt-anthropic-tool-call': (user, _) {
    expect(_lastTurn(user).status, PromptTurnStatus.completed);
    expect(_toolCall(user, 'call_1').status, ToolCallStatus.completed);
  },
  'acp/prompt-cancel-during-terminal': (user, result) {
    expect(_lastTurn(user).status, PromptTurnStatus.cancelled);
    expect(_toolCall(user, 'call_1').status, ToolCallStatus.failed);
    expect(result.environment!.terminal.started.single.args, [
      '-c',
      'sleep 30',
    ]);
  },
  'acp/tool-write-permission-diff': (user, result) {
    expect(_lastTurn(user).status, PromptTurnStatus.completed);
    expect(result.environment!.fileSystem.files['NOTES.md'], '# Notes\n');
  },
  'acp/tool-edit-exact-replace': (user, result) {
    expect(_toolCall(user, 'call_1').status, ToolCallStatus.completed);
    expect(result.environment!.fileSystem.files['README.md'], '# bar\nbaz\n');
  },
  'acp/tool-edit-ambiguous-match-error': (user, result) {
    expect(_toolCall(user, 'call_1').status, ToolCallStatus.failed);
    expect(result.environment!.fileSystem.files['README.md'], 'foo\nfoo\n');
  },
  'acp/tool-list-dir': (user, _) {
    expect(_toolCall(user, 'call_1').status, ToolCallStatus.completed);
  },
  'acp/tool-search-content': (user, _) {
    expect(_toolCall(user, 'call_1').status, ToolCallStatus.completed);
  },
  'acp/tool-invalid-args-error': (user, _) {
    expect(_lastTurn(user).status, PromptTurnStatus.completed);
    expect(_toolCall(user, 'call_1').status, ToolCallStatus.failed);
  },
  'acp/tool-exec-terminal-env-array': (user, result) {
    expect(_toolCall(user, 'call_1').status, ToolCallStatus.completed);
    expect(result.environment!.terminal.started.single.command, '/bin/sh');
  },
  'acp/permission-options-all-four': (user, _) {
    final turn = _lastTurn(user);
    expect(_toolCall(user, 'call_1').status, ToolCallStatus.failed);
    expect(turn.approvals.values.single.status, ApprovalStatus.selected);
  },
  'acp/permission-outcome-cancelled': (user, _) {
    final turn = _lastTurn(user);
    expect(turn.status, PromptTurnStatus.completed);
    expect(turn.approvals.values.single.status, ApprovalStatus.cancelled);
  },
  'acp/permission-critical-pattern-in-bypass': (user, _) {
    expect(_toolCall(user, 'call_1').status, ToolCallStatus.failed);
  },
  'acp/permission-allow-always-scoped': (user, result) {
    final turn = _lastTurn(user);
    expect(turn.approvals, hasLength(2));
    expect(result.environment!.fileSystem.files['README.md'], '# baz\n');
  },
  'acp/session-info-title': (user, _) {
    expect(_lastTurn(user).status, PromptTurnStatus.completed);
    expect(
      _lastTurn(user).updates.whereType<SessionInfoUpdate>().single.title,
      'Почини тест в a_test.dart',
    );
  },
  'acp/compaction-long-session-continues': (user, _) {
    final turns = user.app.sessions.single.turns;
    expect(turns, hasLength(3));
    expect(turns.every((t) => t.status == PromptTurnStatus.completed), isTrue);
  },
  // Реплей `session/load` (change `add-client-session-load-replay`): история
  // заменяет прежние ходы и не выглядит выполняющейся (session-lifecycle §51).
  'acp/session-load-replay': (user, _) {
    final session = user.app.sessions.single;
    expect(session.status, SessionLifecycleStatus.active);
    expect(session.activeTurn, isNull);
    expect(session.title, 'Fixture');
    expect(session.modes?.currentModeId, const SessionModeId('standard'));
    final turn = session.turns.single;
    expect(turn.status, PromptTurnStatus.completed);
    expect(turn.prompt, const [ContentBlock.text(text: 'Что в README.md?')]);
    expect(
      turn.toolCalls[const ToolCallId('call_1')]?.status,
      ToolCallStatus.completed,
    );
    expect(
      turn.updates.whereType<AgentMessageChunk>().single.content,
      const ContentBlock.text(text: 'Один заголовок.'),
    );
  },
  'acp/session-load-interrupted-turn': (user, _) {
    final session = user.app.sessions.single;
    expect(session.id, const SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C'));
    expect(session.activeTurn, isNull);
    final turn = session.turns.single;
    expect(turn.prompt, const [ContentBlock.text(text: 'Прочитай a.txt')]);
    expect(
      turn.toolCalls[const ToolCallId('call_9')]?.status,
      ToolCallStatus.failed,
    );
  },
  'acp/config-effort-option': (user, _) {
    expect(user.configResults, [isNull, isNull, isNull]);
    final options = user.app.sessions.single.configOptions!;
    expect(
      options.singleWhere((o) => o.id.value == 'model').currentValue.value,
      'scripted/scripted-1',
    );
    expect(_lastTurn(user).status, PromptTurnStatus.completed);
  },
  'acp/errors-unknown-session-update-tolerated': (user, _) {
    final session = user.app.sessions.single;
    expect(_lastTurn(user).status, PromptTurnStatus.completed);
    expect(
      user.app.diagnostics.where((d) => d.severity == DiagnosticSeverity.error),
      isEmpty,
    );
    expect(session.diagnostics, isEmpty);
  },
};
