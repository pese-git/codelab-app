// Тесты мапперов представлений kit в модели `acp_ui` (tasks 7.1, design D10
// change `extract-acp-client-kit`): значения совпадают с теми, что
// `CodeLabShellCubit` строил до разделения на Cubit-ы.

import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_client_kit/acp_client_kit.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:codelab_app/features/workbench/application/ui_mappers.dart';
import 'package:fluent_ui/fluent_ui.dart' show FluentIcons;
import 'package:flutter_test/flutter_test.dart';

const _allowOnce = PermissionOption(
  optionId: PermissionOptionId('allow-once'),
  name: 'Allow once',
  kind: PermissionOptionKind.allowOnce,
);
const _rejectOnce = PermissionOption(
  optionId: PermissionOptionId('reject-once'),
  name: 'Reject',
  kind: PermissionOptionKind.rejectOnce,
);

void main() {
  test('connection views map to the connection status badge', () {
    expect(
      [
        const ConnectionView.disconnected(),
        const ConnectionView.connecting(),
        const ConnectionView.reconnecting(attempt: 1),
        const ConnectionView.connected(),
        ConnectionView.failed(
          reason: ConnectionFailureReason.values.first,
          message: 'boom',
        ),
      ].map(connectionStatusOf),
      [
        AcpConnectionStatus.disconnected,
        AcpConnectionStatus.connecting,
        AcpConnectionStatus.reconnecting,
        AcpConnectionStatus.connected,
        AcpConnectionStatus.failed,
      ],
    );
  });

  group('sessionListItemOf', () {
    test('an untitled session is "Session <id>" with its cwd', () {
      final item = sessionListItemOf(
        const AcpSession(id: SessionId('session-1'), cwd: '/work'),
      );

      expect(item.id, 'session-1');
      expect(item.title, 'Session session-1');
      expect(item.subtitle, '/work');
      expect(item.updatedLabel, 'Active');
      expect(item.status, AcpSessionStatus.idle);
    });

    test('a title is trimmed; lifecycle maps to the sidebar badge', () {
      AcpSessionListItem of(SessionLifecycleStatus status) => sessionListItemOf(
        AcpSession(
          id: const SessionId('s'),
          cwd: '/work',
          title: '  Fix tests  ',
          status: status,
        ),
      );

      expect(of(SessionLifecycleStatus.active).title, 'Fix tests');
      expect(
        SessionLifecycleStatus.values.map((status) => of(status).status),
        SessionLifecycleStatus.values.map(
          (status) => switch (status) {
            SessionLifecycleStatus.idle ||
            SessionLifecycleStatus.active => AcpSessionStatus.idle,
            SessionLifecycleStatus.runningTurn ||
            SessionLifecycleStatus.cancellingTurn => AcpSessionStatus.running,
            SessionLifecycleStatus.awaitingApproval =>
              AcpSessionStatus.awaitingApproval,
            SessionLifecycleStatus.failed => AcpSessionStatus.failed,
          },
        ),
      );
    });
  });

  group('transcriptEntriesOf', () {
    test('items get the positional ids, kinds and titles of the old '
        'transcript', () {
      final entries = transcriptEntriesOf(
        const [
          TranscriptItem.user(id: 't1/user', text: 'hello'),
          TranscriptItem.agentText(id: 't1/text-0', text: 'hi'),
          TranscriptItem.thought(id: 't1/thought-0', text: 'thinking'),
          TranscriptItem.notice(
            id: 't1/notice',
            kind: NoticeKind.emptyTurn,
            text: 'Completed with stopReason end_turn',
          ),
          TranscriptItem.notice(
            id: 't2/notice',
            kind: NoticeKind.error,
            text: 'Failed to send prompt: agent crashed',
          ),
          TranscriptItem.toolCall(
            id: 't3/tool-call-1',
            toolCallId: ToolCallId('call-1'),
            title: 'Run tests',
            details: ToolCallView(
              kind: ToolKind.execute,
              status: ToolCallStatusView.running,
              command: 'dart test',
            ),
          ),
        ],
        cwd: '/work',
        approvalsEnabled: true,
        onApprovalSelected: (_, _) {},
      );

      expect(entries.map((entry) => entry.id), [
        'prompt-1',
        'agent-2',
        'agent-3',
        'agent-4',
        'prompt-error-5',
        'tool-6',
      ]);
      expect(entries.map((entry) => entry.kind), [
        AcpTranscriptEntryKind.user,
        AcpTranscriptEntryKind.agent,
        AcpTranscriptEntryKind.agent,
        AcpTranscriptEntryKind.agent,
        AcpTranscriptEntryKind.diagnostic,
        AcpTranscriptEntryKind.toolCall,
      ]);
      expect(entries.map((entry) => entry.title), [
        'You',
        'Agent',
        'Agent',
        'Agent',
        'Prompt failed',
        'Run tests',
      ]);
      expect(entries[4].body, 'Failed to send prompt: agent crashed');
      final tool = entries.last.toolCall!;
      expect(tool.name, 'execute');
      expect(tool.status, AcpToolCallStatus.running);
      expect(tool.detail, 'dart test');
    });

    test('a pending approval is interactive and answers through the '
        'callback with its own identity', () {
      const pending = PendingApprovalView(
        approvalId: ApprovalRequestId('permission-1'),
        sessionId: SessionId('session-1'),
        risk: ApprovalRiskLevel.shell,
        command: 'rm -rf build',
        rawInput: {'command': 'rm -rf build', 'api_key': 'sk-123'},
        options: [_allowOnce, _rejectOnce],
        focused: true,
      );
      final chosen = <(ApprovalRequestId, SessionId, String)>[];

      final entries = transcriptEntriesOf(
        const [
          TranscriptItem.toolCall(
            id: 't1/tool-call-1',
            toolCallId: ToolCallId('call-1'),
            title: 'Clean',
            approval: pending,
          ),
        ],
        cwd: '/work',
        approvalsEnabled: false,
        onApprovalSelected: (approval, optionId) =>
            chosen.add((approval.approvalId, approval.sessionId, optionId)),
      );

      final approval = entries.single.approval! as AcpTranscriptApprovalPending;
      expect(approval.risk, AcpApprovalRisk.shell);
      expect(approval.command, 'rm -rf build');
      expect(approval.cwd, '/work');
      expect(approval.rawInput, contains('rm -rf build'));
      expect(approval.rawInput, isNot(contains('sk-123')));
      expect(approval.enabled, isFalse);
      expect(approval.shortcutsEnabled, isTrue);
      expect(approval.options.map((option) => option.id), [
        'allow-once',
        'reject-once',
      ]);
      expect(approval.options.map((option) => option.kind), [
        AcpApprovalOptionKind.allowOnce,
        AcpApprovalOptionKind.rejectOnce,
      ]);
      expect(approval.options.map((option) => option.tone), [
        AcpTone.success,
        AcpTone.danger,
      ]);

      approval.onOptionSelected('reject-once');
      expect(chosen, [
        (
          const ApprovalRequestId('permission-1'),
          const SessionId('session-1'),
          'reject-once',
        ),
      ]);
    });

    test('a resolved approval is a compact label', () {
      final entries = transcriptEntriesOf(
        const [
          TranscriptItem.toolCall(
            id: 't1/tool-call-1',
            toolCallId: ToolCallId('call-1'),
            title: 'Clean',
            approval: ResolvedApprovalView(label: 'Allowed once'),
          ),
        ],
        cwd: '/work',
        approvalsEnabled: true,
        onApprovalSelected: (_, _) {},
      );

      expect(
        (entries.single.approval! as AcpTranscriptApprovalResolved).label,
        'Allowed once',
      );
    });
  });

  test('config options keep their ids, names and values', () {
    final options = configOptionsOf(const [
      ConfigOptionView(
        id: 'model',
        name: 'Model',
        description: 'Which model answers',
        currentValue: 'gpt-5',
        values: [
          ConfigOptionValueView(value: 'gpt-5', name: 'GPT-5'),
          ConfigOptionValueView(
            value: 'gpt-4',
            name: 'GPT-4',
            description: 'Older',
          ),
        ],
      ),
    ]);

    expect(options, const [
      AcpConfigOption(
        id: 'model',
        name: 'Model',
        description: 'Which model answers',
        currentValue: 'gpt-5',
        values: [
          AcpConfigOptionValue(value: 'gpt-5', name: 'GPT-5'),
          AcpConfigOptionValue(
            value: 'gpt-4',
            name: 'GPT-4',
            description: 'Older',
          ),
        ],
      ),
    ]);
  });

  test('agent commands become agent palette actions', () {
    expect(
      agentCommandsOf(const [
        AgentCommandView(
          name: 'plan',
          description: 'Plan first',
          hint: 'what to plan',
        ),
      ]),
      const [
        AcpCommandAction(
          id: 'agent-plan',
          label: 'plan',
          slashCommand: '/plan',
          description: 'Plan first',
          icon: FluentIcons.robot,
          source: AcpCommandSource.agent,
          hint: 'what to plan',
        ),
      ],
    );
  });

  group('currentPlanOf', () {
    PromptTurn turn(String id, List<SessionUpdate> updates) => PromptTurn(
      id: PromptTurnId(id),
      sessionId: const SessionId('s'),
      prompt: const [ContentBlock.text(text: 'go')],
      updates: updates,
    );

    test('no plan update is null', () {
      expect(
        currentPlanOf(
          AcpSession(
            id: const SessionId('s'),
            cwd: '/work',
            turns: [turn('turn-1', const [])],
          ),
        ),
        isNull,
      );
    });

    test('the last plan across all turns wins', () {
      final plan = currentPlanOf(
        AcpSession(
          id: const SessionId('s'),
          cwd: '/work',
          turns: [
            turn('turn-1', const [
              SessionUpdate.plan(
                entries: [
                  PlanEntry(
                    content: 'old',
                    priority: PlanEntryPriority.low,
                    status: PlanEntryStatus.pending,
                  ),
                ],
              ),
            ]),
            turn('turn-2', const [
              SessionUpdate.plan(
                entries: [
                  PlanEntry(
                    content: 'write tests',
                    priority: PlanEntryPriority.high,
                    status: PlanEntryStatus.inProgress,
                  ),
                  PlanEntry(
                    content: 'ship',
                    priority: PlanEntryPriority.medium,
                    status: PlanEntryStatus.completed,
                  ),
                ],
              ),
            ]),
            turn('turn-3', const []),
          ],
        ),
      )!;

      expect(plan.map((entry) => entry.content), ['write tests', 'ship']);
      expect(plan.map((entry) => entry.status), [
        AcpPlanEntryStatus.inProgress,
        AcpPlanEntryStatus.completed,
      ]);
      expect(plan.map((entry) => entry.priority), [
        AcpPlanEntryPriority.high,
        AcpPlanEntryPriority.medium,
      ]);
    });
  });

  test('queued prompts keep their ids and texts', () {
    final queued = queuedPromptsOf(const [
      QueuedPrompt(id: 'queued-1', text: 'first'),
      QueuedPrompt(id: 'queued-2', text: 'second'),
    ]);

    expect(queued.map((prompt) => (prompt.id, prompt.content)), [
      ('queued-1', 'first'),
      ('queued-2', 'second'),
    ]);
  });

  test('recent projects are sorted most recently opened first', () {
    final recents = recentProjectsOf([
      RecentProject(path: '/old', lastOpenedAt: DateTime.utc(2026)),
      RecentProject(path: '/new', lastOpenedAt: DateTime.utc(2026, 3)),
      RecentProject(path: '/mid', lastOpenedAt: DateTime.utc(2026, 2)),
    ]);

    expect(recents.map((project) => project.path), ['/new', '/mid', '/old']);
  });
}
