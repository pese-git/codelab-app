// `TaskOpsItem` — тихая строка операций со списком задач (задача 1.1, «kit»
// change `add-subagents-and-tasks`; spec acp-client-kit «Операции со списком
// задач в ленте»; design.md, D27).
//
// Красные тесты: `TaskOpsItem` ещё нет (задача 1.6a). Предлагаемые поля:
// `id`, `added`, `completed`, `removed`, `updated` (списки id пунктов,
// `List<String>`) и `text` — готовый текст kit; их же использует desktop
// (задача 1.8). Распознавание — только по данным: `kind: think`, успех, нет
// `_meta.codelab.subagent`, во время вызова пришёл `plan` с
// `_meta.codelab.task`; заголовок вызова не разбирается.

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

/// Пункт плана с `_meta.codelab.task.id`; [withMeta] `false` — план стороннего
/// агента без `_meta`.
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

Map<String, Object?> _plan(List<Map<String, Object?>> entries) => {
  'sessionUpdate': 'plan',
  'entries': entries,
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

  /// Вызов `think` [id], во время которого приходит [plan], и его завершение.
  Future<void> operation(
    String id,
    List<Map<String, Object?>>? plan, {
    String status = 'completed',
  }) async {
    await emit(_think(id));
    if (plan != null) await emit(_plan(plan));
    await emit(_finish(id, status));
  }

  List<TranscriptItem> items() => session.current.transcript;

  test('four creations in a row merge into one TaskOpsItem', () async {
    final entries = <Map<String, Object?>>[];
    for (var i = 1; i <= 4; i++) {
      entries.add(_entry('$i', 'pending'));
      await operation('call-$i', List.of(entries));
    }

    final transcript = items();
    expect(transcript.map((item) => item.runtimeType), [UserItem, TaskOpsItem]);
    final ops = transcript.last as TaskOpsItem;
    expect(ops.added, ['1', '2', '3', '4']);
    expect(ops.text, 'Tasks #1–#4 added to the plan');
  });

  test('while the call is running it is an ordinary ToolCallItem, and '
      'becomes TaskOpsItem on completion at the same place', () async {
    await emit(_think('call-1'));
    expect(items().last, isA<ToolCallItem>());

    await emit(_plan([_entry('1', 'pending')]));
    await emit(_finish('call-1', 'completed'));

    expect(items(), hasLength(2));
    final ops = items().last as TaskOpsItem;
    expect(ops.text, 'Task #1 added to the plan');
  });

  test('a non-contiguous id list is written with commas', () async {
    await operation('call-1', [_entry('1', 'pending'), _entry('3', 'pending')]);

    expect(
      (items().last as TaskOpsItem).text,
      'Tasks #1, #3 added to the plan',
    );
  });

  test(
    'done, removed and updated operations are told by the plan diff',
    () async {
      await operation('call-1', [
        _entry('1', 'pending'),
        _entry('2', 'pending'),
      ]);
      // Операция другого вида между списками: слияние рвётся, элемент свой.
      await emit({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'working'},
      });

      await operation('call-2', [
        _entry('1', 'pending'),
        _entry('2', 'completed'),
      ]);
      final done = items().last as TaskOpsItem;
      expect(done.completed, ['2']);
      expect(done.text, 'Task #2 done');

      await emit({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'more'},
      });
      await operation('call-3', [_entry('2', 'completed')]);
      final removed = items().last as TaskOpsItem;
      expect(removed.removed, ['1']);
      expect(removed.text, 'Task #1 removed');
    },
  );

  test('parts of merged consecutive operations are joined with "; "', () async {
    await operation('call-1', [_entry('1', 'pending')]);
    await operation('call-2', [
      _entry('1', 'completed'),
      _entry('2', 'pending'),
    ]);

    final ops = items().whereType<TaskOpsItem>().single;
    expect(ops.added, ['1', '2']);
    expect(ops.completed, ['1']);
    expect(ops.text, 'Task #2 added to the plan; Task #1 done');
  });

  test('an item of another kind between operations stops the merge', () async {
    await operation('call-1', [_entry('1', 'pending')]);
    await emit({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'thinking aloud'},
    });
    await operation('call-2', [_entry('1', 'pending'), _entry('2', 'pending')]);

    expect(items().whereType<TaskOpsItem>(), hasLength(2));
  });

  test('a rejected operation stays an ordinary failed ToolCallItem', () async {
    await operation('call-1', null, status: 'failed');

    final tool = items().last as ToolCallItem;
    expect(items().whereType<TaskOpsItem>(), isEmpty);
    expect(tool.details?.status, ToolCallStatusView.failed);
  });

  test(
    'a read operation without a plan stays an ordinary ToolCallItem',
    () async {
      await operation('call-1', null);

      expect(items().whereType<TaskOpsItem>(), isEmpty);
      expect(items().last, isA<ToolCallItem>());
    },
  );

  test('a third-party agent plan without _meta.codelab.task keeps the '
      'ordinary call', () async {
    await operation('call-1', [_entry('1', 'pending', withMeta: false)]);

    expect(items().whereType<TaskOpsItem>(), isEmpty);
    expect(items().last, isA<ToolCallItem>());
    expect(session.current.plan.map((e) => e.content), ['Task 1']);
  });

  test('a subagent call is never a list operation even with a plan '
      'during it', () async {
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
    await emit(_plan([_entry('1', 'pending')]));
    await emit(_finish('call-1', 'completed'));

    expect(items().whereType<TaskOpsItem>(), isEmpty);
    expect(items().last, isA<ToolCallItem>());
  });
}
