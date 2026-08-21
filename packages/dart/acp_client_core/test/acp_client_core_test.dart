import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('exports core package boundaries', () {
    expect(acpClientCorePackageName, 'acp_client_core');
    expect(acpProtocolPackageName, 'acp_protocol');
    expect(acpTransportsPackageName, 'acp_transports');
  });

  test('models initialized connection state with agent capabilities', () {
    const state = ClientConnectionState.ready(
      protocolVersion: ProtocolVersion(1),
      agentInfo: Implementation(name: 'agent', version: '0.1.0'),
      capabilities: AgentCapabilities(loadSession: true),
    );

    expect(
      state,
      isA<ClientConnectionReady>()
          .having(
            (state) => state.protocolVersion,
            'protocolVersion',
            const ProtocolVersion(1),
          )
          .having((state) => state.agentInfo?.name, 'agent name', 'agent')
          .having(
            (state) => state.capabilities.loadSession,
            'loadSession',
            isTrue,
          ),
    );
  });

  test('models prompt turn terminal states and active session turn', () {
    const sessionId = SessionId('session-1');
    const completed = PromptTurn(
      id: PromptTurnId('turn-1'),
      sessionId: sessionId,
      prompt: [ContentBlock.text(text: 'done')],
      status: PromptTurnStatus.completed,
      stopReason: StopReason.endTurn,
    );
    const running = PromptTurn(
      id: PromptTurnId('turn-2'),
      sessionId: sessionId,
      prompt: [ContentBlock.text(text: 'continue')],
      status: PromptTurnStatus.running,
    );

    const session = AcpSession(
      id: sessionId,
      cwd: '/workspace',
      turns: [completed, running],
    );

    expect(completed.isTerminal, isTrue);
    expect(running.isTerminal, isFalse);
    expect(session.activeTurn, running);
  });

  test('models tool call records from protocol tool calls', () {
    final record = ToolCallRecord.fromToolCall(
      const ToolCall(
        toolCallId: ToolCallId('tool-1'),
        title: 'Read file',
        kind: ToolKind.read,
        status: ToolCallStatus.inProgress,
        locations: [ToolCallLocation(path: '/workspace/README.md', line: 3)],
      ),
      riskLevel: ApprovalRiskLevel.readOnly,
    );

    expect(record.id, const ToolCallId('tool-1'));
    expect(record.kind, ToolKind.read);
    expect(record.status, ToolCallStatus.inProgress);
    expect(record.riskLevel, ApprovalRiskLevel.readOnly);
    expect(record.locations.single.path, '/workspace/README.md');
  });

  test('classifies approval risk levels for tool calls', () {
    expect(
      ApprovalPolicy.classifyToolCall(
        const ToolCall(
          toolCallId: ToolCallId('read-1'),
          title: 'Read file',
          kind: ToolKind.read,
        ),
      ),
      ApprovalRiskLevel.readOnly,
    );
    expect(
      ApprovalPolicy.classifyToolCall(
        const ToolCall(
          toolCallId: ToolCallId('edit-1'),
          title: 'Patch config',
          kind: ToolKind.edit,
          content: [
            ToolCallContent.diff(
              diff: Diff(path: '/workspace/config.json', newText: '{}'),
            ),
          ],
        ),
      ),
      ApprovalRiskLevel.localWrite,
    );
    expect(
      ApprovalPolicy.classifyToolCall(
        const ToolCall(
          toolCallId: ToolCallId('fetch-1'),
          title: 'Fetch API',
          kind: ToolKind.fetch,
          rawInput: {'url': 'https://example.com/data.json'},
        ),
      ),
      ApprovalRiskLevel.network,
    );
    expect(
      ApprovalPolicy.classifyToolCall(
        const ToolCall(
          toolCallId: ToolCallId('shell-1'),
          title: 'Run tests',
          kind: ToolKind.execute,
        ),
      ),
      ApprovalRiskLevel.shell,
    );
    expect(
      ApprovalPolicy.classifyToolCall(
        const ToolCall(
          toolCallId: ToolCallId('reset-1'),
          title: 'Run git reset --hard',
          kind: ToolKind.execute,
        ),
      ),
      ApprovalRiskLevel.destructive,
    );
  });

  test('decides permission mode behavior from risk levels', () {
    expect(
      ApprovalPolicy.decidePermission(
        mode: PermissionMode.readOnly,
        riskLevel: ApprovalRiskLevel.readOnly,
      ),
      PermissionModeDecision.allowWithoutApproval,
    );
    expect(
      ApprovalPolicy.decidePermission(
        mode: PermissionMode.readOnly,
        riskLevel: ApprovalRiskLevel.localWrite,
      ),
      PermissionModeDecision.requireExplicitApproval,
    );
    expect(
      ApprovalPolicy.decidePermission(
        mode: PermissionMode.ask,
        riskLevel: ApprovalRiskLevel.network,
      ),
      PermissionModeDecision.requireExplicitApproval,
    );
    expect(
      ApprovalPolicy.decidePermission(
        mode: PermissionMode.plan,
        riskLevel: ApprovalRiskLevel.localWrite,
      ),
      PermissionModeDecision.unavailable,
    );
    expect(
      ApprovalPolicy.decidePermission(
        mode: PermissionMode.autoEdits,
        riskLevel: ApprovalRiskLevel.localWrite,
      ),
      PermissionModeDecision.allowWithoutApproval,
    );
    expect(
      ApprovalPolicy.requiresExplicitApproval(
        mode: PermissionMode.autoEdits,
        riskLevel: ApprovalRiskLevel.shell,
      ),
      isTrue,
    );
  });

  test('models approval request resolution and diagnostics', () {
    const approval = ApprovalRequest(
      id: ApprovalRequestId('approval-1'),
      sessionId: SessionId('session-1'),
      turnId: PromptTurnId('turn-1'),
      toolCall: ToolCallRecord(
        id: ToolCallId('tool-1'),
        title: 'Run command',
        kind: ToolKind.execute,
        riskLevel: ApprovalRiskLevel.shell,
      ),
      options: [
        PermissionOption(
          optionId: PermissionOptionId('allow-once'),
          name: 'Allow once',
          kind: PermissionOptionKind.allowOnce,
        ),
      ],
    );
    const resolved = ApprovalRequest(
      id: ApprovalRequestId('approval-1'),
      sessionId: SessionId('session-1'),
      turnId: PromptTurnId('turn-1'),
      toolCall: ToolCallRecord(
        id: ToolCallId('tool-1'),
        title: 'Run command',
        kind: ToolKind.execute,
        riskLevel: ApprovalRiskLevel.shell,
      ),
      options: [
        PermissionOption(
          optionId: PermissionOptionId('allow-once'),
          name: 'Allow once',
          kind: PermissionOptionKind.allowOnce,
        ),
      ],
      status: ApprovalStatus.selected,
      selectedOptionId: PermissionOptionId('allow-once'),
    );
    const diagnostic = DiagnosticEntry(
      id: DiagnosticEntryId('diagnostic-1'),
      message: 'stderr line',
      severity: DiagnosticSeverity.warning,
      source: 'stderr',
    );

    expect(approval.isResolved, isFalse);
    expect(resolved.isResolved, isTrue);
    expect(resolved.selectedOptionId, const PermissionOptionId('allow-once'));
    expect(diagnostic.severity, DiagnosticSeverity.warning);
    expect(diagnostic.source, 'stderr');
  });
}
