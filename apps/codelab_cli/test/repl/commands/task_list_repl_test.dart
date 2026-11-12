// План с задачами и тихая строка операций в REPL «из конца в конец» (задача
// 1.1, «CLI» change `add-subagents-and-tasks`; spec codelab-cli «Субагенты и
// список задач в REPL»; design.md, D27).
//
// Красные тесты: kit пока не читает `_meta.codelab.task` (задача 1.6) и не
// строит `TaskOpsItem` (задача 1.6a), REPL не печатает `#<id> [<status>]`
// (задача 1.7). Метка владельца без известного kit субагента — сам его id
// (spec acp-client-kit «Метаданные пунктов плана»).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:test/test.dart';

import '../../support/repl_harness.dart';

Map<String, Object?> _entry(
  String id,
  String status, {
  String? owner,
  List<String> blockedBy = const [],
}) => {
  'content': 'Task $id',
  'status': status,
  'priority': 'medium',
  '_meta': {
    'codelab': {
      'task': {'id': id, 'owner': ?owner, 'blockedBy': blockedBy},
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

  test('a plan with tasks is printed as #id [status] subject with owner '
      'and open blockers', () async {
    repl.line('go');
    final prompt = await repl.agent.next(sessionPromptMethod);
    repl.agent
      ..update('s1', {
        'sessionUpdate': 'plan',
        'entries': [
          _entry('1', 'completed'),
          _entry('2', 'in_progress', owner: 'sub_a1', blockedBy: ['1']),
          _entry('3', 'pending', blockedBy: ['2']),
        ],
      })
      ..respond(prompt, {'stopReason': 'end_turn'});

    await repl.waitText('#3 [pending] Task 3');
    final output = repl.lastOutput;
    expect(output, contains('#1 [completed] Task 1\n'));
    // Блокер #1 завершён — пометки нет; владелец без известного субагента
    // подписан своим id.
    expect(output, contains('#2 [in_progress] Task 2 (sub_a1)\n'));
    expect(output, contains('#3 [pending] Task 3 (blocked by #2)\n'));
  });

  test('four creations in a row print one quiet line', () async {
    repl.line('go');
    final prompt = await repl.agent.next(sessionPromptMethod);
    final entries = <Map<String, Object?>>[];
    for (var i = 1; i <= 4; i++) {
      entries.add(_entry('$i', 'pending'));
      repl.agent
        ..update('s1', {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call-$i',
          'title': 'Update the list',
          'kind': 'think',
          'status': 'in_progress',
        })
        ..update('s1', {
          'sessionUpdate': 'plan',
          'entries': List.of(entries),
          '_meta': {
            'codelab': {
              'taskChange': {
                'op': 'create',
                'actor': 'main',
                'toolCallId': 'call-$i',
                'changed': ['$i'],
                'deleted': <String>[],
              },
            },
          },
        })
        ..update('s1', {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-$i',
          'status': 'completed',
        });
    }
    repl.agent.respond(prompt, {'stopReason': 'end_turn'});

    await repl.waitText('Tasks #1–#4 added to the plan');
    final line = repl.lastOutput
        .split('\n')
        .singleWhere((l) => l.contains('Tasks #1–#4 added to the plan'));
    // Без значка статуса и времени выполнения; приглушённая строка (SGR 2).
    // Перед строкой — только перерисовки приглашения редактора (`> `, курсор,
    // очистка), без значка статуса и времени.
    expect(
      line,
      matches(
        RegExp(
          r'^(> \r\x1b\[2C\r\x1b\[J)*'
          r'\x1b\[2mTasks #1–#4 added to the plan\x1b\[0m$',
        ),
      ),
    );
  });

  // Spec codelab-cli «Бегущий вызов think не печатается»: до завершения REPL
  // ничего не печатает о вызове `think`, потому что kit опознаёт операцию со
  // списком только по завершённому вызову, а напечатанную строку не стереть.
  group('a running think call is not printed', () {
    Future<JsonRpcRequest> startTurn() async {
      repl.line('go');
      return repl.agent.next(sessionPromptMethod);
    }

    test('a list operation: nothing until completed, then one quiet '
        'line', () async {
      final prompt = await startTurn();
      repl.agent
        ..update('s1', {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call-1',
          'title': 'Create the task',
          'kind': 'think',
          'status': 'in_progress',
        })
        ..update('s1', {
          'sessionUpdate': 'plan',
          'entries': [_entry('1', 'pending')],
          '_meta': {
            'codelab': {
              'taskChange': {
                'op': 'create',
                'actor': 'main',
                'toolCallId': 'call-1',
                'changed': ['1'],
                'deleted': <String>[],
              },
            },
          },
        });
      await pumpEventQueue();
      expect(repl.lastOutput, isNot(contains('Create the task')));
      expect(repl.lastOutput, isNot(contains('Task #1 added')));

      repl.agent
        ..update('s1', {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-1',
          'status': 'completed',
        })
        ..respond(prompt, {'stopReason': 'end_turn'});

      await repl.waitText('Task #1 added to the plan');
      expect(repl.lastOutput, isNot(contains('Create the task')));
    });

    test('a think call that is not a list operation: an ordinary row only '
        'after completion', () async {
      final prompt = await startTurn();
      repl.agent.update('s1', {
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-1',
        'title': 'Ponder the design',
        'kind': 'think',
        'status': 'in_progress',
      });
      await pumpEventQueue();
      expect(repl.lastOutput, isNot(contains('Ponder the design')));

      repl.agent
        ..update('s1', {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-1',
          'status': 'completed',
        })
        ..respond(prompt, {'stopReason': 'end_turn'});

      await repl.waitText('✓');
      expect('Ponder the design'.allMatches(repl.lastOutput), hasLength(1));
    });
  });
}
