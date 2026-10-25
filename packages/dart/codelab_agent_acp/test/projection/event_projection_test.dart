import 'package:acp_protocol/acp_protocol.dart' as acp;
import 'package:codelab_agent_acp/src/connection/acp_error.dart';
import 'package:codelab_agent_acp/src/event_projection.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/pairing.dart';
import 'package:test/test.dart';

import '../support/server_harness.dart' show scriptedModel;

/// Таблица §13.7 строка за строкой и итог хода §13.8 (задача 4.1; ACP-1,
/// ACP-5, ACP-7).
void main() {
  const s = SessionId('sess_1');
  final options = [
    acp.SessionConfigOption.select(
      id: const acp.SessionConfigId('mode'),
      name: 'Mode',
      currentValue: const acp.SessionConfigValueId('plan'),
      options: const [],
    ),
  ];

  List<Map<String, Object?>> project(AgentEvent event) => [
    for (final update in projectEvent(event, configOptions: () => options))
      update.toJson(),
  ];

  AssistantMessage answer([List<ContentBlock> content = const []]) =>
      AssistantMessage(
        content: content,
        model: scriptedModel,
        usage: Usage.zero,
        stopReason: StopReason.stop,
        timestamp: DateTime.utc(2026),
      );

  group('§13.7', () {
    test('MessageDelta → agent_message_chunk', () {
      expect(project(MessageDelta(s, delta: 'Hel', partial: answer())), [
        {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'Hel'},
        },
      ]);
    });

    test('ThoughtDelta → agent_thought_chunk', () {
      expect(project(ThoughtDelta(s, delta: 'hmm', partial: answer())), [
        {
          'sessionUpdate': 'agent_thought_chunk',
          'content': {'type': 'text', 'text': 'hmm'},
        },
      ]);
    });

    test('ToolCallStarted → tool_call pending with rawInput and locations', () {
      final event = ToolCallStarted(
        s,
        toolCallId: 'call_1',
        tool: 'read',
        kind: ToolKind.read,
        title: 'Read README.md',
        input: const {'path': 'README.md'},
        locations: const [Location('/work/demo/README.md', line: 1)],
      );

      expect(project(event), [
        {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call_1',
          'title': 'Read README.md',
          'kind': 'read',
          'status': 'pending',
          'locations': [
            {'path': '/work/demo/README.md', 'line': 1},
          ],
          'rawInput': {'path': 'README.md'},
        },
      ]);
    });

    test('in_progress comes from markInProgress', () {
      expect(inProgressUpdate('call_1').toJson(), {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call_1',
        'status': 'in_progress',
      });
    });

    test('ToolCallProgress → content as is, terminal embedded', () {
      final event = ToolCallProgress(
        s,
        toolCallId: 'call_3',
        content: const [
          ToolCallBlock(TextContent('chunk')),
          ToolCallTerminal('term_7'),
        ],
      );

      expect(project(event), [
        {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call_3',
          'content': [
            {
              'type': 'content',
              'content': {'type': 'text', 'text': 'chunk'},
            },
            {'type': 'terminal', 'terminalId': 'term_7'},
          ],
        },
      ]);
    });

    test('ToolCallFinished completed: content and one diff per file', () {
      final event = ToolCallFinished(
        s,
        toolCallId: 'call_2',
        outcome: ToolOutcome.completed,
        content: const [TextContent('Edited README.md')],
        diffs: const [
          FileDiff(path: '/work/demo/README.md', oldText: 'a', newText: 'b'),
        ],
      );

      expect(project(event), [
        {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call_2',
          'status': 'completed',
          'content': [
            {
              'type': 'content',
              'content': {'type': 'text', 'text': 'Edited README.md'},
            },
            {
              'type': 'diff',
              'path': '/work/demo/README.md',
              'oldText': 'a',
              'newText': 'b',
            },
          ],
        },
      ]);
    });

    test('failed, cancelled, rejected and interrupted are failed', () {
      Map<String, Object?> finish(
        ToolOutcome outcome, {
        bool interrupted = false,
      }) => project(
        ToolCallFinished(
          s,
          toolCallId: 'c',
          outcome: outcome,
          content: const [TextContent('why')],
          interrupted: interrupted,
        ),
      ).single;

      expect(finish(ToolOutcome.failed), {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'c',
        'status': 'failed',
        'content': [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': 'why'},
          },
        ],
      });
      for (final (outcome, name) in [
        (ToolOutcome.cancelled, 'cancelled'),
        (ToolOutcome.rejected, 'rejected'),
      ]) {
        final update = finish(outcome);
        expect(update['status'], 'failed');
        expect(update['_meta'], {
          'codelab': {'outcome': name},
        });
      }
      expect(finish(ToolOutcome.failed, interrupted: true)['_meta'], {
        'codelab': {'outcome': 'interrupted'},
      });
    });

    test('PlanUpdated → plan with every entry', () {
      final event = PlanUpdated(
        s,
        entries: const [
          PlanEntry(
            content: 'Read',
            priority: PlanPriority.high,
            status: PlanStatus.completed,
          ),
          PlanEntry(
            content: 'Edit',
            priority: PlanPriority.medium,
            status: PlanStatus.inProgress,
          ),
        ],
      );

      expect(project(event), [
        {
          'sessionUpdate': 'plan',
          'entries': [
            {'content': 'Read', 'priority': 'high', 'status': 'completed'},
            {'content': 'Edit', 'priority': 'medium', 'status': 'in_progress'},
          ],
        },
      ]);
    });

    test('ModeChanged → current_mode_update and config_option_update', () {
      final updates = project(const ModeChanged(s, mode: ModeId.plan));

      expect(updates, [
        {'sessionUpdate': 'current_mode_update', 'currentModeId': 'plan'},
        {
          'sessionUpdate': 'config_option_update',
          'configOptions': [for (final o in options) o.toJson()],
        },
      ]);
    });

    test('SessionTitleChanged → session_info_update', () {
      final event = SessionTitleChanged(
        s,
        title: 'Fix README',
        updatedAt: DateTime.utc(2026, 10, 25, 12),
      );

      expect(project(event), [
        {
          'sessionUpdate': 'session_info_update',
          'title': 'Fix README',
          'updatedAt': '2026-10-25T12:00:00.000Z',
        },
      ]);
    });

    test('rows "not sent" produce no frame', () {
      final silent = <AgentEvent>[
        TurnStarted(s, turnId: const TurnId('t'), input: const []),
        const StepStarted(s, stepIndex: 0),
        ModelRequested(
          s,
          model: scriptedModel,
          estimatedTokens: 0,
          messageCount: 1,
        ),
        MessageStarted(s, message: answer()),
        MessageEnded(s, message: answer()),
        ToolPairingRepaired(s, report: PairingReport(const ['moved c'])),
        StepEnded(
          s,
          result: StepResult(
            stepIndex: 0,
            response: answer(),
            results: const [],
            usage: Usage.zero,
          ),
        ),
        const AgentError(
          s,
          cls: AgentErrorClass.provider,
          message: 'boom',
          errorClass: LlmErrorClass.server,
        ),
        const ContextCompacted(s, tokensBefore: 10, tokensAfter: 5),
        const TurnEnded(s, reason: TurnEndReason.completed, usage: Usage.zero),
      ];
      for (final event in silent) {
        expect(project(event), isEmpty, reason: '${event.runtimeType}');
      }
    });
  });

  group('§13.8', () {
    Map<String, Object?> respond(
      TurnEndReason reason, {
      BudgetLimit? budget,
      bool cancelRequested = false,
    }) => turnResponse(
      TurnEnded(s, reason: reason, usage: Usage.zero, budgetExceeded: budget),
      cancelRequested: cancelRequested,
    ).toJson();

    test('stop reasons', () {
      expect(respond(TurnEndReason.completed), {'stopReason': 'end_turn'});
      expect(respond(TurnEndReason.maxTokens), {'stopReason': 'max_tokens'});
      expect(respond(TurnEndReason.refused), {'stopReason': 'refusal'});
      expect(respond(TurnEndReason.cancelled), {'stopReason': 'cancelled'});
    });

    test('budget → max_turn_requests with _meta.codelab.budgetExceeded', () {
      expect(respond(TurnEndReason.completed, budget: BudgetLimit.steps), {
        'stopReason': 'max_turn_requests',
        '_meta': {
          'codelab': {'budgetExceeded': 'steps'},
        },
      });
      expect(
        respond(TurnEndReason.completed, budget: BudgetLimit.tokens)['_meta'],
        {
          'codelab': {'budgetExceeded': 'tokens'},
        },
      );
    });

    test('failed → -32603 with data.codelab, never end_turn', () {
      expect(
        () => turnResponse(
          const TurnEnded(s, reason: TurnEndReason.failed, usage: Usage.zero),
          failure: const AgentError(
            s,
            cls: AgentErrorClass.provider,
            message: '401 Unauthorized from openai: check api_key_env',
            errorClass: LlmErrorClass.auth,
          ),
        ),
        throwsA(
          isA<AcpRequestError>().having((e) => e.code, 'code', -32603).having(
            (e) => e.data,
            'data',
            {
              'codelab': {
                'errorClass': 'auth',
                'message': '401 Unauthorized from openai: check api_key_env',
                'retryable': false,
              },
            },
          ),
        ),
      );
    });

    test('a failure that is not the provider names AgentErrorClass', () {
      expect(
        () => turnResponse(
          const TurnEnded(s, reason: TurnEndReason.failed, usage: Usage.zero),
          failure: const AgentError(
            s,
            cls: AgentErrorClass.storage,
            message: 'disk full',
          ),
        ),
        throwsA(
          isA<AcpRequestError>().having(
            (e) => (e.data! as Map)['codelab'],
            'codelab',
            {
              'errorClass': 'storage',
              'message': 'disk full',
              'retryable': false,
            },
          ),
        ),
      );
    });

    test('after session/cancel the answer is cancelled whatever happened', () {
      for (final reason in TurnEndReason.values) {
        expect(respond(reason, cancelRequested: true), {
          'stopReason': 'cancelled',
        }, reason: reason.name);
      }
    });
  });
}
