// Вызов `agent` в kit (задача 2.1 «kit и клиенты» change
// `add-subagents-and-tasks`; spec acp-client-kit «Итог и хвост субагента»:
// сценарии «Вызов agent с первого кадра», «Итог в представлении», «Сторонний
// агент без итога»; «Запрос одобрения от субагента», часть про строку
// `agent`; «Метаданные пунктов плана», метка владельца; design.md, D24, D27,
// D28; задачи 2.9, 2.9b).
//
// Красные тесты: у `ToolCallView` нет `subagentCall` и `subagentSummary`, а у
// `ToolRowView` — полей `progress`, `report`, `summary`, `summaryShort`
// (задача 2.9) — файл не компилируется, пока их нет. Имена из desktop
// (`SubagentCallView(id, type)`, `SubagentSummaryView(toolCalls,
// inputTokens, outputTokens, duration)`) сохранены. Имена, выбранные здесь,
// предложение этой задачи (spec их не задаёт):
//   `SubagentSummaryView.text` — `4 tool calls · 18.2k tokens · 48s`;
//   `SubagentSummaryView.shortText` — `4 tool calls · 18.2k · 48s`;
//   `SubagentSummaryView.durationText` — `48s`, `2m 05s`, `1h 02m`;
//   `ToolRowView.progress` — последняя строка прогресса, пока вызов идёт;
//   `ToolRowView.report` — текст отчёта после завершения;
//   `ToolRowView.summary` / `summaryShort` — строки итога (или `null`).
// Решение «это вызов agent» принимает kit по `_meta.codelab.subagent` первого
// кадра (D28), а не разбор заголовка.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

/// Первый кадр вызова `agent`; [subagent] — значение `_meta.codelab.subagent`,
/// `null` — кадр без `_meta` (сторонний агент).
Map<String, Object?> _agentCall(
  String id, {
  Object? subagent = const {'id': 'sub_a1', 'type': 'explore'},
  String title = 'Subagent explore: Find auth code',
}) => {
  'sessionUpdate': 'tool_call',
  'toolCallId': id,
  'title': title,
  'kind': 'think',
  'status': 'in_progress',
  'rawInput': {
    'type': 'explore',
    'description': 'Find auth code',
    'prompt': 'Find where authentication is implemented.',
  },
  if (subagent != null)
    '_meta': {
      'codelab': {'subagent': subagent},
    },
};

Map<String, Object?> _text(String text) => {
  'type': 'content',
  'content': {'type': 'text', 'text': text},
};

/// Финальный кадр вызова; [summary] — `_meta.codelab.subagent.summary`.
Map<String, Object?> _finish(
  String id, {
  String status = 'completed',
  Object? summary,
  Map<String, Object?>? extra,
  List<Map<String, Object?>>? content,
}) => {
  'sessionUpdate': 'tool_call_update',
  'toolCallId': id,
  'status': status,
  'content': ?content,
  if (summary != null || extra != null)
    '_meta': {
      'codelab': {
        'subagent': {'id': 'sub_a1', 'summary': ?summary, ...?extra},
      },
    },
};

const _summary = {
  'toolCalls': 4,
  'tokens': {'input': 15200, 'output': 3000},
  'durationMs': 48000,
};

