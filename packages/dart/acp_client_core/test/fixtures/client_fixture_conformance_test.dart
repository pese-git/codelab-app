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

  group('known divergences', _knownDivergences);
}

/// Known divergence of the client from the specification, found by the
/// corpus (design.md D7): the fixture stays, the client is fixed by a
/// separate change.
const _cancelledToolCallSkip =
    'AcpClientApplication leaves call_1 in_progress after session/cancel: it '
    'neither marks unfinished tool calls cancelled nor accepts the later '
    'tool_call_update (05-Prompt Turn.md#cancellation, SHOULD); fix in a '
    'separate OpenSpec change';

void _knownDivergences() {
  test(
    'acp/prompt-cancel-mid-tool: the cancelled tool call ends failed',
    () async {
      final fixture = loadFixtureCorpus().singleWhere(
        (f) => f.id == 'acp/prompt-cancel-mid-tool',
      );
      late _User user;
      await runClientFixture<AcpClientApplication>(fixture, (env) {
        user = _User(env);
        return user.app;
      }, onBeforeExpect: (step) => user.act(step));
      addTearDown(user.app.dispose);

      expect(_toolCall(user, 'call_1').status, ToolCallStatus.failed);
    },
    skip: _cancelledToolCallSkip,
  );
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
          app.sendPrompt(
            SendPromptCommand(
              sessionId: _session.id,
              prompt: [
                for (final block in params['prompt']! as List<Object?>)
                  ContentBlock.text(
                    text: (block! as Map<String, Object?>)['text']! as String,
                  ),
              ],
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
    expect(result.environment!.terminal.started.single.command, '/bin/sh');
    // The status of call_1 is checked by the skipped test below.
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
