// `TaskOpsItem` — тихая строка операций со списком задач (задача 1.1, «kit»
// change `add-subagents-and-tasks`; spec acp-client-kit «Операции со списком
// задач в ленте»; design.md, D27, D35).
//
// Вызов становится операцией только по ключу `plan._meta.codelab.taskChange`
// с `toolCallId`: вызов корневого уровня вида `think`, без
// `_meta.codelab.subagent`, завершившийся `completed`. Порядок кадров, статус
// вызова в момент прихода `plan` и сравнение планов вызов не опознают.
// Поля `TaskOpsItem`: `id`, `added`, `completed`, `removed`, `updated` и
// `text` (extension `TaskOpsItemText`).

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

/// Пункт плана с `_meta.codelab.task.id`; [withMeta] `false` — пункт плана
/// стороннего агента.
Map<String, Object?> _entry(String id, String status, {bool withMeta = true}) =>
    {
      'content': 'Task $id',
      'status': status,
      'priority': 'medium',
      if (withMeta)
        '_meta': {
          'codelab': {
            'task': {'id': id},
          },
        },
    };

/// `plan`; [change] — `_meta.codelab.taskChange` (D35), `null` — без ключа.
Map<String, Object?> _plan(
  List<Map<String, Object?>> entries, {
  Map<String, Object?>? change,
}) => {
  'sessionUpdate': 'plan',
  'entries': entries,
  if (change != null)
    '_meta': {
      'codelab': {'taskChange': change},
    },
};

Map<String, Object?> _change(
  String op, {
  String? call,
  List<String> changed = const [],
  List<String> deleted = const [],
}) => {
  'op': op,
  'actor': 'main',
  'toolCallId': ?call,
  'changed': changed,
  'deleted': deleted,
};

Map<String, Object?> _think(String id, {Map<String, Object?>? meta}) => {
  'sessionUpdate': 'tool_call',
  'toolCallId': id,
  // Заголовок намеренно не похож на операцию: kit его не разбирает (D27).
  'title': 'Whatever the agent wrote',
  'kind': 'think',
  'status': 'in_progress',
  '_meta': ?meta,
};

Map<String, Object?> _finish(String id, String status) => {
  'sessionUpdate': 'tool_call_update',
  'toolCallId': id,
  'status': status,
};