void main() {
  late KitAgent agent;
  late SessionHandle session;
  late JsonRpcRequest firstPrompt;

  setUp(() async {
    agent = KitAgent();
    await agent.start();
    session = await agent.newSession('s1');
    firstPrompt = (await agent.prompt(session, 'go')).request;
  });
  tearDown(() => agent.dispose());

  Future<void> emit(Map<String, Object?> update) async {
    agent.update('s1', update);
    await pumpEventQueue();
  }

  ToolCallItem call(String id) => session.current.transcript
      .whereType<ToolCallItem>()
      .singleWhere((item) => item.toolCallId == ToolCallId(id));

  ToolRowView row(String id) => ToolRowFormatter.format(call(id), cwd: '/work');

  group('the sign of an agent call from the first frame (D28)', () {
    test('_meta.codelab.subagent {id, type} gives subagentCall, an unknown '
        'key is ignored', () async {
      await emit(
        _agentCall(
          'call_1',
          subagent: {'id': 'sub_a1', 'type': 'explore', 'x': 1},
        ),
      );

      expect(
        call('call_1').details?.subagentCall,
        const SubagentCallView(id: 'sub_a1', type: 'explore'),
      );
      expect(call('call_1').details?.kind, ToolKind.think);
    });

    test('the same frame without _meta is an ordinary think call', () async {
      await emit(_agentCall('call_1', subagent: null));

      expect(call('call_1').details?.subagentCall, isNull);
      expect(call('call_1').details?.subagentSummary, isNull);
    });

    test('a wrong shape gives null without failing the update', () async {
      await emit(_agentCall('call_1', subagent: 'sub_a1'));
      await emit(_agentCall('call_2', subagent: {'id': 5, 'type': 'explore'}));
      await emit(_agentCall('call_3', subagent: {'id': 'sub_a3'}));

      expect(call('call_1').details?.subagentCall, isNull);
      expect(call('call_2').details?.subagentCall, isNull);
      expect(call('call_3').details?.subagentCall, isNull);
      expect(agent.diagnostics, isEmpty);
    });

    test('a repeated frame of the same call keeps the sign (replay '
        'idempotence)', () async {
      await emit(_agentCall('call_1'));
      await emit(_agentCall('call_1'));

      expect(
        session.current.transcript.whereType<ToolCallItem>(),
        hasLength(1),
      );
      expect(call('call_1').details?.subagentCall?.id, 'sub_a1');
    });

    test('an update without _meta does not drop the sign', () async {
      await emit(_agentCall('call_1'));
      await emit({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call_1',
        'content': [_text('explore · 1 tool call')],
      });

      expect(call('call_1').details?.subagentCall?.type, 'explore');
    });
  });

  group('the summary in the view (D24)', () {
    test('the final update gives subagentSummary and the summary line; an '
        'unknown key is ignored', () async {
      await emit(_agentCall('call_1'));
      await emit(_finish('call_1', summary: {..._summary, 'future': 1}));

      final summary = call('call_1').details?.subagentSummary;
      expect(
        summary,
        const SubagentSummaryView(
          toolCalls: 4,
          inputTokens: 15200,
          outputTokens: 3000,
          duration: Duration(seconds: 48),
        ),
      );
      expect(summary?.text, '4 tool calls · 18.2k tokens · 48s');
      // Сокращённый вид свёрнутой строки (D27): без слова `tokens`.
      expect(summary?.shortText, '4 tool calls · 18.2k · 48s');
    });

    test(
      'a third-party agent finishes without summary: no summary line',
      () async {
        await emit(_agentCall('call_1', subagent: null));
        await emit(_finish('call_1'));

        expect(call('call_1').details?.subagentSummary, isNull);
        expect(row('call_1').summary, isNull);
        expect(row('call_1').summaryShort, isNull);
      },
    );

    test('a CodeLab call without summary: subagentSummary is null', () async {
      await emit(_agentCall('call_1'));
      await emit(
        _finish('call_1', extra: {'failure': 'budget_exceeded:max_steps'}),
      );

      expect(call('call_1').details?.subagentCall, isNotNull);
      expect(call('call_1').details?.subagentSummary, isNull);
    });

    test('a wrong shape of summary is tolerated as no summary', () async {
      for (final (i, bad) in <Object?>[
        'oops',
        {'toolCalls': '4'},
        {'toolCalls': 4, 'tokens': 'many', 'durationMs': 1},
        {
          'toolCalls': 4,
          'tokens': {'input': 1},
          'durationMs': 1,
        },
      ].indexed) {
        await emit(_agentCall('call_$i'));
        await emit(_finish('call_$i', summary: bad));
        expect(
          call('call_$i').details?.subagentSummary,
          isNull,
          reason: '$bad',
        );
      }
      expect(agent.diagnostics, isEmpty);
    });

    test(
      'a failed call with summary keeps both the status and the summary',
      () async {
        await emit(_agentCall('call_1'));
        await emit(
          _finish(
            'call_1',
            status: 'failed',
            summary: _summary,
            extra: {'failure': 'budget_exceeded:max_steps'},
          ),
        );

        final details = call('call_1').details!;
        expect(details.status, ToolCallStatusView.failed);
        expect(details.subagentSummary?.toolCalls, 4);
      },
    );

    test('duration format: 48s, 2m 05s, 1h 02m', () {
      String of(Duration d) => SubagentSummaryView(
        toolCalls: 1,
        inputTokens: 0,
        outputTokens: 0,
        duration: d,
      ).durationText;

      expect(of(const Duration(seconds: 48)), '48s');
      expect(of(const Duration(minutes: 2, seconds: 5)), '2m 05s');
      expect(of(const Duration(hours: 1, minutes: 2, seconds: 30)), '1h 02m');
    });

    test('tokens are input + output with one decimal after k', () {
      String of(int input, int output) => SubagentSummaryView(
        toolCalls: 3,
        inputTokens: input,
        outputTokens: output,
        duration: const Duration(seconds: 1),
      ).text;

      expect(of(6000, 400), '3 tool calls · 6.4k tokens · 1s');
      expect(of(15200, 3000), '3 tool calls · 18.2k tokens · 1s');
    });
  });

  group('the agent row (ToolRowFormatter)', () {
    test('running: the heading is the detail, the last progress line is '
        'shown and replaced by the next one', () async {
      await emit(_agentCall('call_1'));
      await emit({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call_1',
        'content': [_text('explore · 1 tool call · 4s')],
      });
      expect(row('call_1').progress, 'explore · 1 tool call · 4s');

      // `content` обновления заменяет коллекцию: строка прогресса — всегда
      // последняя.
      await emit({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call_1',
        'content': [_text('explore · 2 tool calls · 9s')],
      });

      final view = row('call_1');
      expect(view.progress, 'explore · 2 tool calls · 9s');
      expect(view.report, isNull);
      expect(view.summary, isNull);
      expect(view.label, 'Subagent');
      expect(view.detail, 'explore: Find auth code');
    });

    test('completed: the report is the text output, the progress is gone, '
        'the summary lines come from subagentSummary', () async {
      await emit(_agentCall('call_1'));
      await emit(
        _finish(
          'call_1',
          summary: _summary,
          content: [_text('Auth lives in lib/auth/session.dart.')],
        ),
      );

      final view = row('call_1');
      expect(view.progress, isNull);
      expect(view.report, 'Auth lives in lib/auth/session.dart.');
      expect(view.summary, '4 tool calls · 18.2k tokens · 48s');
      expect(view.summaryShort, '4 tool calls · 18.2k · 48s');
    });

    test('failed keeps the status secondary and the summary', () async {
      await emit(_agentCall('call_1'));
      await emit(
        _finish(
          'call_1',
          status: 'failed',
          summary: _summary,
          content: [_text('Budget exceeded')],
        ),
      );

      final view = row('call_1');
      expect(view.secondary, 'Budget exceeded');
      expect(view.summaryShort, '4 tool calls · 18.2k · 48s');
    });

    test(
      'a third-party think call has no progress, report or summary',
      () async {
        await emit(_agentCall('call_1', subagent: null, title: 'Thinking'));
        await emit({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call_1',
          'content': [_text('hmm')],
        });

        final view = row('call_1');
        expect(view.progress, isNull);
        expect(view.report, isNull);
        expect(view.summary, isNull);
        expect(view.label, 'Think');
      },
    );
  });

  group('the owner label of a plan entry by subagent type (2.9b)', () {
    Map<String, Object?> plan(String? owner) => {
      'sessionUpdate': 'plan',
      'entries': [
        {
          'content': 'Map callers',
          'status': 'in_progress',
          'priority': 'medium',
          '_meta': {
            'codelab': {
              'task': {'id': '1', 'owner': ?owner},
            },
          },
        },
      ],
    };

    test('the owner id of a known agent call turns into its type', () async {
      await emit(_agentCall('call_1'));
      await emit(plan('sub_a1'));

      final entry = session.current.plan.single;
      expect(entry.owner, 'sub_a1');
      expect(entry.ownerLabel, 'explore');
    });

    test('an owner without a known agent call keeps its id', () async {
      await emit(_agentCall('call_1'));
      await emit(plan('sub_zzz'));

      expect(session.current.plan.single.ownerLabel, 'sub_zzz');
    });

    test('a plan that comes before the call is relabelled when the call '
        'arrives', () async {
      await emit(plan('sub_a1'));
      expect(session.current.plan.single.ownerLabel, 'sub_a1');

      await emit(_agentCall('call_1'));

      expect(session.current.plan.single.ownerLabel, 'explore');
    });

    test('a third-party think call is not a source of types', () async {
      await emit(_agentCall('call_1', subagent: null));
      await emit(plan('sub_a1'));

      expect(session.current.plan.single.ownerLabel, 'sub_a1');
    });

    test(
      'the type is taken from calls of earlier turns of the session',
      () async {
        await emit(_agentCall('call_1'));
        await emit(_finish('call_1', summary: _summary));
        agent.respond(firstPrompt, {'stopReason': 'end_turn'});
        await pumpEventQueue();
        await agent.prompt(session, 'next');

        await emit(plan('sub_a1'));

        expect(session.current.plan.single.ownerLabel, 'explore');
      },
    );
  });
}
