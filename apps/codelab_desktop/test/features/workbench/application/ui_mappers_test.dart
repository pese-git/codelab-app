// Тесты мапперов представлений kit в модели `codelab_ui` (tasks 7.1, design D10
// change `extract-acp-client-kit`): значения совпадают с теми, что
// `CodeLabShellCubit` строил до разделения на Cubit-ы.

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:codelab_desktop/features/workbench/application/ui_mappers.dart';
import 'package:fluent_ui/fluent_ui.dart' show FluentIcons;
import 'package:flutter_test/flutter_test.dart';

import '../../../support/transcript_rows.dart';

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
        CodeLabConnectionStatus.disconnected,
        CodeLabConnectionStatus.connecting,
        CodeLabConnectionStatus.reconnecting,
        CodeLabConnectionStatus.connected,
        CodeLabConnectionStatus.failed,
      ],
    );
  });

  group('sessionListItemOf', () {
    test('an untitled session without prompts is "New session", not its '
        'id', () {
      final item = sessionListItemOf(
        const AcpSession(id: SessionId('session-1'), cwd: '/work'),
      );

      expect(item.id, 'session-1');
      expect(item.title, 'New session');
      expect(item.subtitle, '/work');
      expect(item.updatedLabel, 'Active');
      expect(item.status, CodeLabSessionStatus.idle);
    });

    test('an untitled session is named by its first prompt, collapsed to one '
        'line and shortened', () {
      AcpSession withPrompt(String text) => AcpSession(
        id: const SessionId('s'),
        cwd: '/work',
        turns: [
          PromptTurn(
            id: const PromptTurnId('t1'),
            sessionId: const SessionId('s'),
            prompt: [ContentBlock.text(text: text)],
          ),
        ],
      );

      expect(
        sessionListItemOf(withPrompt('  Fix the\n failing   tests ')).title,
        'Fix the failing tests',
      );
      final long = sessionListItemOf(withPrompt('a' * 80)).title;
      expect(long, '${'a' * 60}…');
    });

    test('a title is trimmed; lifecycle maps to the sidebar badge', () {
      CodeLabSessionListItem of(SessionLifecycleStatus status) =>
          sessionListItemOf(
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
            SessionLifecycleStatus.active => CodeLabSessionStatus.idle,
            SessionLifecycleStatus.runningTurn ||
            SessionLifecycleStatus.cancellingTurn =>
              CodeLabSessionStatus.running,
            SessionLifecycleStatus.awaitingApproval =>
              CodeLabSessionStatus.awaitingApproval,
            SessionLifecycleStatus.failed => CodeLabSessionStatus.failed,
          },
        ),
      );
    });
  });

  test('an agent session that is not open is a not loaded row', () {
    final row = sessionListItemOfSummary(
      SessionSummaryView(
        id: const SessionId('s-old'),
        cwd: '/work',
        status: SessionStatusView.notLoaded,
        title: '  Fix tests  ',
        updatedAt: DateTime(2026, 10, 26, 9, 5),
      ),
    );

    expect(row.id, 's-old');
    expect(row.title, 'Fix tests');
    expect(row.status, CodeLabSessionStatus.notLoaded);
    expect(row.subtitle, '/work');
    expect(row.updatedLabel, 'Updated 2026-10-26 09:05');
    expect(
      sessionListItemOfSummary(
        const SessionSummaryView(
          id: SessionId('s-x'),
          cwd: '/work',
          status: SessionStatusView.notLoaded,
        ),
      ).title,
      'Session s-x',
    );
  });

  group('transcriptRowsOf', () {
    test('items get positional ids and their own row kinds', () {
      final rows = transcriptRowsOf(
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
              rawInput: {'command': 'dart test'},
            ),
          ),
        ],
        cwd: '/work',
        approvalsEnabled: true,
        onApprovalSelected: (_, _) {},
      );

      expect(rows.map((row) => row.id), [
        'prompt-1',
        'agent-2',
        'thought-3',
        'notice-4',
        'prompt-error-5',
        'tool-6',
      ]);
      expect(rows.map((row) => row.kind), [
        'user',
        'agent',
        'thought',
        'notice',
        'notice',
        'tool',
      ]);
      final error = rows[4] as CodeLabNoticeRow;
      expect(error.severity, CodeLabNoticeSeverity.error);
      expect(error.title, 'The agent could not complete the turn');
      expect(error.body, 'Failed to send prompt: agent crashed');
      expect(
        (rows[3] as CodeLabNoticeRow).severity,
        CodeLabNoticeSeverity.info,
      );
      final tool = rows.last as CodeLabToolCallRow;
      expect(tool.label, 'Run');
      expect(tool.detail, 'dart test');
      expect(tool.status, CodeLabToolCallStatus.running);
    });

    test('only the last thought of a running turn is streaming', () {
      List<CodeLabTranscriptRow> rows({
        required bool isRunning,
        bool last = true,
      }) => transcriptRowsOf(
        [
          const TranscriptItem.thought(id: 't1/thought-0', text: 'hm'),
          if (!last)
            const TranscriptItem.agentText(id: 't1/text-1', text: 'ok'),
        ],
        cwd: '/work',
        isRunning: isRunning,
        approvalsEnabled: true,
        onApprovalSelected: (_, _) {},
      );

      expect(
        (rows(isRunning: true).first as CodeLabThoughtRow).streaming,
        isTrue,
      );
      expect(
        (rows(isRunning: true, last: false).first as CodeLabThoughtRow)
            .streaming,
        isFalse,
      );
      expect(
        (rows(isRunning: false).first as CodeLabThoughtRow).streaming,
        isFalse,
      );
    });

    test('the approval card is titled by the kind of the call', () {
      expect(approvalTitleOf(ToolKind.execute), 'Run a command?');
      expect(approvalTitleOf(ToolKind.edit), 'Edit a file?');
      expect(approvalTitleOf(ToolKind.fetch), 'Fetch a URL?');
      expect(approvalTitleOf(ToolKind.other), 'Allow this tool call?');
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

      final entries = transcriptRowsOf(
        const [
          TranscriptItem.toolCall(
            id: 't1/tool-call-1',
            toolCallId: ToolCallId('call-1'),
            title: 'Clean',
            details: ToolCallView(
              kind: ToolKind.execute,
              status: ToolCallStatusView.queued,
            ),
            approval: pending,
          ),
        ],
        cwd: '/work',
        approvalsEnabled: false,
        onApprovalSelected: (approval, optionId) =>
            chosen.add((approval.approvalId, approval.sessionId, optionId)),
      );

      final approval =
          entries.single.approval! as CodeLabTranscriptApprovalPending;
      expect(approval.title, 'Run a command?');
      expect(approval.risk, CodeLabApprovalRisk.shell);
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
        CodeLabApprovalOptionKind.allowOnce,
        CodeLabApprovalOptionKind.rejectOnce,
      ]);
      expect(approval.options.map((option) => option.tone), [
        CodeLabTone.success,
        CodeLabTone.danger,
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

    test('a detached session is a warning, a new session a neutral note', () {
      final rows = transcriptRowsOf(
        const [
          TranscriptItem.notice(
            id: 's/detached',
            kind: NoticeKind.detached,
            text: 'The agent cannot restore sessions after reconnecting.',
          ),
          TranscriptItem.notice(
            id: 's/reconnected',
            kind: NoticeKind.reconnected,
            text:
                'The agent cannot restore sessions; a new session was started.',
          ),
        ],
        cwd: '/work',
        approvalsEnabled: true,
        onApprovalSelected: (_, _) {},
      ).cast<CodeLabNoticeRow>();

      expect(rows.map((row) => row.id), [
        'session-notice-1',
        'session-notice-2',
      ]);
      expect(rows.map((row) => row.severity), [
        CodeLabNoticeSeverity.warning,
        CodeLabNoticeSeverity.info,
      ]);
      expect(
        rows.first.body,
        'The agent cannot restore sessions after reconnecting.',
      );
    });

    test('a resolved approval is a compact label', () {
      final entries = transcriptRowsOf(
        const [
          TranscriptItem.toolCall(
            id: 't1/tool-call-1',
            toolCallId: ToolCallId('call-1'),
            title: 'Clean',
            approval: ResolvedApprovalView(
              label: 'Allowed once',
              outcome: ApprovalOutcomeView.allowed,
            ),
          ),
        ],
        cwd: '/work',
        approvalsEnabled: true,
        onApprovalSelected: (_, _) {},
      );

      final resolved =
          entries.single.approval! as CodeLabTranscriptApprovalResolved;
      expect(resolved.label, 'Allowed once');
      expect(resolved.outcome, CodeLabApprovalOutcome.allowed);
    });

    test('a cancelled approval keeps its cancelled outcome', () {
      final entries = transcriptRowsOf(
        const [
          TranscriptItem.toolCall(
            id: 't1/tool-call-1',
            toolCallId: ToolCallId('call-1'),
            title: 'Clean',
            approval: ResolvedApprovalView(
              label: 'Cancelled',
              outcome: ApprovalOutcomeView.cancelled,
            ),
          ),
        ],
        cwd: '/work',
        approvalsEnabled: true,
        onApprovalSelected: (_, _) {},
      );

      expect(
        (entries.single.approval! as CodeLabTranscriptApprovalResolved).outcome,
        CodeLabApprovalOutcome.cancelled,
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
      CodeLabConfigOption(
        id: 'model',
        name: 'Model',
        description: 'Which model answers',
        currentValue: 'gpt-5',
        values: [
          CodeLabConfigOptionValue(value: 'gpt-5', name: 'GPT-5'),
          CodeLabConfigOptionValue(
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
        CodeLabCommandAction(
          id: 'agent-plan',
          label: 'plan',
          slashCommand: '/plan',
          description: 'Plan first',
          icon: FluentIcons.robot,
          source: CodeLabCommandSource.agent,
          hint: 'what to plan',
        ),
      ],
    );
  });

  group('planEntriesOf', () {
    test('an empty plan is null', () {
      expect(planEntriesOf(const []), isNull);
    });

    test('entries keep their order, status and priority', () {
      final plan = planEntriesOf(const [
        PlanEntryView(
          content: 'write tests',
          status: PlanEntryStatus.inProgress,
          priority: PlanEntryPriority.high,
        ),
        PlanEntryView(
          content: 'ship',
          status: PlanEntryStatus.completed,
          priority: PlanEntryPriority.medium,
        ),
      ])!;

      expect(plan.map((entry) => entry.content), ['write tests', 'ship']);
      expect(plan.map((entry) => entry.status), [
        CodeLabPlanEntryStatus.inProgress,
        CodeLabPlanEntryStatus.completed,
      ]);
      expect(plan.map((entry) => entry.priority), [
        CodeLabPlanEntryPriority.high,
        CodeLabPlanEntryPriority.medium,
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

  group(
    'palette catalog (change add-command-palette-agent-commands, D2–D5)',
    () {
      final catalog = paletteCatalogOf(const [
        AgentCommandView(
          name: 'compact',
          description: 'Compact the conversation',
        ),
        AgentCommandView(
          name: 'plan',
          description: 'Create a plan',
          hint: 'what to plan',
        ),
      ]);

      test('the six app commands are the host commands of the catalog', () {
        expect(
          paletteActionsOf(paletteCatalogOf(const [])),
          CodeLabCommandAction.defaults,
        );
      });

      test('agent commands replace the client stubs of the same name; the '
          'remaining stub stays unavailable', () {
        final ids = [for (final action in paletteActionsOf(catalog)) action.id];

        expect(ids, [
          'new',
          'permissions',
          'logs',
          'reconnect',
          'agent-compact',
          'agent-plan',
        ]);
        expect(
          paletteActionsOf(
            catalog,
          ).firstWhere((action) => action.id == 'permissions').isAvailable,
          isFalse,
        );
        expect(
          paletteActionsOf(catalog).last,
          isA<CodeLabCommandAction>()
              .having((a) => a.source, 'source', CodeLabCommandSource.agent)
              .having((a) => a.hint, 'hint', 'what to plan'),
        );
      });

      test('search maps the catalog ranking to palette actions', () {
        expect(
          [
            for (final action in searchPaletteActions(catalog, '/cpt'))
              action.id,
          ],
          ['agent-compact'],
        );
        expect(searchPaletteActions(catalog, '/pl').first.id, 'agent-plan');
      });
    },
  );

  group('turnStateOf', () {
    SessionView view(SessionStatusView status, {bool pending = false}) =>
        SessionView(
          revision: 1,
          status: status,
          pendingApprovals: [
            if (pending)
              const PendingApprovalView(
                approvalId: ApprovalRequestId('permission-1'),
                sessionId: SessionId('s'),
                risk: ApprovalRiskLevel.shell,
                options: [_allowOnce],
                focused: true,
              ),
          ],
        );

    test('a busy session gets a chip, a free one none', () {
      expect(
        turnStateOf(view(SessionStatusView.running)),
        CodeLabTurnState.running,
      );
      expect(
        turnStateOf(view(SessionStatusView.running, pending: true)),
        CodeLabTurnState.awaitingApproval,
      );
      expect(
        turnStateOf(view(SessionStatusView.cancelling)),
        CodeLabTurnState.cancelling,
      );
      expect(turnStateOf(view(SessionStatusView.idle)), isNull);
      expect(turnStateOf(view(SessionStatusView.detached)), isNull);
      expect(turnStateOf(null), isNull);
    });
  });
}