void main() {
  late KitAgent agent;
  late SessionHandle session;

  setUp(() async {
    agent = KitAgent();
    await agent.start();
    session = await agent.newSession('s1');
    await agent.prompt(session, 'go');
  });
  tearDown(() => agent.dispose());

  Future<void> emit(Map<String, Object?> update) async {
    agent.update('s1', update);
    await pumpEventQueue();
  }

  /// Вызов `think` [id] и его завершение; [plan] приходит между ними.
  Future<void> operation(
    String id,
    Map<String, Object?>? plan, {
    String status = 'completed',
  }) async {
    await emit(_think(id));
    if (plan != null) await emit(plan);
    await emit(_finish(id, status));
  }

  List<TranscriptItem> items() => session.current.transcript;
  Iterable<TaskOpsItem> ops() => items().whereType<TaskOpsItem>();

  test('four creations in a row merge into one TaskOpsItem', () async {
    final entries = <Map<String, Object?>>[];
    for (var i = 1; i <= 4; i++) {
      entries.add(_entry('$i', 'pending'));
      await operation(
        'call-$i',
        _plan(
          List.of(entries),
          change: _change('create', call: 'call-$i', changed: ['$i']),
        ),
      );
    }

    expect(items().map((item) => item.runtimeType), [UserItem, TaskOpsItem]);
    final item = items().last as TaskOpsItem;
    expect(item.added, ['1', '2', '3', '4']);
    expect(item.text, 'Tasks #1–#4 added to the plan');
  });

  test('while the call is running it is an ordinary ToolCallItem, and '
      'becomes TaskOpsItem on completion at the same place', () async {
    await emit(_think('call-1'));
    await emit(
      _plan([
        _entry('1', 'pending'),
      ], change: _change('create', call: 'call-1', changed: ['1'])),
    );
    expect(items().last, isA<ToolCallItem>());

    await emit(_finish('call-1', 'completed'));

    expect(items(), hasLength(2));
    expect((items().last as TaskOpsItem).text, 'Task #1 added to the plan');
  });

  test('a non-contiguous id list is written with commas', () async {
    await operation(
      'call-1',
      _plan([
        _entry('1', 'pending'),
        _entry('3', 'pending'),
      ], change: _change('create', call: 'call-1', changed: ['1', '3'])),
    );

    expect(
      (items().last as TaskOpsItem).text,
      'Tasks #1, #3 added to the plan',
    );
  });

  test(
    'done, removed and updated texts follow op, changed and deleted',
    () async {
      await operation(
        'call-1',
        _plan([
          _entry('1', 'pending'),
          _entry('2', 'pending'),
          _entry('3', 'pending'),
        ], change: _change('create', call: 'call-1', changed: ['1', '2', '3'])),
      );
      Future<void> gap(String text) => emit({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': text},
      });

      await gap('a');
      // «done»: пункт completed в этом плане и не completed в предыдущем.
      await operation(
        'call-2',
        _plan([
          _entry('1', 'pending'),
          _entry('2', 'completed'),
          _entry('3', 'pending'),
        ], change: _change('update', call: 'call-2', changed: ['2'])),
      );
      expect((items().last as TaskOpsItem).text, 'Task #2 done');

      await gap('b');
      // Тот же пункт уже completed — это «updated».
      await operation(
        'call-3',
        _plan([
          _entry('1', 'pending'),
          _entry('2', 'completed'),
          _entry('3', 'pending'),
        ], change: _change('update', call: 'call-3', changed: ['2'])),
      );
      expect((items().last as TaskOpsItem).text, 'Task #2 updated');

      await gap('c');
      await operation(
        'call-4',
        _plan([
          _entry('2', 'completed'),
          _entry('3', 'pending'),
        ], change: _change('delete', call: 'call-4', deleted: ['1'])),
      );
      expect((items().last as TaskOpsItem).text, 'Task #1 removed');

      await gap('d');
      // `changed` при delete — пункты со снятым блокером: не «removed» (D35).
      await operation(
        'call-5',
        _plan(
          [_entry('3', 'pending')],
          change: _change(
            'delete',
            call: 'call-5',
            changed: ['3'],
            deleted: ['2'],
          ),
        ),
      );
      expect((items().last as TaskOpsItem).text, 'Task #2 removed');
    },
  );

  test('parts of merged consecutive operations are joined with "; "', () async {
    await operation(
      'call-1',
      _plan([
        _entry('1', 'pending'),
      ], change: _change('create', call: 'call-1', changed: ['1'])),
    );
    await operation(
      'call-2',
      _plan([
        _entry('1', 'completed'),
        _entry('2', 'pending'),
      ], change: _change('create', call: 'call-2', changed: ['2'])),
    );
    await operation(
      'call-3',
      _plan([
        _entry('1', 'completed'),
        _entry('2', 'pending'),
      ], change: _change('update', call: 'call-3', changed: ['1'])),
    );

    expect(ops().single.text, 'Tasks #1–#2 added to the plan; Task #1 updated');
  });

  test('an item of another kind between operations stops the merge', () async {
    await operation(
      'call-1',
      _plan([
        _entry('1', 'pending'),
      ], change: _change('create', call: 'call-1', changed: ['1'])),
    );
    await emit({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'thinking aloud'},
    });
    await operation(
      'call-2',
      _plan([
        _entry('1', 'pending'),
        _entry('2', 'pending'),
      ], change: _change('create', call: 'call-2', changed: ['2'])),
    );

    expect(ops(), hasLength(2));
  });

  test(
    'an item added and removed inside one merge disappears from it',
    () async {
      await operation(
        'call-1',
        _plan([
          _entry('1', 'pending'),
        ], change: _change('create', call: 'call-1', changed: ['1'])),
      );
      await operation(
        'call-2',
        _plan([
          _entry('1', 'pending'),
          _entry('2', 'pending'),
        ], change: _change('create', call: 'call-2', changed: ['2'])),
      );
      await operation(
        'call-3',
        _plan([
          _entry('2', 'pending'),
        ], change: _change('delete', call: 'call-3', deleted: ['1'])),
      );

      final item = ops().single;
      expect(item.added, ['2']);
      expect(item.removed, isEmpty);
      expect(item.text, 'Task #2 added to the plan');
    },
  );

  test('a rejected operation stays an ordinary failed ToolCallItem', () async {
    await operation('call-1', null, status: 'failed');

    expect(ops(), isEmpty);
    expect(
      (items().last as ToolCallItem).details?.status,
      ToolCallStatusView.failed,
    );
  });

  test('a failed call stays ordinary even if a plan refers to it', () async {
    await operation(
      'call-1',
      _plan([
        _entry('1', 'pending'),
      ], change: _change('create', call: 'call-1', changed: ['1'])),
      status: 'failed',
    );

    expect(ops(), isEmpty);
    expect(items().last, isA<ToolCallItem>());
  });

  test('a read call that no plan refers to stays ordinary', () async {
    await operation('call-1', null);

    expect(ops(), isEmpty);
    expect(items().last, isA<ToolCallItem>());
  });

  test('an empty change (nothing changed) stays an ordinary call', () async {
    await operation(
      'call-1',
      _plan([
        _entry('1', 'pending'),
      ], change: _change('update', call: 'call-1')),
    );

    expect(ops(), isEmpty);
    expect(items().last, isA<ToolCallItem>());
  });

  test('a plan without taskChange only updates the plan; the call stays '
      'ordinary (old or third-party agent)', () async {
    await operation('call-1', _plan([_entry('1', 'pending')]));

    expect(ops(), isEmpty);
    expect(items().last, isA<ToolCallItem>());
    expect(session.current.plan.map((e) => e.content), ['Task 1']);
  });

  test('a third-party plan without _meta.codelab.task keeps the ordinary '
      'call', () async {
    await operation('call-1', _plan([_entry('1', 'pending', withMeta: false)]));

    expect(ops(), isEmpty);
    expect(items().last, isA<ToolCallItem>());
  });

  test('taskChange of a wrong shape is treated as absent', () async {
    await operation('call-1', {
      ..._plan([_entry('1', 'pending')]),
      '_meta': {
        'codelab': {'taskChange': 'create'},
      },
    });

    expect(ops(), isEmpty);
  });

  test('restore without toolCallId only replaces the plan', () async {
    await emit(_think('call-1'));
    await emit(
      _plan([
        _entry('1', 'pending'),
      ], change: _change('restore', changed: ['1'])),
    );
    await emit(_finish('call-1', 'completed'));

    expect(ops(), isEmpty);
    expect(items().last, isA<ToolCallItem>());
    expect(session.current.plan, hasLength(1));
  });

  test('a batch [create, read, create] gives two operations split by the '
      'read, whatever the order of plan frames', () async {
    for (final id in ['c1', 'r1', 'c2']) {
      await emit(_think(id));
    }
    // plan второго создания пришёл раньше plan первого.
    await emit(
      _plan([
        _entry('2', 'pending'),
      ], change: _change('create', call: 'c2', changed: ['2'])),
    );
    await emit(
      _plan([
        _entry('1', 'pending'),
        _entry('2', 'pending'),
      ], change: _change('create', call: 'c1', changed: ['1'])),
    );
    for (final id in ['c1', 'r1', 'c2']) {
      await emit(_finish(id, 'completed'));
    }

    expect(items().map((i) => i.runtimeType), [
      UserItem,
      TaskOpsItem,
      ToolCallItem,
      TaskOpsItem,
    ]);
    expect((items()[1] as TaskOpsItem).text, 'Task #1 added to the plan');
    expect((items()[3] as TaskOpsItem).text, 'Task #2 added to the plan');
  });

  test('task_list in a batch with task_create is not an operation', () async {
    await emit(_think('c1'));
    await emit(_think('l1'));
    await emit(
      _plan([
        _entry('1', 'pending'),
      ], change: _change('create', call: 'c1', changed: ['1'])),
    );
    await emit(_finish('c1', 'completed'));
    await emit(_finish('l1', 'completed'));

    expect(items().map((i) => i.runtimeType), [
      UserItem,
      TaskOpsItem,
      ToolCallItem,
    ]);
  });

  test('replayed past operations are ordinary calls, the plan is the state '
      'at the tail', () async {
    for (var i = 1; i <= 3; i++) {
      await operation('call-$i', null);
    }
    await emit(
      _plan([
        _entry('1', 'pending'),
        _entry('2', 'pending'),
        _entry('3', 'pending'),
      ]),
    );

    expect(ops(), isEmpty);
    expect(items().whereType<ToolCallItem>(), hasLength(3));
    expect(session.current.plan.map((e) => e.taskId), ['1', '2', '3']);
  });

  test('a subagent call is never a list operation even if a plan refers '
      'to it', () async {
    await emit(
      _think(
        'call-1',
        meta: {
          'codelab': {
            'subagent': {'id': 'sub_a1', 'type': 'explore'},
          },
        },
      ),
    );
    await emit(
      _plan([
        _entry('1', 'pending'),
      ], change: _change('create', call: 'call-1', changed: ['1'])),
    );
    await emit(_finish('call-1', 'completed'));

    expect(ops(), isEmpty);
    expect(items().last, isA<ToolCallItem>());
  });

  test(
    'a nested call (parentToolCallId) is not a root-level operation',
    () async {
      await emit(
        _think(
          'call-1/call-1',
          meta: {
            'codelab': {'parentToolCallId': 'call-1'},
          },
        ),
      );
      await emit(
        _plan([
          _entry('1', 'pending'),
        ], change: _change('create', call: 'call-1/call-1', changed: ['1'])),
      );
      await emit(_finish('call-1/call-1', 'completed'));

      expect(ops(), isEmpty);
    },
  );
}
