// Вызов `agent` и план с владельцем-субагентом в REPL «из конца в конец»
// (задача 2.1 «CLI» change `add-subagents-and-tasks`; spec codelab-cli
// «Субагенты и список задач в REPL»: сценарии «План с задачами» (метка
// `(explore)`), «Итог в строке вызова»; acp-client-kit «Метаданные пунктов
// плана», метка владельца по типу; design.md, D24, D28; задачи 2.9, 2.9b).
//
// Красные тесты: kit не опознаёт вызов `agent` по `_meta.codelab.subagent`
// первого кадра (2.9) и поэтому подписывает владельца id `sub_a1`, а не типом
// `explore` (2.9b); итог в скобках строки вызова не печатается (2.9).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:test/test.dart';

import '../../support/repl_harness.dart';

Map<String, Object?> _agentCall() => {
  'sessionUpdate': 'tool_call',
  'toolCallId': 'call_1',
  'title': 'Subagent explore: Find auth code',
  'kind': 'think',
  'status': 'in_progress',
  'rawInput': {'type': 'explore', 'description': 'Find auth code'},
  '_meta': {
    'codelab': {
      'subagent': {'id': 'sub_a1', 'type': 'explore'},
    },
  },
};

Map<String, Object?> _entry(String id, String status, {String? owner}) => {
  'content': 'Task $id',
  'status': status,
  'priority': 'medium',
  '_meta': {
    'codelab': {
      'task': {'id': id, 'owner': ?owner},
    },
  },
};

void main() {
  late ReplHarness repl;

  setUp(() async {
    repl = ReplHarness();
    await repl.start();
  });
  tearDown(() => repl.dispose());

  test('a plan entry of a known subagent is printed with its type, '
      'not its id', () async {
    repl.line('go');
    final prompt = await repl.agent.next(sessionPromptMethod);
    repl.agent
      ..update('s1', _agentCall())
      ..update('s1', {
        'sessionUpdate': 'plan',
        'entries': [
          _entry('1', 'completed'),
          _entry('2', 'in_progress', owner: 'sub_a1'),
        ],
      })
      ..respond(prompt, {'stopReason': 'end_turn'});

    await repl.waitText('#2 [in_progress] Task 2');
    expect(repl.lastOutput, contains('#2 [in_progress] Task 2 (explore)\n'));
    expect(repl.lastOutput, isNot(contains('(sub_a1)')));
  });

  test('the finished agent call carries the summary in parentheses, without '
      '"Done", and the report below', () async {
    repl.line('go');
    final prompt = await repl.agent.next(sessionPromptMethod);
    repl.agent
      ..update('s1', _agentCall())
      ..update('s1', {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call_1',
        'status': 'completed',
        'content': [
          {
            'type': 'content',
            'content': {
              'type': 'text',
              'text': 'Auth lives in lib/auth/session.dart.',
            },
          },
        ],
        '_meta': {
          'codelab': {
            'subagent': {
              'id': 'sub_a1',
              'summary': {
                'toolCalls': 4,
                'tokens': {'input': 15200, 'output': 3000},
                'durationMs': 48000,
              },
            },
          },
        },
      })
      ..respond(prompt, {'stopReason': 'end_turn'});

    await repl.waitText('Auth lives in lib/auth/session.dart.');
    final output = repl.lastOutput;
    expect(
      output,
      contains(
        'Subagent explore: Find auth code '
        '(4 tool calls · 18.2k tokens · 48s)',
      ),
    );
    expect(output, isNot(contains('Done')));
  });

  test('a third-party think call of the same shape without the sign has no '
      'summary parentheses', () async {
    repl.line('go');
    final prompt = await repl.agent.next(sessionPromptMethod);
    final call = _agentCall()..remove('_meta');
    repl.agent
      ..update('s1', call)
      ..update('s1', {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call_1',
        'status': 'completed',
      })
      ..respond(prompt, {'stopReason': 'end_turn'});

    await repl.waitText('✓');
    expect(repl.lastOutput, isNot(contains('tool calls')));
  });
}
